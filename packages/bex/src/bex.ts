// bex — CDP-generic browser runner: transactions and owned, volatile jobs.
// 零浏览器特有逻辑：端点与拉起命令来自环境变量（BU_CDP_URL / BU_CDP_LAUNCH），
// 由 NixOS 包装脚本覆盖式固化，CLI 不提供任何指向其他浏览器的入口。
//
// Gate A（纯自动化）契约：
// - 页面工作走隐形事务：--tab 创建 hidden target，run 结束随连接销毁（无跨 run 持久）。
// - 常规 CDP API 受 provenance/域策略约束；vm 不是恶意 JS 的安全沙箱，
//   只接收受信任的片段，绝不在可交接凭据页面运行任意片段。
// - Runtime.evaluate 钉 uniqueContextId：导航后显式失败（CONTEXT_DESTROYED），
//   不静默落入新 document；session.resetContextPin() 供刻意导航后重新钉扎。
// - 超时/崩溃若发生在副作用派发之后，envelope 标记 outcomeUnknown（防重放）。
// - -t / shot 是人工通道：默认 RESTRICTED，BEX_UNRESTRICTED=1 解锁且不装策略。

import { spawn } from "node:child_process";
import { cmdJob, jobOwner, jobWorker } from "./job.js";
import { handoffWorker } from "./handoff.js";
import { closeSync, mkdirSync, openSync, readFileSync, statSync, unlinkSync, writeFileSync, writeSync } from "node:fs";
import { isMainThread, parentPort, workerData, Worker } from "node:worker_threads";
import vm from "node:vm";
// CDP transport and protocol definitions are vendored from pi-chrome-use in ./cdp/.
import { Session } from "./cdp/session.js";
import browserProtocol from "./cdp/browser_protocol.json";
import jsProtocol from "./cdp/js_protocol.json";

const PROG = "bex";
const DEFAULT_TIMEOUT_MS = 60_000;
const MAX_TIMEOUT_MS = 600_000;
const CONNECT_TIMEOUT_MS = 20_000;
const VALUE_MAX_BYTES = 20_000;
const LOGS_MAX_BYTES = 8_192;
const LOG_ENTRY_MAX = 1_000;
const LOG_MAX_ENTRIES = 200;
const LAUNCH_LOCK_STALE_MS = 15_000;

export class BexError extends Error {
  code: string;
  hint?: string;
  constructor(code: string, message: string, hint?: string) {
    super(message);
    this.code = code;
    this.hint = hint;
  }
}

export type LogEntry = { level: string; text: string };
type ShotMeta = { path: string; bytes: number };

function usage(): never {
  process.stderr.write(`usage:
  ${PROG} run [--tab <url>] [--timeout ms] <file>   run a snippet in a hidden throwaway tab
  ${PROG} run [-t targetId] [--timeout ms] <file>   attach an existing target (BEX_UNRESTRICTED=1)
  ${PROG} job start <url>                           start an owned, volatile hidden page
  ${PROG} job start --handoff <url>                 start a parked handoff window (no snippets)
  ${PROG} job run <id> [--timeout ms] <file>        serialize a hidden-page snippet
  ${PROG} job action <id> <json-file>               declarative handoff-page action
  ${PROG} job handoff <id> <reason>                 revoke writes and show the window
  ${PROG} job release <id> <origin> <clean-url> [sel]  verify, clear and re-park
  ${PROG} job status <id>                          inspect live state or last-known snapshot
  ${PROG} job stop <id>                            destroy the job and its page
  ${PROG} targets [--table]                         list browser pages (JSON by default)
  ${PROG} shot -t targetId [-o path]                viewport PNG (BEX_UNRESTRICTED=1)
  ${PROG} api [--domain D] [--method M]             CDP surface from the vendored protocol

snippet contract: the file is an async function body, not an ES module —
top-level await yes; static import / require are not in scope. The vm is not
a security sandbox for untrusted JS. In scope: session (pre-connected CDP Session, every CDP
domain is a property, e.g. await session.Target.getTargets({})), console,
setTimeout/clearTimeout. Return a JSON-serializable value; it arrives in the
envelope as "value".

--tab mode: the tab is created hidden, owned by this run, and destroyed when the
run ends. Page state that outlives a run must live in the application itself
(conversation URLs etc.). Snippets may create further tabs via
session.Target.createTarget — they are forced hidden and auto-destroyed the same
way. Only targets created by this run can be attached or closed; Storage.* and
window operations are denied at the tool level. Evaluations are pinned to the
attached document's execution context: after navigation they fail with
CONTEXT_DESTROYED — call: await session.resetContextPin() after deliberate
navigation, then re-derive page state.
`);
  process.exit(2);
}

