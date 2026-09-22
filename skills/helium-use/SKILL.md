---
name: helium-use
description: >
  Drive, inspect, and screenshot the user's daily Helium browser via the bex CLI
  over CDP. Reactive: when the user asks to 打开网页 / 截图 / 页面提取 / 浏览器操作 /
  drive ChatGPT-like UIs / check a page in a real browser. Proactive: when a task
  needs a real logged-in browser instead of plain HTTP fetch. Contract: scripts
  are async function bodies run by `bex run` with a pre-connected CDP session;
  CDP calls are session.Domain.method(params); no session.send, no emit. Read
  this skill before writing any browser code.
allowed-tools:
  - Read
  - Write
  - Bash(bex:*)
---

# helium-use

The user's daily browser (Helium) exposes a CDP debug endpoint. `bex` is the only
sanctioned way to reach it: a CDP-generic CLI with no browser-specific logic.
Everything browser-specific (endpoint, auto-launch policy) is pinned by the NixOS
wrapper environment.

## Preconditions

- `bex` reads `BU_CDP_URL` (auto-resolved http→ws) and auto-launches `BU_CDP_LAUNCH` when the endpoint is down. Both are pinned by the system wrapper.
- The default endpoint is the ONLY authorized browser. Never launch, download, or connect to any other browser (no nix shell chromium, no headless instances). On endpoint failure, report the error verbatim and stop.
- The browser holds the user's real logged-in sessions — every action is a real side effect.

## Execution Model

Read this once; it prevents every classic first-call error.

- The snippet file is an **async function body**, not an ES module: top-level `await` yes; `return <value>` is the output. No static `import`, no `require`, no fs/net/process — it runs in a vm sandbox. Reusable logic lives in real script files you keep, not in imports.
- In scope: `session`, `console`, `setTimeout`/`clearTimeout`.
- `session` arrives **pre-connected**. With `--tab <url>` bex creates a hidden
tab (about:blank → navigate), attaches, and pins the page's execution context:

  ```js
  const r = await session.Runtime.evaluate({ expression: `JSON.stringify({...})`, returnByValue: true });
  return JSON.parse(r.result.value);
  ```

- Page code (`document`, `window`) exists only inside `Runtime.evaluate` expression strings. The snippet itself runs in Node.
- The hidden tab lives exactly as long as the run — variables, attached-target
state, RemoteObject ids, and the tab itself all die at exit. State that must
outlive a run lives in the application (conversation URLs), not the tab; reopen
by URL in the next run.
- Unknown API surface? `bex api` lists domains; `bex api --domain Target` lists methods with params.
- Ephemeral snippets go to `$XDG_RUNTIME_DIR`/`/tmp`; deliberate reusable scripts go to the project's `.pi/browser/`.

## Commands

```bash
bex run --tab <url> [--timeout ms] file   # 事务：隐形一次性 tab，结束即焚
bex run [--timeout ms] file               # browser 级片段（getTargets 等）
bex targets                               # list pages (JSON: targetId/url/title)
bex api [--domain D] [--method M]         # CDP surface from the vendored protocol
```

`bex run -t <targetId>` and `bex shot` are human-only channels: they exit with
`RESTRICTED` unless the caller sets `BEX_UNRESTRICTED=1`, and unrestricted runs
have no policy installed. Agents never use them — page work goes through
`--tab`.

Success envelope:

```json
{"ok":true,"targetId":"…","value":…,"logs":[],"screenshots":[],"truncated":false,"elapsedMs":1234}
```

Error envelope: `{"ok":false,"error":{"code":"TIMEOUT|API_SHAPE|PAGE_CONTEXT|TARGET_GONE|SESSION_LOST|CONTEXT_DESTROYED|TARGET_CRASHED|FOREIGN_TARGET|NOT_ALLOWED|RESTRICTED|CONNECT|NOT_CONNECTED|NO_EMIT|…","phase":"connect|attach|script","message":…,"hint":…}}`.
Exit codes: 0 ok, 1 error, 2 usage, 3 timeout. `Page.captureScreenshot` inside a run is auto-saved to `$XDG_RUNTIME_DIR/bex/` and the snippet receives `{savedTo}` instead of base64 — but note hidden tabs never paint, so captures only work on unrestricted targets.

