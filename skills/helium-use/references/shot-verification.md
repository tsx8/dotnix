# Screenshot verification & vision

Screenshots answer "what does it look like" — layout, canvas, states the DOM
cannot express. Facts (text, counts, attributes) are cheaper and exact via
DOM extraction; screenshot only when vision is required.

## Status

`bex shot` is a human channel (`BEX_UNRESTRICTED=1`; agents get `RESTRICTED`),
and hidden tabs never paint — `captureScreenshot` on them hangs (bex cuts it
off with `SHOT_TIMEOUT`). Visual verification of agent-driven hidden pages is
an open gap until a capture path for hidden targets exists; until then, agents
verify via DOM and report, and the human takes shots manually.
