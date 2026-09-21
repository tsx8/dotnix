// bex — CDP-generic browser snippet runner: run / targets / shot / api.
// 零浏览器特有逻辑：端点与拉起命令来自环境变量（BU_CDP_URL / BU_CDP_LAUNCH），
// 由 NixOS 包装脚本覆盖式固化，CLI 不提供任何指向其他浏览器的入口。

import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { isMainThread, parentPort, workerData, Worker } from "node:worker_threads";
import vm from "node:vm";
import { Session } from "@cdp/session";
import browserProtocol from "@cdp/browser-protocol";
import jsProtocol from "@cdp/js-protocol";

const PROG = "bex";
const DEFAULT_TIMEOUT_MS = 60_000;
const MAX_TIMEOUT_MS = 600_000;
const CONNECT_TIMEOUT_MS = 20_000;
const VALUE_MAX_BYTES = 20_000;
const LOGS_MAX_BYTES = 8_192;
const LOG_ENTRY_MAX = 1_000;
const LOG_MAX_ENTRIES = 200;

class BexError extends Error {
  code: string;
  hint?: string;
  constructor(code: string, message: string, hint?: string) {
    super(message);
    this.code = code;
    this.hint = hint;
  }
}

type LogEntry = { level: string; text: string };
type ShotMeta = { path: string; bytes: number };

function usage(): never {
  process.stderr.write(`usage:
  ${PROG} run [-t targetId] [--timeout ms] <file>   run a snippet (async function body)
  ${PROG} targets [--table]                         list browser pages (JSON by default)
  ${PROG} shot -t targetId [-o path]                viewport PNG + size/DPR metadata
  ${PROG} api [--domain D] [--method M]             CDP surface from the vendored protocol

snippet contract: the file is an async function body, not an ES module —
top-level await yes; static import / require / fs / net / process are absent by
design (vm sandbox). In scope: session (pre-connected CDP Session, every CDP
domain is a property, e.g. await session.Target.getTargets({})), console,
setTimeout/clearTimeout. Return a JSON-serializable value; it arrives in the
envelope as "value".
`);
  process.exit(2);
}

// ---------- endpoint resolution (http -> live wsUrl, auto-launch once) ----------

async function resolveWsUrl(): Promise<string> {
  const env = process.env.BU_CDP_URL;
  if (!env) {
    throw new BexError(
      "CONNECT",
      "BU_CDP_URL is not set.",
      "This deployment pins BU_CDP_URL in the system wrapper; run bex through it.",
    );
  }
  if (/^wss?:\/\//i.test(env)) return env;
  if (!/^http:\/\//i.test(env)) {
    throw new BexError("CONNECT", `Unsupported BU_CDP_URL scheme: ${env}`, "Use ws:// or http://.");
  }
  const endpoint = env.replace(/\/+$/, "");
  const launch = process.env.BU_CDP_LAUNCH;
  const deadline = Date.now() + CONNECT_TIMEOUT_MS;
  let launched = false;
  let lastErr: unknown = new Error("endpoint never became ready");
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`${endpoint}/json/version`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const info = (await res.json()) as { webSocketDebuggerUrl?: string };
      if (!info.webSocketDebuggerUrl) throw new Error("endpoint returned no webSocketDebuggerUrl");
      return info.webSocketDebuggerUrl;
    } catch (error) {
      lastErr = error;
      if (launch && !launched) {
        launched = true;
        try {
          const child = spawn(launch, { detached: true, stdio: "ignore" });
          child.unref();
        } catch (launchError) {
          lastErr = launchError;
          break;
        }
      }
      await new Promise((r) => setTimeout(r, 250));
    }
  }
  const hint = launch
    ? `Tried auto-starting "${launch}". If the browser is already running without its debug port, restart it. `
    : "";
  throw new BexError(
    "CONNECT",
    `Browser endpoint ${endpoint} unreachable (${String(lastErr)}). ${hint}Do not start or connect to any other browser; report this error instead.`,
  );
}

// ---------- shared helpers ----------

