# Driving ChatGPT-like chat UIs

Workflow proven end-to-end against chatgpt.com (GPT-5.6 Sol, Extra High). Every
step below encodes a failure that actually happened; do not skip the checks.

## 1. Locate or open the conversation

```js
// bex targets first; open a fresh chat if needed:
const { targetId } = await session.Target.createTarget({ url: "https://chatgpt.com/" });
await session.use(targetId);
await new Promise((r) => setTimeout(r, 4000));   // wait for app shell
return { targetId };
```

Persist `targetId` in your notes; reuse it across runs while the tab lives.

## 2. Model / reasoning selection

- Find the picker by innerText (`"Extra High"`, etc.); `aria-label`s are unreliable.
- Synthetic `element.click()` is often intercepted — use real mouse events at the
  button's coordinates:

```js
const pos = await session.Runtime.evaluate({ expression: `(function(){
  const b = [...document.querySelectorAll('button')].find(x => (x.innerText||'').trim()==='Extra High');
  if (!b) return JSON.stringify(null);
  const r = b.getBoundingClientRect();
  return JSON.stringify({ x: Math.round(r.x+r.width/2), y: Math.round(r.y+r.height/2) });
})()`, returnByValue: true });
const p = JSON.parse(pos.result.value);
await session.Input.dispatchMouseEvent({ type: "mouseMoved", x: p.x, y: p.y });
await session.Input.dispatchMouseEvent({ type: "mousePressed", x: p.x, y: p.y, button: "left", clickCount: 1 });
await session.Input.dispatchMouseEvent({ type: "mouseReleased", x: p.x, y: p.y, button: "left", clickCount: 1 });
// then read [role="menu"] items and click the one matching the model name
```

## 3. Insert long text (never per-key)

```js
await session.Runtime.evaluate({ expression: `(function(){
  (document.querySelector('#prompt-textarea') || document.querySelector('div[contenteditable="true"]')).focus();
  return 'focused';
})()`, returnByValue: true });
await session.Input.insertText({ text: PROMPT });
// verify: query the composer's textContent length and the send button's disabled state
```

## 4. Send and confirm streaming started

Click `button[data-testid="send-button"]`; within seconds a Stop button must
appear — that is your confirmation the message went out.

## 5. Completion detection — beware false completion

High reasoning effort streams in segments with long silent pauses (thinking,
web search). Observed: reply stable at 1688 chars for minutes, finally 17047.
"Stop button gone + text stable once" is NOT completion. Require all of:

- assistant message exists and `length` above a sane threshold (not 0/short),
- no streaming indicator (Stop button, thinking animation),
- length identical across two checks several seconds apart,
- no `thinking`/activity element present.

```js
for (let i = 0; i < 44; i++) {
  await new Promise((r) => setTimeout(r, 12000));
  const st = await session.Runtime.evaluate({ expression: `(function(){
    const a = document.querySelectorAll('[data-message-author-role="assistant"]');
    const stop = document.querySelector('button[aria-label="Stop streaming"], button[aria-label*="Stop"]');
    const anim = document.querySelector('[class*="animate-pulse"], [class*="animate-bounce"]');
    return JSON.stringify({ n: a.length, len: a.length ? a[a.length-1].innerText.length : 0,
      streaming: !!stop, anim: !!anim });
  })()`, returnByValue: true });
  const s = JSON.parse(st.result.value);
  if (s.n > 0 && s.len > 500 && !s.streaming && !s.anim) {
    await new Promise((r) => setTimeout(r, 8000));   // second stability check
    // …re-read len; return done only if unchanged…
  }
}
return { done: false, msg: "timeout, still generating" };
```

Run with `--timeout 580000` or similar.

## 6. Extract the reply

`innerText` of the last assistant message; long replies: slice into parts and
return each part as its own run. Strip citation chips (standalone lines like
`+1`, `GitHub`, `npm`) with a line filter. Keep your return compact.

## 7. Interrupt recovery

If a run died mid-way (e.g. `NOT_CONNECTED`), the browser state is untouched:
reconnect is automatic on the next `bex run`; re-`use(targetId)` and continue —
the conversation, the streaming reply, everything survives in the tab.
