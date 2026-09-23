# HITL handoff surfaces (bex job --handoff)

For flows that will need the human's hands — login, OAuth, 2FA, CAPTCHA, payment
confirmation — and for any flow where losing page-local state to an unexpected
human moment is expensive. Everything below was validated live on
Helium 0.17.2.1 + KWin 6.7.5 Wayland (park/wake under lock included); the
known limitations at the end are real observations, not speculation.

## Surface model

- One job = one dedicated browser window, created blank and **parked
  (minimized)** before the real page is navigated to. While parked the window
  still exists in the taskbar (see limitations).
- **No snippet ever runs on this surface.** `job run` is structurally
  unavailable; the only agent operations are declarative `job action`s issued
  by the trusted worker. This is the credential boundary: a snippet VM is not
  a security sandbox (host-object escape is proven), so it must never touch a
  page a human will type secrets into.
- While agent-owned, every owned window must stay minimized. A window restored
  without authorization flips the job to `EXTERNAL_TAKEOVER` within ~1s and
  revokes all writes. Do not fight the human for the window; stop the job.

## Lifecycle

```bash
bex job start --handoff https://issuer.example/login   # parked, AGENT_OWNED
bex job action <id> act.json                            # declarative prep
bex job handoff <id> "complete 2FA for issuer.example"  # WAIT_HUMAN
#   -> window is restored+activated; envelope carries expectedOrigin.
#   The human MUST verify the address bar matches expectedOrigin.
#   While WAIT_HUMAN: no action works; release/stop only.
bex job release <id> https://issuer.example https://issuer.example/done '[selector]'
#   -> verifies completion origin, requires popups closed, optional
#      postcondition selector, then replaces the document (secret-clear
#      barrier) and re-parks. New write epoch afterwards.
bex job stop <id>                                       # closes window + popups
```

Release rules: `<origin>` and `<clean-url>` must match the job's expected
origin; `clean-url` is the page the surface navigates to so the credential DOM
is fully replaced — pick a neutral same-origin URL. `selector` (optional) is a
boolean postcondition checked before the barrier; a failed selector keeps the
job in WAIT_HUMAN.

## Declarative actions (`job action <id> <json-file>`)

```json
{"type":"navigate","url":"https://issuer.example/step2"}   // same-origin only
{"type":"exists","selector":"#otp-input"}                  // boolean, no content returned
{"type":"click","selector":"#send"}
{"type":"fill","selector":"#name","text":"..."}            // credential-like fields are refused
```

`fill` rejects fields whose type/name/autocomplete/selector look like
password/OTP/token/secret/CVV/PIN. If the page needs a secret, that is exactly
the moment to `handoff`.

## Death and drift

- `TARGET_GONE`/`BROWSER_GONE`: page-local state is gone; the job ends. Start a
  new one — volatile persistence means no recovery promise.
- `EXTERNAL_TAKEOVER` in status: writes are revoked. Only `stop` (or the human
  closing the window) remains. Never auto-replay the last action.
- Any action envelope may carry `outcomeUnknown:true` only when a dispatch
  actually went out; validation refusals never do.

## Known limitations (accepted for v1)

1. **Creation flash**: the blank window briefly appears before parking (no
   content — the real URL loads only after park). Focus may be stolen for that
   moment.
2. **Taskbar entry while parked**: the minimized window is visible in the
   taskbar/pager. (This is also how a human performs an unauthorized restore —
   which the job detects and revokes writes for.)
3. Real OAuth popup chains and a secret-canary audit have NOT been
   end-to-end validated. Popup provenance (openerId adoption, POPUP_OPEN on
   release) is implemented and smoke-tested synthetically; run one real flow
   with a canary secret before relying on the credential claim.
