# Screenshot verification & vision

Screenshots answer "what does it look like" — layout, canvas, states the DOM
cannot express. Facts (text, counts, attributes) are cheaper and exact via
DOM extraction; screenshot only when vision is required.

## Take a shot

```bash
bex shot -t <targetId> [-o /tmp/page.png]
# → {"ok":true,"path":"…","bytes":…,"viewport":{"width":1440,"height":900},
#    "pixels":{"width":2880,"height":1800},"devicePixelRatio":2}
```

- It is a **viewport** screenshot: content below the fold is not in it. "Element
  not visible in shot" ≠ "element absent" — verify in the DOM first.
- `devicePixelRatio` matters if you compute click coordinates from image pixels:
  CSS px = image px ÷ dpr. `Input.dispatchMouseEvent` takes CSS px.
- Default output goes to `$XDG_RUNTIME_DIR/bex/` (0700/0600, private). Use `-o`
  deliberately — a screenshot of the daily browser may contain private content;
  never write it into a repo working tree.

## Look at it

`bex shot` only produces the file. To see it, read the path with the `read`
tool (image-capable). Skip the read when the shot is only evidence for the user.

## In-run captures

`await session.Page.captureScreenshot({format:'png'})` inside a run is
auto-saved to `$XDG_RUNTIME_DIR/bex/` and returns `{savedTo}` — the snippet
never handles base64. Use it when the capture must be interleaved with actions;
use `bex shot` for standalone verification.