function shotDir(): string {
  const dir = process.env.BEX_SHOT_DIR ?? `${process.env.XDG_RUNTIME_DIR ?? "/tmp"}/${PROG}`;
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  return dir;
}

function safeStringify(value: unknown): string | undefined {
  try {
    return JSON.stringify(value, (_k, v) => (typeof v === "bigint" ? String(v) : v));
  } catch {
    return undefined;
  }
}

function truncateLogs(logs: LogEntry[]): { logs: LogEntry[]; truncated: boolean } {
  let total = 0;
  for (let i = 0; i < logs.length; i++) {
    const bytes = Buffer.byteLength(logs[i].text);
    if (total + bytes > LOGS_MAX_BYTES || i >= LOG_MAX_ENTRIES) {
      return { logs: logs.slice(0, i), truncated: true };
    }
    total += bytes;
  }
  return { logs, truncated: false };
}

function capValue(value: unknown): { value: unknown; truncated: boolean } {
  const s = safeStringify(value);
  if (s === undefined) {
    return {
      value: { bexNote: "value not JSON-serializable", preview: String(value).slice(0, 200) },
      truncated: false,
    };
  }
  if (Buffer.byteLength(s) <= VALUE_MAX_BYTES) return { value, truncated: false };
  return {
    value: { bexTruncated: true, originalBytes: Buffer.byteLength(s), head: s.slice(0, VALUE_MAX_BYTES) },
    truncated: true,
  };
}

function classifyError(e: unknown): { code: string; message: string; hint?: string } {
  if (e instanceof BexError) return { code: e.code, message: e.message, hint: e.hint };
  const message = e instanceof Error ? e.message : String(e);
  const stack = e instanceof Error ? (e.stack ?? "").split("\n").slice(0, 3).join("\n") : undefined;
  if (/emit is not defined/.test(message)) {
    return {
      code: "NO_EMIT",
      message,
      hint: "bex snippets have no emit(); return a JSON-serializable value, or console.log for intermediate output.",
    };
  }
  if (/session\.send is not a function/.test(message)) {
    return {
      code: "API_SHAPE",
      message,
      hint: "CDP calls are session.Domain.method(params), e.g. `await session.Target.getTargets({})`. Run `bex api` for the full surface.",
    };
  }
  if (/window is not defined|document is not defined/.test(message)) {
    return {
      code: "PAGE_CONTEXT",
      message,
      hint: "The snippet runs in Node, not in the page. Page code goes through `await session.Runtime.evaluate({ expression, returnByValue: true })`.",
    };
  }
  if (/No target with given id/i.test(message)) {
    return {
      code: "TARGET_GONE",
      message,
      hint: "That tab no longer exists. Run `bex targets` and re-resolve the page.",
    };
  }
  if (/Not connected/i.test(message)) {
    return { code: "NOT_CONNECTED", message, hint: "bex connects for you; this happens only if the browser died mid-run. Retry the command." };
  }
  if (e instanceof SyntaxError) {
    return { code: "SYNTAX", message, hint: stack };
  }
  return { code: "SCRIPT_ERROR", message, hint: stack };
}

function printEnvelope(envelope: Record<string, unknown>): void {
  process.stdout.write(`${JSON.stringify(envelope)}\n`);
}

// ---------- `run` worker: vm sandbox + screenshot interception ----------

type RunData = { wsUrl: string; targetId?: string; code: string; dir: string };

function makeConsole(logs: LogEntry[]): Console {
  const emit = (level: string) => (...args: unknown[]) => {
    if (logs.length >= LOG_MAX_ENTRIES) {
      if (logs.length === LOG_MAX_ENTRIES) logs.push({ level: "warn", text: "[bex] log limit reached; further logs dropped" });
      return;
    }
    const text = args
      .map((a) => (typeof a === "string" ? a : (safeStringify(a) ?? String(a))))
      .join(" ")
      .slice(0, LOG_ENTRY_MAX);
    logs.push({ level, text });
  };
  return Object.assign(Object.create(console), {
    log: emit("log"),
    info: emit("info"),
    warn: emit("warn"),
    error: emit("error"),
  }) as Console;
}

