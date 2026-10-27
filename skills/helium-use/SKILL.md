---
name: helium-use
description: >
  Drive, inspect, and screenshot the user's daily Helium browser through the
  mcp-bex MCP tools over CDP; the bex CLI is the human and fallback path. Use
  for browser automation, page extraction, ChatGPT-like UIs, or any task that
  needs a real logged-in browser. Snippets are async function bodies with a
  pre-connected CDP session; use a job only for page state that must persist.
  Read this skill before writing browser code.
allowed-tools:
  - Read
  - Write
  - Bash(bex:*)
  - mcp__mcp_bex__*
---

# helium-use

The user's daily Helium browser exposes a CDP endpoint. `bex` is the only
sanctioned way to reach it. The NixOS wrapper pins the endpoint and launch
command. On Pi, call the `mcp__mcp_bex__*` tools; the CLI remains for humans
and harnesses without MCP.

## Preconditions

- The default endpoint is the only authorized browser. Never launch, download, or connect to another browser, including headless instances. On endpoint failure, report the error verbatim and stop.
- The browser holds real login state; every action is a real side effect.

## Execution Model

- The snippet is an **async function body**, not an ES module. Top-level `await` works; `return` is the output. The VM is not a security sandbox; never run page-supplied code.
- In scope: `session`, `console`, `setTimeout`/`clearTimeout`. `session` is pre-connected. CDP calls are `session.Domain.method(params)`.
- Page code exists only inside `Runtime.evaluate` expression strings:

  ```js
  const r = await session.Runtime.evaluate({ expression: `JSON.stringify({...})`, returnByValue: true });
  return JSON.parse(r.result.value);
  ```

- A hidden tab lives exactly as long as the run. Variables, attached targets, and RemoteObject ids die with it. Use a job only when page-local state must survive multiple calls; state that must survive the browser belongs to the application URL.
- Unknown CDP method? Run `bex api` or `bex api --domain Target` from the CLI.
- `Page.captureScreenshot` inside a run is saved to `$XDG_RUNTIME_DIR/bex/` and the snippet receives `{savedTo}`. Hidden tabs never paint, so screenshots need a visible target.

## Interfaces

The MCP tools are the parameter contract. `run` and `job_run` take the snippet as `code`. `job_start` owns a hidden page or a parked handoff window. `job_status` and `job_stop` apply to both surfaces. `job_action`, `job_handoff`, and `job_release` operate only on handoff-surface jobs.

The result is the bex envelope as text and, in scripts, as structured content. It carries the value, logs, screenshots, `value.savedTo`, and error `code`/`hint`/`phase`. The value caps at 20 KB; logs cap at 8 KB and 200 entries. `outcomeUnknown` means a page command may have run before a kill; inspect state before retrying.

CLI fallback: run `bex --help` for `run`, `job`, `targets`, `shot`, and `api`; the hidden-tab and job rules are the same. `bex run -t` and `bex shot` are human-only; they need `BEX_UNRESTRICTED=1`, and agents never use them.

## Tool Policy

- Only targets created by the current run can be attached or closed. Snippet-created tabs are hidden and die with the run; window and focus parameters are rejected.
- `Storage.*`, `Browser.close`, window-bounds mutation, `Target.activateTarget`, and auto-attach are denied. They touch the shared account or the human's screen.
- Evaluations are pinned to the verified main-frame document. After deliberate navigation call `await session.resetContextPin()` and re-derive state. A stale pin is `CONTEXT_DESTROYED`; an unavailable pin is `CONTEXT_NOT_READY`.
- A TIMEOUT or worker crash may carry `outcomeUnknown`. Inspect state; never blindly replay side effects.
- A job id is its only control locator. Commands queue at the owner; a timed-out command ends the job and its page. A dead socket means page-local state is gone; `status` may return `live:false`, which is not recovery. Stop jobs you no longer need.
- Hidden jobs never operate human tabs. Use a handoff surface for login, OAuth, 2FA, CAPTCHA, or payment. `job_handoff` returns `WAIT_HUMAN` immediately; poll `job_status`; do not block.
- The MCP surface has no `-t`, no `shot`, and strips `BEX_UNRESTRICTED`.

## Quick Start

On Pi, call `run` with the snippet as `code` and a `tab_url`. On the CLI:

```bash
bex run --tab https://example.com/ /tmp/probe.js
```

## Task Patterns

| Task | Read |
| --- | --- |
| Driving ChatGPT-like chat UIs: compose, send, wait for Extra-High replies, extract | [references/llm-consultation.md](references/llm-consultation.md) |
| Flows that need the human's hands: login, OAuth, 2FA, CAPTCHA, payment | [references/hitl-handoff.md](references/hitl-handoff.md) |
| Extracting and verifying page data in one round-trip | [references/page-extraction.md](references/page-extraction.md) |
| Screenshot verification and vision workflows | [references/shot-verification.md](references/shot-verification.md) |

## Pitfalls

| Symptom | Cause | Fix |
| --- | --- | --- |
| `session.send is not a function` | bare-CDP prior; bex has no `send` | `session.Domain.method(params)`; `bex api` for the surface |
| `FOREIGN_TARGET` | tried to `use()` a tab this run did not create | use `run` or `job_run`; never operate the human's tabs |
| `CONTEXT_DESTROYED` | the attached document navigated or was replaced | after deliberate navigation call `await session.resetContextPin()` and re-derive; otherwise stop |
| `SESSION_LOST` | CDP session detached but the tab lives | re-`use(targetId)` and retry |
| `TARGET_GONE` | the tab closed or its run ended | reopen by URL in a fresh run; long-lived state belongs to the app |
| `JOB_ENDED` | the job owner is not running; the page is gone | inspect `job_status`; do not replay side effects |
| `RESTRICTED` | used `-t` or `shot` without `BEX_UNRESTRICTED` | agents do not use them; humans set the env |
| bex tools absent from the tool list | MCP tools are deferred | run `tool_search` for `bex browser` before calling them |
| `outcomeUnknown: true` on TIMEOUT | side effects were dispatched before the kill | inspect page state first; do not replay blindly |
| `window/document is not defined` | page code at snippet top level | move it into `session.Runtime.evaluate({expression})` |
| Envelope `truncated:true` | value exceeded 20 KB | slice DOM text and cap arrays; `value.savedTo` is the full JSON (0600) |

## Contract

1. Return compact values. The envelope caps at 20 KB; `value.savedTo` holds the full JSON (0600). Read that file instead of replaying side effects.
2. Verify after acting. After click, send, or insert, re-evaluate state before claiming success.
3. Use one run when the page can be reopened. Use a job only when page-local state must survive. Long waits use `timeout_ms` or `--timeout` up to 600000 ms.
4. Prefer DOM extraction. Screenshot only when vision is required.
5. Use the one authorized browser. Report endpoint errors verbatim and report measured latency, not invented numbers.
