# Frozen visual helper backend checkpoint

2026-10-23. Independent review requested; this is an implementation/test report, not completed review or live acceptance.

- Own base: `c20e1eb3287397caa15205e0c036afbc6e21deb7`.
- Frozen source: `1c2d8ef2ce5d6207fd74f126845ebab48024537c`.
- Branch: `feature/visual-host-adapter-2026-10-23`.
- Focused draft PR: https://github.com/KanujVerma/relay/pull/78 against frozen `build/visual-host-foundation-2026-10-23` at the exact own base; one commit/eight files. Created and attached after source freeze. Independent review remains pending.
- Checkout: `<workspace>/work/relay-build-visual`.
- Incremental diff: 8 files, 1019 insertions, 26 deletions.
- SHA-256 of `git diff --binary <base> <head>`: `b3b057b24e42706db495d2f097aea0e6f595240b801210ffe779c1b86f85a36b`.
- Base contains accepted answers b33292f, composition 86d69e and reviewed visual primitive/handoff. Root owns later native fixes and assembly. PR74/frozen primitive base are unchanged.

## Result

Actual helper stdio now handles the approved four-key explicit visual request/eight-key status response. One separately tracked idle probe task is cancellable without blocking the reader; all terminals emit after actual task quiescence. Exact replay caches latest output without IO; changed payload under reused UUID rejects/revokes; ledger is bounded512. Actual configured bound OAuth stream is required before any credential access. Status itself never reads credentials/network.

Public ScreenImageAssembler performs bounded local staging against matching staged OCR identity. Two read-only source accessors expose/check the original issued observation, and claim.owner is that actual object. Selected AX text has no image. Incomplete/unknown images use one ordinary text request; image failure makes no second POST. Pre-EOU retirement clears staged text/image even without active request; late old retirement preserves newer staging.

The actual current request/token/permission base callback avoids recursive permit validation. Same configured OAuth transport, request budget and one-active/newest-pending answer worker are reused. Actual bearer revalidation precedes helper publication. Host-built imageDigest appears only for actual used-image permits and is the original native canonical-pixels digest, separately from encoded-PNG SHA256. Lost proof cannot downgrade an image answer to text-only metadata. Raw PNG storage clears while original publication ownership remains. Disable cancels image-dependent work while preserving unrelated reference/personal answers.

Tiny requested fixture-only correction: case-study demos now return users/workflow/problem/success-measure points without code and with an explicit synthetic assumption. Production request/answer policy files are untouched.

## Fresh observed verification

- Existing `/private/tmp/relay-answers-venv/bin/python`, HTTPX0.28.1; no install.
- Full `python -m unittest discover -s tests`: **554 tests, 21 optional converter skips**, zero failures.
- Focused `python -m unittest tests.test_visual_host_backend`: **30 passed**, including **six actual helper subprocess tests**.
- Existing fake localhost HTTPX socket tests are included in the full suite; sandbox-free execution was explicitly limited to offline synthetic tests.
- EVALS validate: **26 synthetic questions**.
- Documentation verifier: **20 required files/local Markdown links**.
- `git diff --check`: passed.
- Existing HTTPError/SQLite ResourceWarnings and expected negative CLI output remain. New helper subprocess cases exited with empty stderr.

Red-to-green evidence includes original missing APIs, repeated completed transfer, early nonquiesced probe terminal, staged pre-EOU revocation, UUID payload mismatch, same-stream cleanup race, fixture transport credential read, completed image permit loss, publication token/config/consent changes and the case fixture mismatch. Tests use synthetic PNGs, fake bearer strings and HTTPX MockTransport.

No actual OAuth/account probe, credential read, external model call, capture, AX access, permission prompt, private user file, model download or image persistence was performed. No Swift, CI, global HANDOFF/ADR or root-owned contract source was edited in the own delta.

## Remaining gates

Root independent exact-head review, native control/producer/complete-offer/pixel-gate integration on the separate Swift branch, joined verification and hosted CI remain separate. Actual account acceptance, visual quality/latency, source/window/permission lifecycle and image-only capture remain unverified; current capture requires a valid OCR observation.

Implementation/API details: `docs/VISUAL_BACKEND.md`; continuation: `docs/lanes/VISUAL_HOST.md` in the frozen source.