// ---------- endpoint resolution (http -> live wsUrl, auto-launch once) ----------

// 冷启动竞态：多个 bex 并发时只允许一个进程 spawn 拉起命令。O_EXCL 锁 +
// 陈旧检测（持锁进程死亡时由 mtime 兜底），无运行时依赖。
function acquireLaunchLock(dir: string): boolean {
  const lock = `${dir}/launch.lock`;
  const attempt = (): boolean => {
    try {
      const fd = openSync(lock, "wx");
      writeSync(fd, String(process.pid));
      closeSync(fd);
      return true;
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === "EEXIST") return false;
      throw e;
    }
  };
  if (attempt()) return true;
  try {
    if (Date.now() - statSync(lock).mtimeMs > LAUNCH_LOCK_STALE_MS) {
      unlinkSync(lock);
      return attempt();
    }
  } catch {
    // 锁文件消失即重试一次
    return attempt();
  }
  return false;
}

export async function resolveWsUrl(): Promise<string> {
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
  const lockDir = `${process.env.XDG_RUNTIME_DIR ?? "/tmp"}/${PROG}`;
  let launched = false;
  let holdLock = false;
  let lastErr: unknown = new Error("endpoint never became ready");
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`${endpoint}/json/version`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const info = (await res.json()) as { webSocketDebuggerUrl?: string };
      if (!info.webSocketDebuggerUrl) throw new Error("endpoint returned no webSocketDebuggerUrl");
      if (holdLock) {
        try { unlinkSync(`${lockDir}/launch.lock`); } catch { /* 已被清理 */ }
      }
      return info.webSocketDebuggerUrl;
    } catch (error) {
      lastErr = error;
      if (launch && !launched) {
        mkdirSync(lockDir, { recursive: true, mode: 0o700 });
        if (acquireLaunchLock(lockDir)) {
          holdLock = true;
          launched = true;
          try {
            const child = spawn(launch, { detached: true, stdio: "ignore" });
            child.unref();
          } catch (launchError) {
            lastErr = launchError;
            try { unlinkSync(`${lockDir}/launch.lock`); } catch { /* 同上 */ }
            break;
          }
        } else {
          // 其他进程持锁拉起中，本进程只等待端点就绪
          launched = true;
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

export function shotDir(): string {
  const dir = process.env.BEX_SHOT_DIR ?? `${process.env.XDG_RUNTIME_DIR ?? "/tmp"}/${PROG}`;
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  return dir;
}

// 并发进程同毫秒生成同名截图的碰撞由 pid + 随机后缀消除
function shotName(prefix: string): string {
  return `${prefix}-${Date.now()}-${process.pid.toString(36)}-${Math.random().toString(36).slice(2, 8)}.png`;
}

export function safeStringify(value: unknown): string | undefined {
  try {
    return JSON.stringify(value, (_k, v) => (typeof v === "bigint" ? String(v) : v));
  } catch {
    return undefined;
  }
}

export function truncateLogs(logs: LogEntry[]): { logs: LogEntry[]; truncated: boolean } {
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

export function capValue(value: unknown): { value: unknown; truncated: boolean } {
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

export function classifyError(e: unknown): { code: string; message: string; hint?: string } {
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
      hint: "That tab no longer exists. Hidden tabs die with their run; state that must outlive a run belongs to the application (URLs).",
    };
  }
  if (/unique.?context/i.test(message) || /default execution context/i.test(message) || /execution context .*(destroyed|cleared|not found)/i.test(message)) {
    return {
      code: "CONTEXT_DESTROYED",
      message,
      hint: "The attached document was navigated or replaced; the pinned execution context is gone. After a deliberate navigation call session.resetContextPin(), then re-derive page state.",
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

export function printEnvelope(envelope: Record<string, unknown>): void {
  process.stdout.write(`${JSON.stringify(envelope)}\n`);
}

// ---------- 常规 CDP 调用保护（不构成不可信 JS 的安全沙箱） ----------

export type PolicyState = {
  owned: Set<string>;
  pinnedUniqueId?: string;
  candidates: Array<{ id: string; frameId: string }>; // 最近在前；仅主帧候选能钉扎
  mutated: boolean;
  crashed: boolean;
  bootstrap: boolean;
};

// 只在 run 的 worker 内安装；拦截一切 CDP 调用（bindDomains 统一走 _call）。
export function installPolicy(session: Session, st: PolicyState): void {
  const orig = session._call.bind(session);
  const deny = (code: string, what: string, hint?: string) =>
    Promise.reject(new BexError(code, `${what} is denied by bex policy.`, hint));
  session._call = async (method: string, params: Record<string, unknown> = {}) => {
    // 任意页面命令（包括 JS 求值）都可能触发副作用；无法证明未执行就保守标未知。
    // 引导导航与钉扎探测走 orig，不计入用户命令。
    if (!st.bootstrap && !st.mutated && !["Target.getTargets", "Target.getTargetInfo", "Browser.getVersion"].includes(method)) {
      st.mutated = true;
      parentPort?.postMessage({ type: "mutated" });
    }
    if (method === "Target.createTarget") {
      // 不能用 newWindow/focus 等参数把页面变为可见；只接收 URL。
      if (Object.keys(params).some((key) => !["url", "background"].includes(key))) {
        throw new BexError("NOT_ALLOWED", "Target.createTarget only accepts url/background in hidden runs.");
      }
      const r = (await orig(method, { url: params.url, hidden: true, background: true })) as { targetId?: string };
      if (r?.targetId) st.owned.add(r.targetId);
      return r;
    }
    if (method === "Target.attachToTarget" || method === "Target.closeTarget") {
      const tid = params.targetId as string | undefined;
      if (!tid || !st.owned.has(tid)) {
        throw new BexError(
          "FOREIGN_TARGET",
          `Refusing ${method} on a target this run did not create.`,
          "bex only operates targets it created. Pass --tab <url> to work on a page; human tabs are never attachable from a run.",
        );
      }
      const r = await orig(method, params);
      if (method === "Target.closeTarget") st.owned.delete(tid);
      return r;
    }
    if (method.startsWith("Target.") && !["Target.getTargets", "Target.getTargetInfo"].includes(method)) {
      return deny("NOT_ALLOWED", method);
    }
    if (method.startsWith("Browser.") && method !== "Browser.getVersion") {
      return deny("NOT_ALLOWED", method);
    }
    if (method.startsWith("Storage.")) {
      return deny("NOT_ALLOWED", `Storage.${method.slice(8)}`, "The Storage domain touches the shared account context (cookies, origin data) and is denied.");
    }
    if (method === "Runtime.evaluate" && !st.bootstrap) {
      if (!st.pinnedUniqueId) throw new BexError("CONTEXT_NOT_READY", "No verified main-frame execution context is pinned.");
      params = { ...params, uniqueContextId: st.pinnedUniqueId };
    }
    return orig(method, params);
  };
  session.onEvent((method, params) => {
    if (method === "Runtime.executionContextCreated") {
      const ctx = (params as { context?: { auxData?: { isDefault?: boolean; frameId?: string }; uniqueId?: string } }).context;
      if (ctx?.auxData?.isDefault && ctx.uniqueId && ctx.auxData.frameId) st.candidates.unshift({ id: ctx.uniqueId, frameId: ctx.auxData.frameId });
      if (st.candidates.length > 16) st.candidates.length = 16;
    } else if (method === "Target.targetCrashed" && st.owned.has((params as { targetId?: string }).targetId ?? "")) {
      st.crashed = true;
    }
  });
  // 片段可调用的钉扎重置：刻意导航后重新验证候选并重新锚定
  (session as unknown as Record<string, unknown>).resetContextPin = async (): Promise<string | null> =>
    awaitPin(orig, st);
}

// 导航会产生多个 default 候选；先按当前主帧 frameId 过滤，再验证 context 活性。
// 不把晚到的子帧或已销毁的主帧误认为当前文档。
export async function pinByValidation(orig: (m: string, p?: unknown) => Promise<unknown>, st: PolicyState): Promise<string | null> {
  const { frameTree } = (await orig("Page.getFrameTree", {})) as { frameTree: { frame: { id: string } } };
  const main = frameTree.frame.id;
  for (const candidate of st.candidates.filter((c) => c.frameId === main)) {
    try {
      await orig("Runtime.evaluate", { expression: "1", uniqueContextId: candidate.id });
      st.pinnedUniqueId = candidate.id;
      return candidate.id;
    } catch {
      // 候选已随导航/帧销毁失效，试下一个
    }
  }
  return null;
}

export async function awaitPin(orig: (m: string, p?: unknown) => Promise<unknown>, st: PolicyState): Promise<string> {
  st.pinnedUniqueId = undefined;
  const deadline = Date.now() + 5_000;
  while (Date.now() < deadline) {
    try {
      const pin = await pinByValidation(orig, st);
      if (pin) return pin;
    } catch { /* navigation may still be replacing the frame tree */ }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new BexError("CONTEXT_NOT_READY", "No live main-frame context appeared within five seconds.");
}

// ---------- `run` worker: vm execution + screenshot interception + policy ----------

type RunData = { wsUrl: string; targetId?: string; tabUrl?: string; code: string; dir: string };

export function makeConsole(logs: LogEntry[]): Console {
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
  const st: PolicyState = { owned: new Set(), candidates: [], mutated: false, crashed: false, bootstrap: false };
  try {
    post({ type: "phase", phase: "connect" });
    const session = new Session();
    // 拦截截图写入运行时目录：片段收到 savedTo 而非 base64（onCallResult 先于
    // resolve 触发，修改 result 对象对片段可见）。
    session.onCallResult((method, _params, result) => {
      const r = result as { data?: string } | null;
      if (method === "Page.captureScreenshot" && r && typeof r.data === "string") {
        const path = `${data.dir}/${shotName("shot")}`;
        const buf = Buffer.from(r.data, "base64");
        writeFileSync(path, buf, { mode: 0o600 });
        screenshots.push({ path, bytes: buf.length });
        delete r.data;
        (r as { savedTo?: string }).savedTo = path;
      }
    });
    await session.connect({ wsUrl: data.wsUrl, timeoutMs: CONNECT_TIMEOUT_MS });

    let attachedTo: string | undefined;
    if (!process.env.BEX_UNRESTRICTED) installPolicy(session, st);

    if (data.tabUrl) {
      post({ type: "phase", phase: "attach" });
      const { targetId } = (await session.Target.createTarget({ url: "about:blank" })) as { targetId: string };
      await session.use(targetId);
      st.bootstrap = true;
      await session.Runtime.enable({}).catch(() => undefined);
      if (data.tabUrl === "about:blank") await session.Page.navigate({ url: "data:text/html," });
      await session.Page.navigate({ url: data.tabUrl });
      await awaitPin(session._call.bind(session), st);
      st.bootstrap = false;
      attachedTo = targetId;
    } else if (data.targetId) {
      post({ type: "phase", phase: "attach" });
      await session.use(data.targetId);
      st.owned.add(data.targetId); // -t 仅在 BEX_UNRESTRICTED 人工模式下可达，策略未安装
      attachedTo = data.targetId;
    }
    post({ type: "phase", phase: "script" });

    // vm 隔离误用的全局 API，不是恶意 JS 的安全边界；只运行受信任片段。
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
        targetId: attachedTo ?? null,
        ...capped,
        ...cappedLogs,
        screenshots,
        elapsedMs: Date.now() - started,
      },
    });
  } catch (e) {
    const err = classifyError(e);
    // -32001 细分：会话丢失不等于页面消失，浏览器级复查后定性
    if (/Session with given id not found/i.test(err.message)) {
      try {
        const session2 = new Session();
        await session2.connect({ wsUrl: data.wsUrl, timeoutMs: 5_000 });
        const { targetInfos } = (await session2.Target.getTargets({})) as { targetInfos: Array<{ targetId: string }> };
        session2.close();
        const alive = data.targetId
          ? targetInfos.some((t) => t.targetId === data.targetId)
          : [...st.owned].some((t) => targetInfos.some((x) => x.targetId === t));
        err.code = alive ? "SESSION_LOST" : "TARGET_GONE";
        err.hint = alive
          ? "The tab lives but this CDP session was detached; re-attach with session.use(targetId) and retry."
          : "The tab is gone (closed or its run ended). Re-derive state; long-lived state belongs to the application, not the tab.";
      } catch {
        /* 复查失败保留原分类 */
      }
    }
    if (err.code === "SCRIPT_ERROR" && st.crashed) {
      err.code = "TARGET_CRASHED";
      err.hint = "The page renderer crashed mid-run. Retry with a fresh --tab; tab-local state is lost.";
    }
    post({
      type: "done",
      envelope: {
        ok: false,
        targetId: data.targetId ?? null,
        error: err,
        logs: truncateLogs(logs).logs,
        screenshots,
        elapsedMs: Date.now() - started,
      },
    });
  }
}

function cmdRun(args: string[]): void {
  let targetId: string | undefined;
  let tabUrl: string | undefined;
  let timeoutMs = DEFAULT_TIMEOUT_MS;
  let file: string | undefined;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "-t" || a === "--target") targetId = args[++i];
    else if (a === "--tab") tabUrl = args[++i];
    else if (a === "--timeout") {
      timeoutMs = Number(args[++i]);
      if (!Number.isFinite(timeoutMs)) usage();
    } else if (!file && !a.startsWith("-")) file = a;
    else usage();
  }
  if (!file) usage();
  if (targetId && tabUrl) usage();
  if (targetId && !process.env.BEX_UNRESTRICTED) {
    printEnvelope({
      ok: false,
      error: {
        code: "RESTRICTED",
        message: "`run -t <targetId>` attaches a target the run did not create.",
        hint: "Agents: use `run --tab <url>` (hidden throwaway tab). Humans: prefix BEX_UNRESTRICTED=1 for direct manual access.",
      },
    });
    process.exit(2);
  }
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
      workerData: { wsUrl, targetId, tabUrl, code, dir: shotDir() } satisfies RunData,
    });
    let phase = "connect";
    let printed = false;
    let mutated = false;
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
          outcomeUnknown: mutated || undefined,
          error: {
            code: "TIMEOUT",
            phase,
            message: `run exceeded ${timeoutMs}ms and was force-terminated during phase "${phase}".`,
            hint: mutated
              ? "A page command was dispatched before the kill: its effect may be unknown. Do NOT blindly replay side effects — inspect state first."
              : "Raise --timeout (max 600000) or shorten the script; long waits belong inside one run.",
          },
        },
        3,
      );
    }, timeoutMs);
    worker.on("message", (m: { type: string; phase?: string; envelope?: Record<string, unknown> }) => {
      if (m.type === "phase" && m.phase) phase = m.phase;
      if (m.type === "mutated") mutated = true;
      if (m.type === "done" && m.envelope) {
        clearTimeout(timer);
        finish(m.envelope, m.envelope.ok ? 0 : 1);
      }
    });
    worker.on("error", (e) => {
      clearTimeout(timer);
      finish({ ok: false, outcomeUnknown: mutated || undefined, error: { code: "WORKER_CRASH", message: String(e) } }, 1);
    });
    worker.on("exit", (code) => {
      clearTimeout(timer);
      finish({ ok: false, outcomeUnknown: mutated || undefined, error: { code: "WORKER_CRASH", message: `worker exited unexpectedly (code ${code})` } }, 1);
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
  if (!process.env.BEX_UNRESTRICTED) {
    printEnvelope({
      ok: false,
      error: {
        code: "RESTRICTED",
        message: "`shot` captures a target the caller did not create (hidden tabs cannot be captured).",
        hint: "Humans: prefix BEX_UNRESTRICTED=1. Note: screenshots hang on hidden targets; capture real tabs only.",
      },
    });
    process.exit(2);
  }
  if (!targetId) {
    printEnvelope({ ok: false, error: { code: "USAGE", message: "shot requires -t <targetId>", hint: "Run `bex targets` to list pages." } });
    process.exit(2);
  }
  const wsUrl = await resolveWsUrl();
  const session = new Session();
  await session.connect({ wsUrl, timeoutMs: CONNECT_TIMEOUT_MS });
  let done = false;
  // 隐形 target 上 captureScreenshot 会无限挂起，必须有时限兜底
  const timer = setTimeout(() => {
    if (done) return;
    done = true;
    session.close();
    printEnvelope({ ok: false, error: { code: "SHOT_TIMEOUT", message: "captureScreenshot did not return within 20s (hidden targets never paint)." } });
    process.exit(3);
  }, 20_000);
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
    const path = out ?? `${shotDir()}/${shotName("shot")}`;
    writeFileSync(path, buf, { mode: 0o600 });
    done = true;
    clearTimeout(timer);
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
    if (!done) {
      done = true;
      clearTimeout(timer);
    }
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
  if (cmd === "__job-owner") return void jobOwner(rest);
  if (cmd === "job") return void cmdJob(rest);
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
  if (workerData?.kind === "handoff") void handoffWorker(workerData);
  else if (workerData?.kind === "job") void jobWorker(workerData);
  else void workerRun(workerData as RunData);
}
