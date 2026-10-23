# Independent scoped automatic-speech review

2026-10-23. Reviewer: GPT-6.1 Sol, extra-high. Verdict: **changes requested for one P2 cancellation-ownership defect**. No additional material finding in the assigned delta. The original author owns the correction; this review changes no production source.

## Immutable target and scope

- Exact target: `fbceb0c972612e0aafb15b75b5825d84e268931b`.
- Parent: `1f8e7fbc7e4c7a2f925e1380ddec67f46c5fc3a7`; own commits `d3a0ca3bd4bf0f844880d9126f2352152554bd89`, `caeff29ed4a80fda72db2cbb14990304a718573f`, `fbceb0c972612e0aafb15b75b5825d84e268931b`.
- Fresh detached checkout: `work/relay-review-automatic-fbceb0c`, clean before and after review. Author, root, peer and UI checkouts were not edited. UI candidate `a100cd9` remains frozen.
- Complete13-file own diff read, including implementation, tests and notices. Contracts read from controller: `docs/CLUELY_PARITY_CONTRACT.md` and `docs/superpowers/specs/2026-10-23-automatic-speech-design.md`.
- Full parent-to-target patch SHA256: `c8a757a76ea43cba4f1bb62997c1a3b32b3f6d2ef5b77afd79eb86cd2be6c081`.
- Unchanged FluidAudio inference, capture/event/lease, image, helper, profile and answer code are reviewed dependencies, not a new broad audit.

## P2: an obsolete preparation waiter's cancellation can cancel a new operation

Location: `spikes/macos-session/Sources/RelaySessionCapture/SpeechSetupCoordinator.swift:101`.

The cancellation handler enqueues `Task { @MainActor [weak self] in self?.cancel() }`. That delayed callback is not bound to the operation represented by `owned.id`. The public coordinator explicitly coalesces concurrent callers. When one old caller completes and publishes ready, an observer can start a fresh preparation while a second old caller is still awaiting delivery. Cancelling that obsolete waiter queues its callback after the new preparation. When the callback runs, `cancel()` retires whichever operation is current, so the fresh request is cancelled by an unrelated old request.

The exact-source probe uses two coalesced callers, a synchronous ready-state observer, and a held synthetic preparation. The observer queues a fresh high-priority preparation and then cancels the obsolete low-priority waiter. No filesystem, download, model, capture or account is involved. In10/10 iterations, the fresh preparation actually starts and then reports `replacement_state=cancelled busy=true`. The otherwise identical positive control leaves the obsolete waiter uncancelled;10/10 iterations report the fresh operation still `checking busy=true`. Cleanup cancels/releases the synthetic operation only after logging those states.

This violates the intended late-callback/current-operation fence and can make a valid new prepare/Retry unexpectedly fail. It does not demonstrate unauthorized capture. Bind the delayed cancellation to `owned.id`, retire only that matching operation, and preserve direct public cancellation of the current operation. Add a focused regression for the obsolete coalesced waiter/new-operation sequence and retain actual cleanup-before-restart behavior. No broader lifecycle redesign is needed.

Probe sources/results are preserved in `automatic-fbceb0c-probes/` beside this report:

- `CoordinatorProbe.swift`, SHA256 `6e7311fd0504c26ee3f01c2f54c216dc9a44b2a4f16d4b8286a34ef6f0a1bda5`.
- `CoordinatorControl.swift`, SHA256 `cdf9a24cac5586bda2613e79a133b53aaf8c3fef25ca097eb4c35af31ebbc46b`.
- `coordinator-probe.log` and `coordinator-control.log` preserve the ten observed states each. The programs log observations and exit successfully when the harness completes; exit0 is not a claim that the defective behavior passed an assertion.

Reproduction from the detached target:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-automatic-review-clang \
swiftc -swift-version 6 -parse-as-library \
  spikes/macos-session/Sources/RelaySessionCapture/SpeechSetupCoordinator.swift \
  spikes/macos-session/Sources/RelaySessionCapture/SpeechAssetStore.swift \
  spikes/macos-session/Sources/RelaySessionCapture/SpeechAssetDownloader.swift \
  spikes/macos-session/Sources/RelaySessionCapture/SpeechAssetManifest.swift \
  ../coordination-2026-10-23/automatic-fbceb0c-probes/CoordinatorProbe.swift \
  -o /private/tmp/relay-automatic-review-probes/coordinator-probe
/private/tmp/relay-automatic-review-probes/coordinator-probe
```

Substitute `CoordinatorControl.swift` for the positive control. The harness compiles the four exact new production files directly against Foundation/Combine, without package resolution or new dependencies. Local toolchain: Swift6.4/macOS27.0.1. Narrow correction re-review should rerun both probes plus affected coordinator tests; no repeat of the whole accepted runtime is required.

## Specification and quality assessment

The manifest independently matches every specified immutable revision/path/size/hash:21 files,225,301,695bytes, including16 ASR and5 VAD artifacts. Offline parsing compared all21 entries with the contract's hash table, not just totals. Manifest source SHA256 is `073d18249b6a1ae03157fbefb7cb7546ee235a631cc53b10f87fa49ed14d0d40`.

The internally constructed prepared-assets value and separate managed capture policy avoid fabricating the old user acknowledgment. Source/conversation consent remains independent. Default construction is inert; fixture Start bypasses preparation. The model checks consent/source before setup, uses a Start identity, rechecks choices/currentness before helper/capture, and joins setup/old Start during retirement. Advanced nonempty roots retain a separate explicit policy. Ordinary errors use fixed recovery messages.

The store/downloader have bounded two-file concurrency, finite attempts and overall deadline, explicit public immutable URLs, no ambient credential/cookie store, HTTPS redirect checks, streamed temporary files, exact length/hash checks, same-root locking and complete staged-tree promotion. Cache inspection rejects unsafe file types/symlinks and does not trust the marker alone. These boundaries were read in full; no unrelated framework or inference change is introduced. The coalescing/currentness tests missed the delayed cancellation-to-new-operation edge above.

Independent read-only cache proof: `CacheReadProbe.swift` calls only `SpeechAssetStore.cachedAssets()` on the supplied existing public `/private/tmp/relay-auto-speech-real-cache`. It revalidated the complete tree and all21 hashes, yielding manifest `parakeet-eou320-silero621-v1` and225,301,695bytes. It does not call prepare, create a lock, write/delete cache files, fetch assets or load CoreML. Source SHA256 `72704fcdeac3fdc0db9c5ae04640263593c87d1a677d8001c84f3414da39553a`; result is in `cache-read.log`.

## Limits and next action

Author's22 asset cases (21 pass/1 opt-in skip),23 affected app cases and product/signature evidence were inspected as declared baseline evidence. They were not re-labelled as a fresh full independent run. The targeted native probes above are this review's new execution evidence. No full suite, real download, model load, microphone/process tap/screen/AX permission, Keychain/account/private data or visible UI was exercised. The Mac remains locked. Permission behavior, live recognition quality, two-source resource use and visible end-to-end Start remain separate acceptance work.

Root and original author received the concrete P2 and probe paths. Wait for a new immutable author correction, then narrowly re-review cancellation ownership and affected tests before accepting the automatic slice. This report's target remains the frozen original `fbceb0c`.
