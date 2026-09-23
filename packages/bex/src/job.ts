// Each job is one owner process, one CDP connection, and one private Unix socket.
// The socket (not a browser title or the on-disk snapshot) is the authority for a live job.
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { createServer, createConnection, type Socket } from "node:net";
import { existsSync, lstatSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { parentPort, Worker } from "node:worker_threads";
import vm from "node:vm";
import { Session } from "./cdp/session.js";
import type { HandoffData } from "./handoff.js";
import {
  BexError, awaitPin, capValue, classifyError, installPolicy, makeConsole,
  printEnvelope, resolveWsUrl, truncateLogs, type LogEntry, type PolicyState,
} from "./bex.js";

const MAX_MESSAGE = 1024 * 1024;
const DEFAULT_TIMEOUT = 60_000;
const MAX_TIMEOUT = 600_000;
const ID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
type Request = {
  op: "status" | "run" | "stop" | "action" | "handoff" | "release";
  code?: string; timeoutMs?: number; action?: Record<string, unknown>;
  reason?: string; expectedOrigin?: string; cleanUrl?: string; selector?: string;
};
type Reply = Record<string, unknown>;
type WorkerMessage = { type: string; seq?: number; result?: Reply; targetId?: string; windowId?: number; expectedOrigin?: string; error?: string; phase?: string; reason?: string };
type JobData = { kind: "job"; wsUrl: string; url: string };

function root(): string {
  const path = join(process.env.XDG_RUNTIME_DIR ?? `/tmp/bex-${process.getuid()}`, "bex", "jobs");
  mkdirSync(path, { recursive: true, mode: 0o700 });
  const stat = lstatSync(path);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077)) {
    throw new BexError("UNSAFE_RUNTIME", "Job directory must be a private directory owned by the current user.");
  }
  return path;
}
function dir(id: string): string {
  if (!ID.test(id)) throw new BexError("USAGE", "Invalid job id.");
  return join(root(), id);
}
function snapshot(path: string, state: Reply): void {
  writeFileSync(join(path, "state.json"), JSON.stringify(state), { mode: 0o600 });
}
function timeout(value: string | undefined): number {
  const n = value === undefined ? DEFAULT_TIMEOUT : Number(value);
  if (!Number.isInteger(n) || n < 1_000 || n > MAX_TIMEOUT) throw new BexError("USAGE", "--timeout must be an integer from 1000 to 600000 ms.");
  return n;
}
function send(socket: Socket, request: Request): Promise<Reply> {
  return new Promise((resolve, reject) => {
    let data = "";
    const timer = setTimeout(() => { socket.destroy(); reject(new BexError("JOB_UNRESPONSIVE", "Job did not respond.")); }, (request.timeoutMs ?? 5_000) + 10_000);
    const fail = (e: unknown) => { clearTimeout(timer); reject(e); };
    socket.on("error", fail);
    socket.on("data", (buf) => {
      data += buf.toString();
      if (data.length > MAX_MESSAGE) return fail(new BexError("JOB_PROTOCOL", "Oversized response."));
      const end = data.indexOf("\n");
      if (end < 0) return;
      clearTimeout(timer);
      socket.destroy();
      try { resolve(JSON.parse(data.slice(0, end)) as Reply); } catch { reject(new BexError("JOB_PROTOCOL", "Invalid response.")); }
    });
    socket.on("connect", () => socket.write(`${JSON.stringify(request)}\n`));
  });
}
function ask(id: string, request: Request): Promise<Reply> {
  return send(createConnection(join(dir(id), "control.sock")), request);
}

