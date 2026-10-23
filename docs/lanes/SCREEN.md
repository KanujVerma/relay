# Screen context lane handoff

Issue: #64. Branch: `feature/screen-context-2026-10-23`. Frozen PR base: `build/parallel-foundation-2026-10-23` at `a8f8359354f44e11be39e22a55422b2cef9f6c91`. Other lane files and global HANDOFF/ADRs are controller-owned.

## First verified checkpoint

Implemented public request/source/OCR/snapshot types and selected-source coordinator in new `spikes/macos-context`. The first positive capture test failed on the unavailable interface, then passed. Eleven lifecycle tests subsequently produced 20 expected assertion failures before the lifecycle implementation; all 11 now pass. These checks exercise disabled launch, selected request provenance, denial/closure, disable/revoke, source change, superseding question, busy backpressure, uncooperative OS deadline, digest recheck and oversized OCR. No OS permission prompt or actual screen read occurred.

Current source uses pixel digest revalidation; controller requested OCR text/layout digest with separate pixel artifact identity for the next checkpoint. Real Apple adapter, synthetic Vision OCR and strict supplemental provider are still in progress. Native capture is unavailable until an explicit Enable/select action. Hardware permission/selected-window acceptance, full app composition and image understanding remain unverified.

Next: implement the compiled system picker/screenshot and Vision adapters, then freeze the strict supplemental fixture with controller and answer lane. See `docs/plans/2026-10-23-screen-context.md` and `spikes/macos-context/THIRD_PARTY_NOTICES.md`.

Test command in this sandbox redirects SwiftPM/Clang caches to `/private/tmp/relay-screen-*`, with `swift test --disable-sandbox --package-path spikes/macos-context`. The initial ordinary SwiftPM invocation failed because its global module cache was unwritable; the redirected build/test passed.
