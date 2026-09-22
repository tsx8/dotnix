# Driving ChatGPT-like chat UIs

Workflow proven end-to-end against chatgpt.com (GPT-5.6 Sol, Extra High) in
hidden throwaway tabs. Every step below encodes a failure that actually
happened; do not skip the checks.

## 0. Transaction shape

One consultation = one `bex run --tab` transaction when it fits the timeout
(observed full cycle: ~5–8 min; `--timeout` max 600000). The tab dies with the
run; the conversation lives server-side. Follow-ups reopen the SAME
conversation by URL in a fresh `--tab` run — that is the only state that
outlives a run.

```bash
bex run --tab https://chatgpt.com/c/<conversation-id> --timeout 580000 consult.js
```

## 1. Find or resume the conversation

- Fresh chat: `--tab https://chatgpt.com/`.
- Resume: you need the conversation URL. Sidebar history links do NOT render
  in hidden tabs — read the account's local cache instead (proven):

  ```js
  // inside a --tab https://chatgpt.com/ run, after the shell is up:
  const r = await session.Runtime.evaluate({ expression: `(function(){
    const k = Object.keys(localStorage).find(k => /conversation-history$/.test(k));
    const items = k ? JSON.parse(localStorage.getItem(k)).value.pages[0].items : [];
    return JSON.stringify(items.slice(0, 10).map(i => ({ id: i.id, title: i.title })));
  })()`, returnByValue: true });
  return JSON.parse(r.result.value);
  ```

Persist conversation ids in your notes. Conversations keep their model and
effort settings; a fresh tab inherits the account defaults.

## 2. Wait for the shell (hydration is slow and variable)

Poll instead of sleeping once — 6s is sometimes not enough:

```js
const ev = async (e) => { const r = await session.Runtime.evaluate({ expression: e, returnByValue: true });
  return JSON.parse(r.result.value); };
let pre;
for (let i = 0; i < 8; i++) {
  pre = await ev(`(function(){
    const c = document.querySelector('#prompt-textarea') || document.querySelector('div[contenteditable="true"]');
    return JSON.stringify({ composer: !!c, users: document.querySelectorAll('[data-message-author-role="user"]').length,
      assistants: document.querySelectorAll('[data-message-author-role="assistant"]').length });
  })()`);
  if (pre.composer) break;
  await new Promise((r) => setTimeout(r, 1500));
}
```

## 3. Compose and send (the proven recipe)

ChatGPT auto-restores composer drafts across tabs; typing on top of a restored
draft makes button clicks AND Enter silently do nothing. Clear, type, submit
the form directly:

```js
// 3.1 clear any auto-restored draft
await ev(`(function(){
  const c = document.querySelector('#prompt-textarea') || document.querySelector('div[contenteditable="true"]');
  c.focus(); document.execCommand('selectAll', false, null); document.execCommand('delete', false, null);
  return true;
})()`);
// 3.2 inject (never per-key)
await session.Input.insertText({ text: PROMPT });
// 3.3 submit the form — coordinate clicks and Enter events are unreliable here
await ev(`(function(){
  const c = document.querySelector('#prompt-textarea') || document.querySelector('div[contenteditable="true"]');
  c.closest('form').requestSubmit(); return true;
})()`);
```

Confirm the send: user-message count increments, or a Stop button appears.
If neither, inspect state before retrying — a half-dispatched send with
`outcomeUnknown` must not be blindly replayed.

## 4. Completion detection — beware false completion

High reasoning effort streams in segments with long silent pauses. Observed:
reply stable at 1688 chars for minutes, finally 17047. Also observed: a
transient placeholder of ~100 chars captured as the "final" length — the final
snapshot must be re-derived, not trusted. Require all of:

- a NEW assistant message beyond the pre-send count, `length > 500`,
- no streaming indicator (Stop button), no thinking animation,
- length identical across two checks ~8s apart.

```js
let stableLen = -1, stableAt = 0, final = null;
for (let i = 0; i < 44; i++) {
  const s = await ev(`(function(){
    const a = document.querySelectorAll('[data-message-author-role="assistant"]');
    const stop = [...document.querySelectorAll('button')].some(b => /stop|停止/i.test(b.getAttribute('aria-label')||''));
    const anim = document.querySelector('[class*="animate-pulse"], [class*="animate-bounce"]');
    return JSON.stringify({ n: a.length, len: a.length ? a[a.length-1].innerText.length : 0, stop, anim: !!anim });
  })()`);
  final = s;
  if (s.n > priorAssistants && s.len > 500 && !s.stop && !s.anim) {
    if (stableLen === s.len && Date.now() - stableAt >= 8000) break;
    if (stableLen !== s.len) { stableLen = s.len; stableAt = Date.now(); }
  } else { stableLen = -1; }
  await new Promise((r) => setTimeout(r, 12000));
}
```

## 5. Extract

`innerText` of the last assistant message; strip citation chips. The envelope
caps at 20 KB — slice ~1900 chars per part and return one part per run,
reopening the conversation by URL each time. If the extracted length looks like
a placeholder (~100 chars), re-open and re-extract before believing it.

## 6. Failure recovery

- Run died mid-generation: the conversation and any in-flight reply survive
  server-side. Reopen by URL; if generation finished while you were away, the
  full text is there.
- `CONTEXT_DESTROYED`: the tab was navigated (by the app, not you) — stop and
  re-derive; do not continue a flow whose page identity you cannot confirm.
- Draft residue after a killed run: the draft store may re-inject your text
  into the next tab's composer — step 3.1 exists for this; also clear
  `localStorage['oai/apps/conversationDrafts']` if it holds an orphan.
