# Selected screen context implementation plan

Goal: build issue #64's optional selected-window capture and local OCR library, with a request-bound integration port. This lane executes inline under the controller's accepted build contract. No permission prompt or real screen capture is permitted during development.

Architecture: a main-actor coordinator owns enable/selection/request/permission revisions and one capture/OCR pipeline. Public Apple adapters supply the system single-window picker, screenshot capture, and local Vision OCR. A deadline retires admission immediately but keeps backpressure until an uncooperative OS call actually returns. The same coordinator validates the original snapshot against a fresh selected-window digest before native publication.

Write set: `spikes/macos-context/{Package.swift,Sources,Tests,THIRD_PARTY_NOTICES.md}`, `docs/SCREEN_CONTEXT.md`, `docs/lanes/SCREEN.md`, this plan; optional `relay_spike/screen_context.py` and `tests/test_screen_context.py`. Shared wire/fixtures and other lane files remain controller-owned.

## Tasks

- [x] Add public request/source/OCR/snapshot value types and dependency ports. Write a synthetic selected-source capture test, observe the unavailable implementation fail, then add the bounded lifecycle. Test disabled launch, denied capture, selected-window replacement, revocation, superseded question, late completion, timeout and busy rejection.
- [x] Implement local `VNRecognizeTextRequest` on an isolated queue, retaining line boxes/confidence, language correction disabled for code, bounded result text and cancellation. Render synthetic code/problem and diagram-label `CGImage` fixtures in memory; verify meaningful extracted labels and line separation without claiming diagram topology or exact code recovery.
- [x] Implement the macOS 15.2+ `SCContentSharingPicker` single-window adapter and `SCScreenshotManager`, with selected window/app/PID verification and no display fallback. Compile the actual public adapter. Add a SwiftUI selection/settings view with explicit Enable/select and Disable, preview and OCR limitations.
- [x] Freeze supplemental serialization with controller and answer owner. Add strict request-bound provider validation, replay/revision/source invalidation tests, native final digest validation contract, and no images on JSON wire. Keep the exact 13-key EOU schema untouched.
- [x] Record exact Apple/Muesli source pins, licenses, adopted/rejected components, observed tests and remaining hardware/image-inference gates. Commit and push passing coherent checkpoints, open a draft PR against `build/parallel-foundation-2026-10-23`, and report exact head/check status.

Verification: `swift test --package-path spikes/macos-context`; targeted Python unittest if the provider is needed. Default tests use synthetic images and fake capture providers only. No OS selection, screen read, user OAuth, model call, or private content in Git/CI.