async function workerRun(data: RunData): Promise<void> {
  const post = (m: unknown) => parentPort?.postMessage(m);
  const started = Date.now();
  const logs: LogEntry[] = [];
  const screenshots: ShotMeta[] = [];
  try {
    post({ type: "phase", phase: "connect" });
    const session = new Session();
    // 拦截截图写入运行时目录：片段收到 savedTo 而非 base64（onCallResult 先于
    // resolve 触发，修改 result 对象对片段可见）。
    session.onCallResult((method, _params, result) => {
      const r = result as { data?: string } | null;
      if (method === "Page.captureScreenshot" && r && typeof r.data === "string") {
        const path = `${data.dir}/shot-${Date.now()}-${String(screenshots.length + 1).padStart(2, "0")}.png`;
        const buf = Buffer.from(r.data, "base64");
        writeFileSync(path, buf, { mode: 0o600 });
        screenshots.push({ path, bytes: buf.length });
        delete r.data;
        (r as { savedTo?: string }).savedTo = path;
      }
    });
    await session.connect({ wsUrl: data.wsUrl, timeoutMs: CONNECT_TIMEOUT_MS });

    let sessionId: string | undefined;
    if (data.targetId) {
      post({ type: "phase", phase: "attach" });
      sessionId = await session.use(data.targetId);
    }
    post({ type: "phase", phase: "script" });

    // vm 沙箱：仅 session/console/定时器。fs/net/process/require 不进上下文，
    // 片段可触达的世界只有目标浏览器。
    const sandboxConsole = makeConsole(logs);
    const ctx = vm.createContext({
      session,
      console: sandboxConsole,
      setTimeout,
      clearTimeout,
      queueMicrotask,
    });
    const make = vm.compileFunction(`return async (session, console) => {\n${data.code}\n;}`, [], {
      parsingContext: ctx,
    }) as () => (s: unknown, c: unknown) => Promise<unknown>;
    const value = await make()(session, sandboxConsole);

    const capped = capValue(value);
    const cappedLogs = truncateLogs(logs);
    post({
      type: "done",
      envelope: {
        ok: true,
        targetId: data.targetId ?? null,
        ...capped,
        ...cappedLogs,
        screenshots,
        elapsedMs: Date.now() - started,
      },
    });
  } catch (e) {
    post({
      type: "done",
      envelope: {
        ok: false,
        targetId: data.targetId ?? null,
        error: classifyError(e),
        logs: truncateLogs(logs).logs,
        screenshots,
        elapsedMs: Date.now() - started,
      },
    });
  }
}

function cmdRun(args: string[]): void {
  let targetId: string | undefined;
  let timeoutMs = DEFAULT_TIMEOUT_MS;
  let file: string | undefined;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "-t" || a === "--target") targetId = args[++i];
    else if (a === "--timeout") {
      timeoutMs = Number(args[++i]);
      if (!Number.isFinite(timeoutMs)) usage();
    } else if (!file && !a.startsWith("-")) file = a;
    else usage();
  }
  if (!file) usage();
  timeoutMs = Math.min(Math.max(Math.trunc(timeoutMs), 1_000), MAX_TIMEOUT_MS);

  let code: string;
  try {
    code = readFileSync(file, "utf8");
  } catch (e) {
    printEnvelope({ ok: false, error: { code: "USAGE", message: `cannot read ${file}: ${String(e)}` } });
    process.exit(2);
  }

  resolveWsUrl().then((wsUrl) => {
    const worker = new Worker(new URL(import.meta.url), {
      workerData: { wsUrl, targetId, code, dir: shotDir() } satisfies RunData,
    });
    let phase = "connect";
    let printed = false;
    const finish = (envelope: Record<string, unknown>, exitCode: number) => {
      if (printed) return;
      printed = true;
      printEnvelope(envelope);
      worker.terminate();
      process.exit(exitCode);
    };
    const timer = setTimeout(() => {
      finish(
        {
          ok: false,
          targetId: targetId ?? null,
          error: {
            code: "TIMEOUT",
            phase,
            message: `run exceeded ${timeoutMs}ms and was force-terminated during phase "${phase}".`,
            hint: "Raise --timeout (max 600000) or shorten the script; long waits belong inside one run.",
          },
        },
        3,
      );
    }, timeoutMs);
    worker.on("message", (m: { type: string; phase?: string; envelope?: Record<string, unknown> }) => {
      if (m.type === "phase" && m.phase) phase = m.phase;
      if (m.type === "done" && m.envelope) {
        clearTimeout(timer);
        finish(m.envelope, m.envelope.ok ? 0 : 1);
      }
    });
    worker.on("error", (e) => {
      clearTimeout(timer);
      finish({ ok: false, error: { code: "WORKER_CRASH", message: String(e) } }, 1);
    });
    worker.on("exit", (code) => {
      clearTimeout(timer);
      finish({ ok: false, error: { code: "WORKER_CRASH", message: `worker exited unexpectedly (code ${code})` } }, 1);
    });
  }).catch((e) => {
    printEnvelope({ ok: false, error: classifyError(e) });
    process.exit(1);
  });
}

