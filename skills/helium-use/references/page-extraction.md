# Page data extraction & verification

One round-trip per fact: build the whole extraction as a single
`Runtime.evaluate` returning one JSON string, parse it in Node, return it.

## Canonical pattern

```js
const r = await session.Runtime.evaluate({ expression: `(function(){
  return JSON.stringify({
    title: document.title,
    state: document.querySelector('[title="Status"]')?.title || null,
    labels: [...document.querySelectorAll('.IssueLabel')].map(e => e.textContent.trim()).slice(0, 10),
    bodySnippet: (document.querySelector('.comment-body')?.innerText || '').slice(0, 600),
    lastComments: [...document.querySelectorAll('.timeline-comment')].slice(-3)
      .map(c => (c.innerText || '').slice(0, 400)),
  });
})()`, returnByValue: true });
return JSON.parse(r.result.value);
```

Rules that keep the envelope small and the facts exact:

- Slice long text where you collect it (`innerText.slice(0, N)`), cap arrays.
- Prefer absence-tolerant selectors (`?.`) and report `null`, not a throw.
- Discover selectors first with a tiny probe run (count matches for each
  candidate), then extract with the winners — don't guess twice in one script.

## Navigation

New tab: `Target.createTarget({url})` → `use(targetId)` → sleep 3–5 s for JS-heavy
apps (or poll for a marker selector). Same tab: `Page.navigate` via
`await session.Page.navigate({url})` then wait for load the same way.

## Stale targets

`TARGET_GONE` / `No target with given id` means the tab closed or was replaced —
`bex targets`, re-resolve, re-`use`. A targetId is valid only while that tab
lives.

## Verification discipline

After asserting a fact about page state (a value was saved, a message sent),
re-evaluate the DOM for evidence in the same run — don't infer from the absence
of errors. For claims about what a page *looks* like, see
[shot-verification.md](shot-verification.md).