## Tool Policy (enforced, not etiquette)

- Only targets created by the current run can be attached or closed —
`session.use()` on anything else fails with `FOREIGN_TARGET`. Snippet-created
tabs via `session.Target.createTarget` are forced `hidden` and die with the run.
- `Storage.*`, `Browser.close`, window-bounds mutation, `Target.activateTarget`
and auto-attach are denied (`NOT_ALLOWED`) — they touch the shared account or
the human's screen surface.
- Evaluations are pinned to the attached document. After a deliberate
navigation call `await session.resetContextPin()` and re-derive state; a
stale pin surfaces as `CONTEXT_DESTROYED` instead of silently evaluating the
new document.
- A TIMEOUT (or worker crash) envelope may carry `outcomeUnknown: true` —
input/navigation was dispatched before the kill and the page may have acted on
it. Inspect state; never blindly replay side effects.

## Quick Start

```bash
# 1. write the snippet (see Execution Model), then:
bex run --tab https://example.com/ /tmp/probe.js   # hidden throwaway tab
```

## Task Patterns

| Task | Read |
| --- | --- |
| Driving ChatGPT-like chat UIs: compose, send, wait for Extra-High replies, extract | [references/llm-consultation.md](references/llm-consultation.md) |
| Extracting/verifying page data in one round-trip | [references/page-extraction.md](references/page-extraction.md) |
| Screenshot verification and vision workflows | [references/shot-verification.md](references/shot-verification.md) |

## Pitfalls

| Symptom | Cause | Fix |
| --- | --- | --- |
| `session.send is not a function` | bare-CDP prior; bex has no `send` | `session.Domain.method(params)`; `bex api` for the surface |
| `FOREIGN_TARGET` | tried to `use()` a tab this run didn't create | agents: `--tab <url>`; never operate the human's tabs |
| `CONTEXT_DESTROYED` | the attached document navigated/replaced under you | after deliberate navigation: `await session.resetContextPin()`, re-derive; otherwise treat as drift and stop |
| `SESSION_LOST` | CDP session detached but the tab lives | re-`use(targetId)` and retry |
| `TARGET_GONE` | the tab closed / its run ended | reopen by URL in a fresh `--tab` run; long-lived state belongs to the app |
| `RESTRICTED` | used `-t`/`shot` without `BEX_UNRESTRICTED` | agents: don't; humans: prefix the env |
| `outcomeUnknown: true` on TIMEOUT | side effects were dispatched before the kill | inspect page state first; do not replay blindly |
| `window/document is not defined` | page code at snippet top level | move it into `session.Runtime.evaluate({expression})` |
| Reply "done" but text truncated/growing | mid-generation thinking pause (false completion) | require length threshold + no activity indicator + repeated stability; see llm-consultation.md |
| Envelope `truncated:true` | value exceeded 20 KB | slice DOM text (`innerText.slice(0,N)`) and cap arrays in the snippet |

## Contract

1. Return compact values: slice DOM text, cap arrays; the envelope truncates at 20 KB but you should not rely on it.
2. Verify after acting: after click/send/insert, re-evaluate state before claiming success.
3. Long waits happen inside ONE run (`--timeout` up to 600000), never as many small calls.
4. Screenshots only when vision is required; prefer DOM extraction for facts.
5. One authorized browser: never launch or connect to another endpoint; report endpoint errors verbatim.
6. Report `elapsedMs`/latency facts as measured, never invented.

## Notes

- `--timeout` default 60000, max 600000 ms; hard-killed (envelope `code:"TIMEOUT"`, `phase` tells where).
- Value cap 20 KB, logs cap 8 KB / 200 entries.
- Snippets have no fs access; to persist artifacts return data and write it yourself (human shot channel: `BEX_UNRESTRICTED=1 bex shot -o`).
