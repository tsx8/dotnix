// 上下文超过当前模型窗口的 1/e 时主动压缩（ChatGPT/Codex 的 auto_compact 语义）。
// ctx.compact 为 fire-and-forget，轮内超限由 pi 内置阈值压缩兜底。
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const COMPACT_RATIO = 1 / Math.E;

export default function (pi: ExtensionAPI) {
  let inFlight = false;

  pi.on("agent_settled", async (_event, ctx) => {
    if (inFlight) return;
    const contextWindow = ctx.model?.contextWindow;
    if (!contextWindow) return;
    const usage = ctx.getContextUsage();
    if (!usage || usage.tokens < Math.floor(contextWindow * COMPACT_RATIO)) return;

    inFlight = true;
    ctx.compact({
      onComplete: () => {
        inFlight = false;
      },
      onError: () => {
        inFlight = false;
      },
    });
  });
}
