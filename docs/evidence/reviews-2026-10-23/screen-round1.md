# Independent screen-context review

Reviewed 2026-10-23. PR #69, issue #64.

- Checkout: `<workspace>/work/relay-build-screen`
- Exact head: `ec2ef2565da6ff6d056c58f08eb06128dbc9bf36`
- Exact base: `a8f8359354f44e11be39e22a55422b2cef9f6c91`
- Review was read-only in the feature checkout. HEAD remained exact; initial and final `git status --porcelain=v1` were empty. No source, index, branch, commit, PR or remote mutation occurred.

## Actionable finding

### [P2] Use downscale-only configuration for the selected window

**Location:** `spikes/macos-context/Sources/RelayScreenContext/SystemSelectedWindowCapture.swift:80`

**Trigger:** The selected window becomes smaller after `filter.contentRect`/`pointPixelScale` determine the requested output dimensions at lines 71-76 and before the asynchronous screenshot captures its content. The configured output can then exceed the source's current pixel dimensions.

**Why:** `configuration.scalesToFit = true` explicitly asks ScreenCaptureKit to scale both up and down. Apple's installed public SDK documents this at `ScreenCaptureKit.framework/Versions/A/Headers/SCStream.h:257`: true scales up and down; false only scales down. Bounding the requested dimensions with `ScreenCaptureDimensions.fit` does not prevent this later resize case. Consequently, the actual adapter violates `docs/SCREEN_CONTEXT.md`'s "never upscaled" contract and may give Vision enlarged, softened pixels. This is a capture quality/bounds defect, not a source-scope or stale-publication bypass.

**Fix:** Set `configuration.scalesToFit = false`, retaining the existing 1920 maximum requested dimensions and aspect-ratio behavior. The existing dimensions-only test does not inspect this actual adapter configuration.

**Evidence:** Actual adapter source and installed public SDK semantics. No real screen capture was performed, so the runtime resize case was not exercised on hardware.

## Spec verdict

The library and ports substantially implement the assigned lane contract, with the one downscale-only mismatch above. Request the small adapter correction before merging this exact head. Final application/helper composition remains separately assigned and is not reported as an unexpected lane defect.

The reviewed source provides an explicit public single-window picker, selected filter retention, window/PID/bundle checks around the screenshot, local Vision recognition, bounded text/pixel dimensions, one capture/OCR/recheck operation, cancellation and timeout retirement with quiescence backpressure, original request/session/revision identity, separate text/pixel digests, original preview retention, strict supplemental text and exact-issued retirement frames, provider-issued snippet identity, and optional image policy disabled by default with bounded lazy native chunks and bounded Python assembly.

Final native admission remains a caller obligation: after the bounded observation recheck, synchronously check both the original native presentation lease and `coordinator.owns`. Age and digests are not proof of content at paint time. A change after re-observation remains an explicit TOCTOU interval.

## Quality verdict and limits

No independently supported stale-output, selected-source substitution, or retirement-clears-newer-context defect was found under the documented current-native-envelope precondition. The source separates untrusted OCR task text from personal authority and image capability, preserves transient preview identity, and documents OCR and external acceptance limits clearly.

An exploratory synthetic probe showed that the Python provider is not an independent global session-epoch authority: accepting epoch 2, calling `invalidate()`, then supplying both an old epoch-1 frame and its old matching envelope to `ingest` accepts that pair. This is not filed as a bypass because `ingest` requires the host to supply the actual current original native envelope. Controller composition must reject retired sessions/epochs/requests before invoking the port and must directly invalidate source authority on native source/permission/session retirement. Passing a retired envelope as current violates that precondition. The native coordinator independently rejects a same-session older epoch in `supersede`.

No real picker, selected screen, permission prompt/denial/revocation, window closure, image inference, model/account capability, OAuth, Keychain or private data was exercised. The actual Apple adapter's runtime behavior and on-device OCR quality remain external acceptance gates. Builder-reported native test/build results were read as supplied evidence, not rerun or relabeled as this review's results.

## Fresh review verification

- Read repository `AGENTS.md`, screen plan/contract/lane handoff, controller `BUILD_CONTRACT.md`, builder report, added Swift/Python sources, fixtures and lane tests. Reviewed the immutable added-file diff in manageable source/test passes.
- Inspected the installed Apple public SDK declarations for picker/filter/screenshot configuration and window metadata scope. No capture API was called.
- Five focused committed Python cases passed: revoke/replay; old completion preserving newer context; exact old/future retirement; unknown/disabled image policy; duplicate/out-of-order/gapped image chunks. Result: 5 tests, 0 failures, 0 skips.
- The focused old-envelope probe above ran with synthetic golden text only and bytecode writes disabled.
- `git diff --check <base> <head>` passed.
- No full repository or native suite ran. Feature checkout remained clean at exact head after verification.