// ---------- `targets` ----------

async function cmdTargets(table: boolean): Promise<void> {
  const wsUrl = await resolveWsUrl();
  const session = new Session();
  await session.connect({ wsUrl, timeoutMs: CONNECT_TIMEOUT_MS });
  const { targetInfos } = (await session.Target.getTargets({})) as {
    targetInfos: Array<{ targetId: string; type: string; url: string; title?: string }>;
  };
  const pages = targetInfos
    .filter((t) => t.type === "page")
    .map((t) => ({ targetId: t.targetId, url: t.url, title: t.title ?? "" }));
  session.close();
  if (table) {
    for (const p of pages) process.stdout.write(`${p.targetId}  ${p.url.slice(0, 60).padEnd(60)}  ${p.title.slice(0, 40)}\n`);
  } else {
    printEnvelope({ ok: true, pages });
  }
  process.exit(0);
}

// ---------- `shot` ----------

async function cmdShot(targetId: string | undefined, out: string | undefined): Promise<void> {
  if (!targetId) {
    printEnvelope({ ok: false, error: { code: "USAGE", message: "shot requires -t <targetId>", hint: "Run `bex targets` to list pages." } });
    process.exit(2);
  }
  const wsUrl = await resolveWsUrl();
  const session = new Session();
  await session.connect({ wsUrl, timeoutMs: CONNECT_TIMEOUT_MS });
  try {
    await session.use(targetId);
    const vp = await session.Runtime.evaluate({
      expression: "JSON.stringify({ w: window.innerWidth, h: window.innerHeight, dpr: window.devicePixelRatio })",
      returnByValue: true,
    });
    const { w, h, dpr } = JSON.parse((vp as { result: { value: string } }).result.value) as {
      w: number;
      h: number;
      dpr: number;
    };
    const shot = (await session.Page.captureScreenshot({ format: "png" })) as { data: string };
    const buf = Buffer.from(shot.data, "base64");
    const path = out ?? `${shotDir()}/shot-${Date.now()}.png`;
    writeFileSync(path, buf, { mode: 0o600 });
    printEnvelope({
      ok: true,
      targetId,
      path,
      bytes: buf.length,
      viewport: { width: w, height: h },
      pixels: { width: Math.round(w * dpr), height: Math.round(h * dpr) },
      devicePixelRatio: dpr,
    });
    process.exit(0);
  } finally {
    session.close();
  }
}

// ---------- `api` ----------

type Param = { name: string; type?: string; description?: string; optional?: boolean };
type Command = { name: string; description?: string; parameters?: Param[] };
type Domain = { domain: string; description?: string; commands?: Command[]; events?: unknown[] };

const DOMAINS: Domain[] = [
  ...(browserProtocol as { domains: Domain[] }).domains,
  ...(jsProtocol as { domains: Domain[] }).domains,
].sort((a, b) => a.domain.localeCompare(b.domain));