export async function cmdJob(args: string[]): Promise<void> {
  try {
    const [op, first, ...tail] = args;
    const handoff = op === "start" && first === "--handoff";
    const arg = handoff ? tail[0] : first;
    const rest = handoff ? tail.slice(1) : tail;
    if (op === "start") {
      if (!arg || rest.length || !(arg === "about:blank" && !handoff || /^https?:\/\//.test(arg))) throw new BexError("USAGE", "job start [--handoff] requires one http(s) URL (hidden jobs also accept about:blank).");
      // Resolve before forking: never leave an orphaned owner when the browser is unreachable.
      const wsUrl = await resolveWsUrl();
      const id = randomUUID();
      const path = dir(id);
      mkdirSync(path, { mode: 0o700 });
      const child = spawn(process.execPath, [fileURLToPath(import.meta.url), "__job-owner"], {
        detached: true, stdio: ["pipe", "pipe", "ignore"],
      });
      let line = "";
      const ready = new Promise<Reply>((resolve, reject) => {
        const timer = setTimeout(() => reject(new BexError("JOB_START_TIMEOUT", "Owner did not start in 25 seconds.")), 25_000);
        child.on("error", (e) => { clearTimeout(timer); reject(e); });
        child.on("exit", (code) => { clearTimeout(timer); reject(new BexError("JOB_START", `Owner exited (${code}) before ready.`)); });
        child.stdout!.on("data", (chunk) => {
          line += chunk.toString();
          const i = line.indexOf("\n");
          if (i < 0) return;
          clearTimeout(timer);
          try { resolve(JSON.parse(line.slice(0, i)) as Reply); } catch { reject(new BexError("JOB_PROTOCOL", "Invalid owner handshake.")); }
        });
      });
      child.stdin!.end(JSON.stringify({ id, wsUrl, url: arg, surface: handoff ? "handoff" : "hidden" }));
      try {
        const result = await ready;
        if (!result.ok) throw new BexError("JOB_START", String((result.error as { message?: string })?.message ?? "Owner failed."));
        printEnvelope(result);
      } catch (e) {
        child.kill();
        throw e;
      } finally {
        child.stdout?.destroy();
        child.unref();
      }
      return;
    }
    if (!arg || !ID.test(arg)) throw new BexError("USAGE", "Expected a job UUID.");
    if (op === "status" || op === "stop") {
      if (rest.length) throw new BexError("USAGE", "Unexpected arguments.");
      try { printEnvelope(await ask(arg, { op })); }
      catch (e) {
        if (op !== "status" || !["ENOENT", "ECONNREFUSED"].includes((e as NodeJS.ErrnoException).code ?? "") || !existsSync(join(dir(arg), "state.json"))) throw e;
        const lastKnown = JSON.parse(readFileSync(join(dir(arg), "state.json"), "utf8")) as Reply;
        printEnvelope({
          ok: true, id: arg, live: false,
          state: lastKnown.endedAt ? lastKnown.state : "DEAD_UNKNOWN",
          lastKnown,
          hint: "The owner socket is unreachable. This is a last-known snapshot, not a recovered page; never replay an unconfirmed side effect.",
        });
      }
      return;
    }
    if (op === "action") {
      if (rest.length !== 1) throw new BexError("USAGE", "job action <id> <json-file>.");
      const action = JSON.parse(readFileSync(rest[0], "utf8")) as Record<string, unknown>;
      if (!action || !["navigate", "exists", "click", "fill"].includes(String(action.type))) throw new BexError("USAGE", "Unknown declarative action.");
      const response = await ask(arg, { op, action, timeoutMs: 20_000 });
      printEnvelope(response);
      if (!response.ok) process.exitCode = 1;
      return;
    }
    if (op === "handoff" || op === "release") {
      if (op === "handoff" && (rest.length !== 1 || !rest[0])) throw new BexError("USAGE", "job handoff <id> <reason>.");
      if (op === "release" && (rest.length < 2 || rest.length > 3)) throw new BexError("USAGE", "job release <id> <origin> <clean-url> [selector].");
      const response = await ask(arg, op === "handoff"
        ? { op, reason: rest[0], timeoutMs: 20_000 }
        : { op, expectedOrigin: rest[0], cleanUrl: rest[1], selector: rest[2], timeoutMs: 20_000 });
      printEnvelope(response);
      if (!response.ok) process.exitCode = 1;
      return;
    }
    if (op === "run") {
      let file: string | undefined;
      let ms: number = DEFAULT_TIMEOUT;
      for (let i = 0; i < rest.length; i++) {
        if (rest[i] === "--timeout") ms = timeout(rest[++i]);
        else if (!file && !rest[i].startsWith("-")) file = rest[i];
        else throw new BexError("USAGE", "job run <id> [--timeout ms] <file>.");
      }
      if (!file) throw new BexError("USAGE", "job run requires a snippet file.");
      const code = readFileSync(file, "utf8");
      if (Buffer.byteLength(code) > MAX_MESSAGE / 2) throw new BexError("USAGE", "Snippet is too large.");
      const result = await ask(arg, { op, code, timeoutMs: ms });
      printEnvelope(result);
      if (!result.ok) process.exitCode = result.error && (result.error as { code?: string }).code === "TIMEOUT" ? 3 : 1;
      return;
    }
    throw new BexError("USAGE", "job start|run|action|handoff|release|status|stop");
  } catch (e) {
    printEnvelope({ ok: false, error: classifyError(e) });
    process.exitCode = 1;
  }
}

// The owner never accepts arbitrary target IDs or a browser URL from its control socket.
export async function jobOwner(args: string[]): Promise<void> {
  if (args.length) return;
  let worker: Worker | undefined;
  let server: ReturnType<typeof createServer> | undefined;
  let path = "";
  let id = "";
  let ready = false;
  let ended = false;
  let state: Reply = {};
  let sequence = 0;
  let uncertain = false;
  let queue = Promise.resolve();
  const waiters = new Map<number, (m: WorkerMessage) => void>();
  const reply = (socket: Socket, value: Reply) => { socket.end(`${JSON.stringify(value)}\n`); };
  const end = (reason: string) => {
    if (ended) return;
    ended = true;
    state = { ...state, state: reason, outcomeUnknown: uncertain || state.outcomeUnknown === true, endedAt: new Date().toISOString() };
    if (path) snapshot(path, state);
    for (const resolve of waiters.values()) resolve({ type: "ended", error: reason });
    waiters.clear();
    server?.close();
    worker?.terminate();
    // The socket is the live authority. Preserve snapshot only for diagnostics.
    setTimeout(() => process.exit(0), 100).unref();
  };
  try {
    let input = "";
    for await (const chunk of process.stdin) {
      input += chunk.toString();
      if (input.length > 32_000) throw new BexError("USAGE", "Oversized owner startup.");
    }
    const init = JSON.parse(input) as { id: string; wsUrl: string; url: string; surface?: string };
    const surface = init.surface === "handoff" ? "handoff" : "hidden";
    if (init.wsUrl !== await resolveWsUrl()) throw new BexError("CONNECT", "Browser endpoint changed during job startup.");
    id = init.id;
    path = dir(id);
    if (!lstatSync(path).isDirectory()) throw new BexError("UNSAFE_RUNTIME", "Invalid job directory.");
    worker = new Worker(new URL(import.meta.url), { workerData: surface === "handoff"
      ? { kind: "handoff", wsUrl: init.wsUrl, url: init.url } satisfies HandoffData
      : { kind: "job", wsUrl: init.wsUrl, url: init.url } satisfies JobData });
    state = { id, surface, state: "STARTING", startedAt: new Date().toISOString(), epoch: 1 };
    snapshot(path, state);
    worker.on("message", (m: WorkerMessage) => {
      if (m.type === "ready") {
        ready = true;
        state = { ...state, state: "AGENT_OWNED", targetId: m.targetId, ...(m.windowId !== undefined ? { windowId: m.windowId } : {}) };
        snapshot(path, state);
      } else if (m.type === "terminal") end(m.error ?? "BROWSER_GONE");
      else if (m.type === "phase") {
        state = { ...state, state: m.phase!, ...(m.reason ? { lastReason: m.reason } : {}) };
        snapshot(path, state);
      } else if (m.type === "mutated") state = { ...state, inFlightMayHaveEffect: true };
      else if (m.seq !== undefined) waiters.get(m.seq)?.(m);
    });
    worker.on("error", () => end("WORKER_CRASH"));
    worker.on("exit", () => { if (!ended) end("WORKER_CRASH"); });
    const deadline = Date.now() + 20_000;
    while (!ready && !ended && Date.now() < deadline) await sleep(25);
    if (!ready) throw new BexError("JOB_START", "Browser target did not become ready.");
    server = createServer((socket) => {
      let incoming = "";
      socket.on("data", (buf) => {
        incoming += buf.toString();
        if (incoming.length > MAX_MESSAGE) { reply(socket, { ok: false, error: { code: "JOB_PROTOCOL", message: "Request too large." } }); return; }
        const i = incoming.indexOf("\n");
        if (i < 0) return;
        socket.removeAllListeners("data");
        let request: Request;
        try { request = JSON.parse(incoming.slice(0, i)) as Request; }
        catch { reply(socket, { ok: false, error: { code: "JOB_PROTOCOL", message: "Invalid request." } }); return; }
        if (request.op === "status") { reply(socket, { ok: true, ...state }); return; }
        if (request.op === "stop" && surface === "hidden") {
          reply(socket, { ok: true, id, state: "STOPPED" });
          end("STOPPED");
          return;
        }
        // handoff surfaces accept only declarative operations; snippet runs are
        // structurally unavailable there, and window control stays in the worker.
        const valid = surface === "hidden"
          ? request.op === "run" && typeof request.code === "string"
          : ["action", "handoff", "release", "stop"].includes(request.op)
            && (request.op !== "action" || !!request.action)
            && (request.op !== "handoff" || typeof request.reason === "string")
            && (request.op !== "release" || typeof request.expectedOrigin === "string" && typeof request.cleanUrl === "string");
        const wait = request.timeoutMs ?? 5_000;
        if (!valid || !Number.isInteger(wait) || wait < 1_000 || wait > MAX_TIMEOUT) {
          reply(socket, { ok: false, error: { code: "JOB_PROTOCOL", message: "Operation is not available on this job surface." } }); return;
        }
        request.timeoutMs = wait;
        queue = queue.then(async () => {
          if (ended) { reply(socket, { ok: false, error: { code: "JOB_ENDED", message: "Job is no longer live." } }); return; }
          const seq = ++sequence;
          if (surface === "hidden") {
            state = { ...state, state: "RUNNING", inFlightMayHaveEffect: false };
            snapshot(path, state);
          }
          const result = await new Promise<WorkerMessage>((resolve) => {
            const timer = setTimeout(() => {
              waiters.delete(seq);
              resolve({ type: "timeout", error: "TIMEOUT" });
            }, request.timeoutMs);
            waiters.set(seq, (m) => { clearTimeout(timer); waiters.delete(seq); resolve(m); });
            worker!.postMessage({ ...request, seq, type: request.op });
          });
          if (result.type === "timeout" || result.type === "ended") {
            uncertain = true;
            reply(socket, { ok: false, id, outcomeUnknown: true, error: { code: result.error, message: "Job ended during a command; its effect may be unknown. Never replay a side effect blindly." } });
            end(result.error ?? "WORKER_CRASH");
          } else {
            reply(socket, { id, ...result.result });
            if (request.op === "stop" && result.result?.ok) { end("STOPPED"); return; }
            uncertain ||= result.result?.outcomeUnknown === true;
            if (surface === "hidden") state = { ...state, state: "AGENT_OWNED", epoch: Number(state.epoch) + 1 };
            if (request.op === "release" && result.result?.ok) state = { ...state, epoch: Number(state.epoch) + 1 };
            state = { ...state, outcomeUnknown: uncertain, inFlightMayHaveEffect: false };
            snapshot(path, state);
          }
        }).catch(() => end("WORKER_CRASH"));
      });
    });
    await new Promise<void>((resolve, reject) => { server!.once("error", reject); server!.listen(join(path, "control.sock"), resolve); });
    process.stdout.write(`${JSON.stringify({ ok: true, id, surface, state: "AGENT_OWNED" })}\n`);
    process.on("SIGTERM", () => end("KILLED"));
    process.on("SIGINT", () => end("KILLED"));
  } catch (e) {
    process.stdout.write(`${JSON.stringify({ ok: false, error: classifyError(e) })}\n`);
    end("START_FAILED");
  }
}

// The worker owns the only CDP connection. Every command receives a fresh, revocable
// facade; late timers, event callbacks and unawaited promises cannot write in a later epoch.
export async function jobWorker(data: JobData): Promise<void> {
  const st: PolicyState = { owned: new Set(), candidates: [], mutated: false, crashed: false, bootstrap: true };
  const session = new Session();
  try {
    await session.connect({ wsUrl: data.wsUrl, timeoutMs: 15_000 });
    installPolicy(session, st);
    const { targetId } = (await session.Target.createTarget({ url: "about:blank" })) as { targetId: string };
    await session.use(targetId);
    await session.Runtime.enable({});
    if (data.url === "about:blank") await session.Page.navigate({ url: "data:text/html," });
    await session.Page.navigate({ url: data.url });
    await awaitPin(session._call.bind(session), st);
    st.bootstrap = false;
    parentPort?.postMessage({ type: "ready", targetId });
    const monitor = setInterval(async () => {
      if (!session.isConnected()) { parentPort?.postMessage({ type: "terminal", error: "BROWSER_GONE" }); return; }
      if (st.crashed) { parentPort?.postMessage({ type: "terminal", error: "TARGET_CRASHED" }); return; }
      try {
        const { targetInfos } = (await session.Target.getTargets({})) as { targetInfos: Array<{ targetId: string }> };
        if (!targetInfos.some((t) => t.targetId === targetId)) parentPort?.postMessage({ type: "terminal", error: "TARGET_GONE" });
      } catch { if (!session.isConnected()) parentPort?.postMessage({ type: "terminal", error: "BROWSER_GONE" }); }
    }, 2_000);
    monitor.unref();
    parentPort?.on("message", async (m: { type: string; seq: number; code: string }) => {
      if (m.type !== "run") return;
      const logs: LogEntry[] = [];
      let active = true;
      const timers = new Set<ReturnType<typeof setTimeout>>();
      const pending = new Set<Promise<unknown>>();
      const listeners = new Set<() => void>();
      const guard = () => { if (!active) throw new BexError("STALE_EPOCH", "Command has ended; its write capability was revoked."); };
      const facade: Record<string, unknown> = {
        resetContextPin: () => { guard(); return awaitPin(session._call.bind(session), st); },
        onEvent: (fn: (method: string, params: unknown) => void) => {
          guard();
          const unsubscribe = session.onEvent((method, params, sid) => {
            if (active && sid === session.getActiveSession()) fn(method, params);
          });
          listeners.add(unsubscribe);
          return () => { unsubscribe(); listeners.delete(unsubscribe); };
        },
        waitFor: (method: string, predicate?: (p: unknown) => boolean, timeoutMs = 30_000) => {
          guard();
          return new Promise((resolve, reject) => {
            const stop = session.onEvent((event, params, sid) => {
              if (!active || sid !== session.getActiveSession() || event !== method || (predicate && !predicate(params))) return;
              clearTimeout(timer); stop(); listeners.delete(stop); resolve(params);
            });
            listeners.add(stop);
            const timer = setTimeout(() => { stop(); listeners.delete(stop); reject(new BexError("EVENT_TIMEOUT", `Timed out waiting for ${method}.`)); }, timeoutMs);
            timers.add(timer);
          });
        },
      };
      for (const domain of Object.keys(session.domains)) {
        facade[domain] = new Proxy({}, { get: (_obj, method) => {
          if (typeof method !== "string") return undefined;
          return (params: unknown = {}) => {
            guard();
            if (domain === "Target" || (domain === "Page" && method === "captureScreenshot")) throw new BexError("NOT_ALLOWED", "Jobs only operate their own attached hidden page; screenshots cannot paint on hidden pages.");
            const p = session._call(`${domain}.${method}`, params as Record<string, unknown>);
            pending.add(p);
            void p.finally(() => pending.delete(p)).catch(() => undefined);
            return p;
          };
        } });
      }
      const runTimer = (fn: (...args: unknown[]) => void, ms: number) => {
        guard();
        const t = setTimeout(() => { timers.delete(t); if (active) fn(); }, ms);
        timers.add(t);
        return t;
      };
      try {
        st.mutated = false;
        const con = makeConsole(logs);
        const ctx = vm.createContext({ session: facade, console: con, setTimeout: runTimer, clearTimeout: (t: ReturnType<typeof setTimeout>) => { clearTimeout(t); timers.delete(t); }, queueMicrotask });
        const make = vm.compileFunction(`return async (session, console) => {\n${m.code}\n;}`, [], { parsingContext: ctx }) as () => (s: unknown, c: unknown) => Promise<unknown>;
        const value = await make()(facade, con);
        await Promise.allSettled([...pending]);
        parentPort?.postMessage({ type: "result", seq: m.seq, result: { ok: true, ...capValue(value), ...truncateLogs(logs) } });
      } catch (e) {
        await Promise.allSettled([...pending]);
        parentPort?.postMessage({ type: "result", seq: m.seq, result: {
          ok: false, outcomeUnknown: st.mutated || undefined,
          error: classifyError(e), logs: truncateLogs(logs).logs,
        } });
      } finally {
        active = false;
        for (const t of timers) clearTimeout(t);
        for (const stop of listeners) stop();
      }
    });
  } catch (e) {
    parentPort?.postMessage({ type: "terminal", error: classifyError(e).code });
  }
}
