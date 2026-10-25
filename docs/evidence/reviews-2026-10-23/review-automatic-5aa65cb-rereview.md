# Automatic speech cancellation correction: scoped re-review

2026-10-23. GPT-6.1 Sol, extra-high. **Accepted for the scoped automatic-speech slice.** The original P2 is corrected; no additional material finding in the narrow correction. Root assembly and real-device acceptance remain separate.

Target `5aa65cb8ed0dfb5ffde5f32f32517b85880c500d`, exact parent `fbceb0c972612e0aafb15b75b5825d84e268931b`. Fresh detached checkout `work/relay-review-automatic-5aa65cb` stayed clean. The original detachedfbceb0c checkout and [original report](review-automatic-fbceb0c.md) remain frozen. Correction patch SHA256: `1f5fd38106db608a4345807d89ec60891575a89d17f82f2b9c657f5f5d697559`.

## Correction inspected

Read the entire3-file correction: owned-operation cancellation in SpeechSetupCoordinator, the ready-observer/coalesced-waiter regression and lane evidence. No asset, capture, model bridge, manifest, helper, profile, UI or policy source changed.

The cancellation handler now captures `owned.id` and calls a private cancellation method that requires the current operation to have that exact UUID. An obsolete callback cannot retire a replacement. Public explicit `cancel()` still synchronously cancels the actual current operation and keeps busy until real cleanup. Existing generation/progress/publication and wait-for-quiescence fences remain intact.

## Independent execution

- Recompiled the **unchanged original** `CoordinatorProbe.swift` from the durable original probe directory against the four exact corrected speech files.10/10 runs report replacement started, `checking`, busytrue. The originalfb source reported replacement cancelled in10/10 runs.
- Recompiled the unchanged positive `CoordinatorControl.swift`.10/10 runs also remain checking/busytrue. No cancellation is injected by this control.
- Ran all6 `SpeechSetupTests` from the fresh correction checkout:6 passed, zero failures in0.060s. This includes the new3-schedule regression, actual cancelled-operation cleanup, coalescing, late progress/currentness and managed policy checks.

Command:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-automatic-review-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-automatic-review-swift \
swift test --disable-sandbox --disable-automatic-resolution --skip-update \
  --package-path spikes/macos-session \
  --cache-path /private/tmp/relay-composition-cache \
  --scratch-path /private/tmp/relay-review-automatic-build \
  --filter SpeechSetupTests
```

The reviewer scratch was seeded only with this lane's already pinned public dependency/artifact cache, avoiding network or credential resolution. No model assets were copied or loaded. Standalone compilation commands are unchanged from the original report except for using this correction checkout's exact source.

Results are preserved in `automatic-5aa65cb-probes/{coordinator-fixed.log,coordinator-fixed-control.log,SpeechSetupTests.log}`. Original harness sources/hashes remain in `automatic-fbceb0c-probes/`. The standalone programs log observed states; the actual XCTest regression asserts the new operation completes and the coordinator becomes ready after release.

## Limits

No repeated full suite, download, real provisioning, model load/capture, permission, Keychain/account/private data or visible UI operation was performed. Original manifest/cache/transport review evidence remains applicable because those files are unchanged. The author's9 affected app setup tests are declared source-owner evidence, not relabelled as this review's fresh execution. The Mac remains locked; permission behavior, live recognition, resources and visible end-to-end Start remain explicit later acceptance gates.