function firstLine(s: string | undefined, max = 78): string {
  const line = (s ?? "").split("\n")[0].trim();
  return line.length > max ? `${line.slice(0, max - 1)}…` : line;
}

function cmdApi(domain?: string, method?: string): void {
  if (!domain) {
    for (const d of DOMAINS) process.stdout.write(`${d.domain.padEnd(22)} ${firstLine(d.description)}\n`);
    process.stdout.write(`\n${DOMAINS.length} domains. Detail: ${PROG} api --domain <D> [--method <M>]. Events: session.onEvent / session.waitFor.\n`);
    return;
  }
  const d = DOMAINS.find((x) => x.domain === domain);
  if (!d) {
    printEnvelope({ ok: false, error: { code: "USAGE", message: `unknown domain "${domain}"`, hint: "Run `bex api` to list domains." } });
    process.exit(2);
  }
  if (!method) {
    process.stdout.write(`${domain} — ${firstLine(d.description, 200)}\n\nmethods (call as session.${domain}.<name>(params)):\n`);
    for (const c of d.commands ?? []) {
      const params = (c.parameters ?? []).map((p) => (p.optional ? `[${p.name}]` : p.name)).join(", ");
      process.stdout.write(`  ${c.name}(${params}) — ${firstLine(c.description)}\n`);
    }
    process.stdout.write(`\n${(d.commands ?? []).length} methods, ${(d.events ?? []).length} events (session.onEvent). Method detail: ${PROG} api --domain ${domain} --method <M>.\n`);
    return;
  }
  const c = (d.commands ?? []).find((x) => x.name === method);
  if (!c) {
    printEnvelope({ ok: false, error: { code: "USAGE", message: `unknown method "${domain}.${method}"` } });
    process.exit(2);
  }
  process.stdout.write(`session.${domain}.${method}\n${c.description ?? ""}\n\n`);
  if (c.parameters?.length) {
    process.stdout.write("params:\n");
    for (const p of c.parameters) {
      const req = p.optional ? "optional" : "required";
      process.stdout.write(`  ${p.name}: ${p.type ?? "any"} (${req}) — ${firstLine(p.description, 120)}\n`);
    }
  } else {
    process.stdout.write("params: none\n");
  }
  process.stdout.write(`\nexample: await session.${domain}.${method}({${(c.parameters ?? [])
    .filter((p) => !p.optional)
    .slice(0, 3)
    .map((p) => `${p.name}: …`)
    .join(", ")}})\n`);
}

// ---------- main ----------

function main(): void {
  // 管道下游提前退出（如 `bex api | head`）不应变成 EPIPE 崩溃。
  process.stdout?.on?.("error", (e: NodeJS.ErrnoException) => {
    if (e.code === "EPIPE") process.exit(0);
    throw e;
  });
  const [cmd, ...rest] = process.argv.slice(2);
  if (!cmd || cmd === "-h" || cmd === "--help") usage();
  if (cmd === "run") return cmdRun(rest);
  if (cmd === "api") {
    let domain: string | undefined;
    let method: string | undefined;
    for (let i = 0; i < rest.length; i++) {
      if (rest[i] === "--domain") domain = rest[++i];
      else if (rest[i] === "--method") method = rest[++i];
      else usage();
    }
    return cmdApi(domain, method);
  }
  if (cmd === "targets") return void cmdTargets(rest.includes("--table")).catch((e) => {
    printEnvelope({ ok: false, error: classifyError(e) });
    process.exit(1);
  });
  if (cmd === "shot") {
    let targetId: string | undefined;
    let out: string | undefined;
    for (let i = 0; i < rest.length; i++) {
      if (rest[i] === "-t" || rest[i] === "--target") targetId = rest[++i];
      else if (rest[i] === "-o" || rest[i] === "--out") out = rest[++i];
      else usage();
    }
    return void cmdShot(targetId, out).catch((e) => {
      printEnvelope({ ok: false, error: classifyError(e) });
      process.exit(1);
    });
  }
  usage();
}

if (isMainThread) {
  main();
} else {
  void workerRun(workerData as RunData);
}
