// Gate C handoff surface: one dedicated browser window per job, parked
// (minimized) while agent-owned. No snippet VM ever touches this page — the
// only page operations are declarative CDP actions issued by this trusted
// worker, and during WAIT_HUMAN no content-bearing command is issued at all.
import { parentPort } from "node:worker_threads";
import { Session } from "./cdp/session.js";
import { BexError, classifyError } from "./bex.js";

export type HandoffData = { kind: "handoff"; wsUrl: string; url: string };
type Action =
  | { type: "navigate"; url: string }
  | { type: "exists"; selector: string }
  | { type: "click"; selector: string }
  | { type: "fill"; selector: string; text: string };
type Command = { type: string; seq: number; action?: Action; reason?: string; expectedOrigin?: string; cleanUrl?: string; selector?: string };
type TargetInfo = { targetId: string; openerId?: string; url: string; type: string };
type Phase = "STARTING" | "AGENT_OWNED" | "WAIT_HUMAN" | "VERIFY" | "EXTERNAL_TAKEOVER" | "STOPPING";
const origin = (url: string): string => { try { return new URL(url).origin; } catch { return "opaque"; } };
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function handoffWorker(data: HandoffData): Promise<void> {
  const session = new Session();
  const expected = origin(data.url);
  let root = "";
  let windowId: number | undefined;
  let phase: Phase = "STARTING";
  const owned = new Set<string>();            // root + popup targets (provenance graph)
  const windows = new Map<string, number>();  // targetId -> cdp windowId
  const popups = new Set<string>();
  const say = (m: unknown) => parentPort?.postMessage(m);
  const setPhase = (p: Phase, reason?: string) => { phase = p; say({ type: "phase", phase: p, reason }); };
  const result = (seq: number, value: Record<string, unknown>) => say({ type: "result", seq, result: value });

  const windowState = async (wid: number): Promise<string> => {
    const { bounds } = (await session.Browser.getWindowBounds({ windowId: wid })) as { bounds: { windowState?: string } };
    return bounds.windowState ?? "unknown";
  };
  const waitState = async (wid: number, state: string, ms = 4000): Promise<boolean> => {
    for (let i = 0; i < ms / 100; i++) {
      if ((await windowState(wid)) === state) return true;
      await sleep(100);
    }
    return false;
  };
  // Poll the target graph: root liveness, popup adoption via openerId, window ids.
  const refreshGraph = async (): Promise<"TARGET_GONE" | "NEW_POPUP" | null> => {
    const { targetInfos } = (await session.Target.getTargets({})) as { targetInfos: TargetInfo[] };
    if (phase !== "STOPPING" && !targetInfos.some((t) => t.targetId === root)) return "TARGET_GONE";
    let newPopup = false;
    for (const info of targetInfos) {
      if (info.openerId && owned.has(info.openerId) && !owned.has(info.targetId)) { owned.add(info.targetId); popups.add(info.targetId); newPopup = true; }
    }
    for (const id of owned) {
      if (!windows.has(id)) {
        try { const w = (await session.Browser.getWindowForTarget({ targetId: id })) as { windowId: number }; windows.set(id, w.windowId); } catch { /* closing */ }
      }
    }
    return newPopup ? "NEW_POPUP" : null;
  };
  const allParked = async (): Promise<boolean> => {
    for (const wid of windows.values()) if ((await windowState(wid)) !== "minimized") return false;
    return true;
  };
  const detach = async () => {
    const attached = session.getActiveSession();
    if (attached) await session.Target.detachFromTarget({ sessionId: attached }).catch(() => undefined);
    session.setActiveSession(undefined);
  };
  const node = async (selector: string): Promise<number> => {
    if (selector.length > 512) throw new BexError("USAGE", "Selector too long.");
    const { root: doc } = (await session.DOM.getDocument({ depth: 0 })) as { root: { nodeId: number } };
    const { nodeId } = (await session.DOM.querySelector({ nodeId: doc.nodeId, selector })) as { nodeId: number };
    return nodeId;
  };
  const preflight = async () => {
    if (phase === "WAIT_HUMAN") throw new BexError("WRITE_REVOKED", "The human owns this surface; only release or stop is available.");
    if (phase === "EXTERNAL_TAKEOVER") throw new BexError("WRITE_REVOKED", "An owned window was exposed without authorization; writes are revoked. Stop the job.");
    if (phase !== "AGENT_OWNED") throw new BexError("BAD_PHASE", `Job is ${phase}.`);
    if (!(await allParked())) {
      setPhase("EXTERNAL_TAKEOVER", "window_restored");
      throw new BexError("WRITE_REVOKED", "An owned window is not parked; write permission was revoked.");
    }
  };

  try {
    await session.connect({ wsUrl: data.wsUrl, timeoutMs: 15_000 });
    const created = (await session.Target.createTarget({ url: "about:blank", newWindow: true, windowState: "minimized", focus: false })) as { targetId: string };
    root = created.targetId;
    owned.add(root);
    const w = (await session.Browser.getWindowForTarget({ targetId: root })) as { windowId: number };
    windowId = w.windowId;
    windows.set(root, windowId);
    // KWin/Wayland: creation lands maximized and minimizing a maximized window
    // is not honored. Restore to normal first, then minimize — verify by readback.
    await session.Browser.setWindowBounds({ windowId, bounds: { windowState: "normal" } });
    if (!(await waitState(windowId, "normal"))) throw new BexError("PARK_FAILED", `Window never reached normal (state=${await windowState(windowId)}).`);
    await session.Browser.setWindowBounds({ windowId, bounds: { windowState: "normal", width: 769, height: 547 } });
    await sleep(200);
    await session.Browser.setWindowBounds({ windowId, bounds: { windowState: "minimized" } });
    if (!(await waitState(windowId, "minimized"))) throw new BexError("PARK_FAILED", `Window did not minimize (state=${await windowState(windowId)}).`);
    // Parked on a blank surface; only now navigate to the real workflow page.
    await session.use(root);
    await session.Page.navigate({ url: data.url });
    setPhase("AGENT_OWNED");
    say({ type: "ready", targetId: root, windowId, expectedOrigin: expected });

    const monitor = setInterval(async () => {
      if (phase === "STOPPING") return;
      if (!session.isConnected()) { say({ type: "terminal", error: "BROWSER_GONE" }); return; }
      try {
        const changed = await refreshGraph();
        if (changed === "TARGET_GONE") { say({ type: "terminal", error: "TARGET_GONE" }); return; }
        if (phase === "AGENT_OWNED") {
          if (changed === "NEW_POPUP") { setPhase("EXTERNAL_TAKEOVER", "surface_escape"); return; }
          if (!(await allParked())) { setPhase("EXTERNAL_TAKEOVER", "window_restored"); return; }
        }
      } catch { if (!session.isConnected()) say({ type: "terminal", error: "BROWSER_GONE" }); }
    }, 1000);
    monitor.unref();

    parentPort?.on("message", async (m: Command) => {
      let dispatched = false; // set immediately before any effectful CDP dispatch
      try {
        if (m.type === "action") {
          await preflight();
          const a = m.action!;
          if (a.type === "navigate") {
            if (origin(a.url) !== expected) throw new BexError("ORIGIN_MISMATCH", "Navigation must stay on the handoff surface's expected origin.");
            dispatched = true;
            await session.Page.navigate({ url: a.url });
          } else {
            if (!a.selector || !["exists", "click", "fill"].includes(a.type)) throw new BexError("USAGE", "Unknown declarative action.");
            const id = await node(a.selector);
            if (a.type === "exists") { result(m.seq, { ok: true, exists: id !== 0 }); return; }
            if (!id) throw new BexError("ELEMENT_MISSING", "Selector did not match.");
            if (a.type === "fill") {
              const { attributes } = (await session.DOM.getAttributes({ nodeId: id })) as { attributes: string[] };
              const attrs = Object.fromEntries(Array.from({ length: attributes.length / 2 }, (_, i) => [attributes[2 * i], attributes[2 * i + 1]]));
              if (typeof a.text !== "string" || a.text.length > 4096 || /password|otp|secret|token|code|cvv|pin/i.test(`${attrs.type ?? ""} ${attrs.name ?? ""} ${attrs.autocomplete ?? ""} ${a.selector}`)) {
                throw new BexError("CREDENTIAL_FIELD", "Cannot inject credential-like fields; the human enters them during handoff.");
              }
              await session.DOM.focus({ nodeId: id });
              dispatched = true;
              await session.Input.insertText({ text: a.text });
            } else {
              const { model } = (await session.DOM.getBoxModel({ nodeId: id })) as { model: { content: number[] } };
              const x = (model.content[0] + model.content[2] + model.content[4] + model.content[6]) / 4;
              const y = (model.content[1] + model.content[3] + model.content[5] + model.content[7]) / 4;
              dispatched = true;
              await session.Input.dispatchMouseEvent({ type: "mousePressed", button: "left", clickCount: 1, x, y });
              await session.Input.dispatchMouseEvent({ type: "mouseReleased", button: "left", clickCount: 1, x, y });
            }
          }
          // The parked window can be restored by the human at any instant; a
          // post-check catches exposure during the command, its outcome unknown.
          if (!(await allParked())) {
            setPhase("EXTERNAL_TAKEOVER", "window_restored");
            result(m.seq, { ok: false, outcomeUnknown: true, error: { code: "WRITE_REVOKED", message: "Window was exposed during the action; its effect may be unknown." } });
            return;
          }
          result(m.seq, { ok: true, dispatched: true });
        } else if (m.type === "handoff") {
          if (phase !== "AGENT_OWNED") throw new BexError("BAD_PHASE", `Handoff requires AGENT_OWNED; job is ${phase}.`);
          await preflight();
          setPhase("WAIT_HUMAN"); // writes revoked BEFORE the surface is shown
          await detach();
          await session.Browser.setWindowBounds({ windowId: windowId!, bounds: { windowState: "normal" } });
          await waitState(windowId!, "normal");
          await session.Target.activateTarget({ targetId: root });
          result(m.seq, { ok: true, state: "WAIT_HUMAN", reason: m.reason?.slice(0, 200), expectedOrigin: expected, checkAddressBar: true });
        } else if (m.type === "release") {
          if (phase !== "WAIT_HUMAN") throw new BexError("BAD_PHASE", `Release requires WAIT_HUMAN; job is ${phase}.`);
          if (origin(m.expectedOrigin ?? "") !== expected || origin(m.cleanUrl ?? "") !== expected) {
            throw new BexError("ORIGIN_MISMATCH", "Release origin and clean URL must match the job's expected origin.");
          }
          const info = (await session.Target.getTargetInfo({ targetId: root })) as { targetInfo: { url: string } };
          const actual = origin(info.targetInfo.url);
          if (actual !== expected) throw new BexError("ORIGIN_MISMATCH", "Completion origin does not match; verify the address bar before releasing.");
          if (popups.size) {
            const { targetInfos } = (await session.Target.getTargets({})) as { targetInfos: TargetInfo[] };
            const open = targetInfos.filter((t) => popups.has(t.targetId));
            if (open.length) throw new BexError("POPUP_OPEN", `${open.length} handoff popup(s) still open; complete and close them first.`);
          }
          setPhase("VERIFY");
          await session.use(root);
          if (m.selector && !(await node(m.selector))) { setPhase("WAIT_HUMAN"); throw new BexError("POSTCONDITION", "Completion selector not present."); }
          // secret-clear barrier: full document replacement on the same origin
          const nav = (await session.Page.navigate({ url: m.cleanUrl })) as { loaderId?: string };
          if (!nav.loaderId) { setPhase("WAIT_HUMAN"); throw new BexError("BARRIER_FAILED", "Clean navigation did not replace the document."); }
          let replaced = false;
          for (let i = 0; i < 50; i++) {
            const { frameTree } = (await session.Page.getFrameTree({})) as { frameTree: { frame: { loaderId?: string } } };
            if (frameTree.frame.loaderId === nav.loaderId) { replaced = true; break; }
            await sleep(100);
          }
          await detach();
          if (!replaced) { setPhase("WAIT_HUMAN"); throw new BexError("BARRIER_FAILED", "Document replacement not observed."); }
          if ((await windowState(windowId!)) !== "minimized") {
            await session.Browser.setWindowBounds({ windowId: windowId!, bounds: { windowState: "minimized" } });
          }
          if (!(await waitState(windowId!, "minimized", 3000))) { setPhase("WAIT_HUMAN"); throw new BexError("PARK_FAILED", "Could not re-park; the human still owns the surface."); }
          await session.use(root);
          setPhase("AGENT_OWNED");
          result(m.seq, { ok: true, state: "AGENT_OWNED", secretClearBarrier: "document_replaced", origin: actual });
        } else if (m.type === "stop") {
          setPhase("STOPPING");
          await detach();
          for (const id of [...owned].reverse()) {
            try { await session.Target.closeTarget({ targetId: id }); } catch { /* already closed */ }
          }
          session.close();
          result(m.seq, { ok: true });
        }
      } catch (e) {
        if (m.type === "release" && phase === "VERIFY") setPhase("WAIT_HUMAN");
        result(m.seq, { ok: false, error: classifyError(e), outcomeUnknown: (m.type === "action" && dispatched) || undefined });
      }
    });
  } catch (e) {
    if (root) { try { await session.Target.closeTarget({ targetId: root }); } catch { /* creation failed partway */ } }
    session.close();
    say({ type: "terminal", error: classifyError(e).code });
  }
}
