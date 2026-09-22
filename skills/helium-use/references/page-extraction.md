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

New page: `bex run --tab <url> file.js` — the tab is hidden, owned by the run,
and dies with it; wait for JS-heavy apps by polling for a marker selector
(sleeps are unreliable). In-page navigation via `session.Page.navigate` is
allowed on your own tab; the context pin then fails fast with
`CONTEXT_DESTROYED` — call `await session.resetContextPin()` and re-derive
state before continuing. Attaching the human's tabs is refused (`FOREIGN_TARGET`);
extract by opening the URL in your own tab.

## Stale targets

`TARGET_GONE` means the tab is gone (closed or its run ended) — nothing to
re-resolve; reopen by URL in a fresh `--tab` run. `SESSION_LOST` means the
tab lives but the CDP session detached — re-`use(targetId)` and retry.

## Verification discipline

After asserting a fact about page state (a value was saved, a message sent),
re-evaluate the DOM for evidence in the same run — don't infer from the absence
of errors. For claims about what a page *looks* like, see
[shot-verification.md](shot-verification.md).
