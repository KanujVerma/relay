# Automatic speech setup and session readiness

Design/research only,2026-10-23. Runtime baseline: `1f8e7fbc7e4c7a2f925e1380ddec67f46c5fc3a7`. Root subsequently published product direction at `c487975aef6eab78d41e64e6a839a05353641f60`; no runtime changes are inferred from that documentation commit. This file is the automatic-speech lane's proposed implementation contract. Runtime ownership must be frozen by root before edits.

## Recommendation

Retain the existing pinned FluidAudio ASR/VAD inference ports and automatic default choices. Add one managed asset resolver/download/cache coordinator in `RelaySessionCapture`. The main flow has one Start action: resolve verified cached assets, download missing assets with truthful progress, then enter the existing native capture start. No speech-model folder, detector folder or model-license checkbox appears in normal home/session UI. Advanced overrides belong in Settings.

Use an app-maintained, reviewed model dependency policy with exact source/license notices and immutable artifact manifest. This is not a user/legal approval inferred from file presence. The owner explicitly delegated default model selection/download; the UI should explain the first225MB preparation and link About/Settings notices without asking the user to understand ASR/VAD components. Source selection and authorized-recording/assistance consent remain distinct and meaningful.

Default preparation is triggered by an explicit first Start or setup action, not object construction or synthetic/fixture launch. No capture starts during download. A cancelled preparation never auto-starts later. Repeat starts use validated local assets offline and perform no model network request. Existing capture/admission/session/helper quiescence contracts remain unchanged.

## What is actually implemented today

- `RelayPanelSessionApp.swift:44-47` exposes two developer folder buttons and a model-license flag. `SessionApplicationModel` initializes ASR/VAD paths from optional launch arguments or empty strings. `startOwned` refuses Start unless both paths and two consent booleans are populated.
- `NativeCaptureConfiguration.validateLocalModels` checks existence of four ASR entries below `<root>/parakeet-eou-streaming/320ms` plus the supplied VAD `.mlmodelc`. This is a path/existence check, not artifact integrity or runtime-readiness proof.
- `FluidEouRecognizer` already chooses Parakeet EOU120M/320ms and loads only those local bundles in the capture path. `FluidSpeechActivityDetector.local` loads a provided Silero model and uses `.cpuAndNeuralEngine`; the ASR manager currently uses the upstream `MLModelConfiguration` default. Do not claim both are already forced to ANE.
- `NativeCaptureSession.prepare` constructs separate VAD and recognizer owners for microphone and selected-app audio. It loads models before starting drivers, preserves independent source state and retains uncancellable startup/shutdown work. The new resolver should feed these exact ports, not replace the audio pipeline.
- Current app Start creates/ensures a helper before validating the model paths. Managed setup should resolve assets before launching a new helper merely to discover that speech is unavailable, while preserving an existing helper/profile lifecycle.
- The current source is selected-app output, not all system audio. The process tap can include other tabs/process helpers belonging to a selected browser. A zero/silent tap is explicitly permission-unverified.

Source evidence: current `spikes/macos-panel/Sources/RelayPanelSession/SessionApplicationModel.swift`, `RelayPanelSessionApp.swift`; `spikes/macos-session/Sources/RelaySessionCapture/{NativeCaptureConfiguration,NativeCaptureSession,FluidSessionAdapters}.swift`; `spikes/macos-audio/asr/Sources/RelayLocalASR/FluidEouRecognizer.swift`; `spikes/macos-audio/Sources/RelayAudioBuffer/{SelectedAppProcesses,SelectedAppProcessTap,MicrophoneCapture}.swift` at the baseline.

## Production default and exact size

Keep SDK pin [`FluidAudio c79c4106b954f81205113c3343e5a7e59a1089b5`](https://github.com/FluidInference/FluidAudio/tree/c79c4106b954f81205113c3343e5a7e59a1089b5). Do not upgrade the speech engine or silently switch to the current library's batch TDT/Ultra/Redux defaults as part of removing pickers.

| Component | Exact selection | Immutable model revision | Required bytes |
| --- | --- | --- | ---: |
| ASR | `FluidInference/parakeet-realtime-eou-120m-coreml`,320ms, three compiled bundles plus vocab | `40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355` |224,238,270 |
| VAD | `FluidInference/silero-vad-coreml`, `silero-vad-unified-256ms-v6.2.1.mlmodelc` | `b419383c55c110e2c9271fa6ee0ea83d03c70d96` |1,063,425 |
| Total |21 files, no `.mlpackage`, conversion scripts, alternate chunks or unrelated models | manifest v1 |225,301,695 |

Total is225.3 decimal MB, approximately214.9MiB. The public320ms folder is approximately448MB because it also contains source packages and conversion material; download only the selected compiled runtime files. Sizes/revisions were read from the public Hugging Face API, not estimated from parameter count. No weight tensors were downloaded in this research phase.

The [converted model card](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml) documents the split runtime bundles and M2 benchmark; that benchmark is upstream evidence, not Relay's latency/accuracy. The [original NVIDIA card](https://huggingface.co/nvidia/parakeet_realtime_eou_120m-v1) states English-only output with no punctuation/capitalization. Keep320ms because it matches the accepted adapter and has higher upstream throughput/accuracy than160ms, not because320ms is end-to-end answer latency. The [Silero conversion](https://huggingface.co/FluidInference/silero-vad-coreml) declares MIT and the pinned SDK expects its4096-new-sample/256ms form. Do not substitute arbitrary Silero versions/shapes.

On16GBM2Pro, this is the lowest-change reasonable starting default, not a measured resource guarantee. Two recognizer owners may load the same compiled weights separately, plus CoreML caches/state. Measure warm/cold start, two-source resident memory, thermal/CPU and transcription quality before claiming live readiness or changing compute units. Do not infer RAM from225MB on disk.

## License and source policy

FluidAudio is Apache-2.0; its model weights have separate terms. The pinned ASR card records `license:other` with `license_name:nvidia-open-model-license` and the official [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/). VAD declares MIT. Retain exact model/source revisions, license IDs/URLs, notices and review date in the release manifest/About material; do not label all models Apache-2.0 from the SDK license.

Use an internal `ManagedSpeechPolicy` associated with this reviewed manifest to authorize the app's chosen dependency. A typed prepared-assets result should feed a managed `NativeCaptureConfiguration` initializer without requiring the normal user to toggle `modelLicensesAcknowledged`. Do not set that legacy flag merely because files exist or claim the user reviewed terms they did not review. Keep the existing explicit-license advanced/CLI path if it remains necessary for arbitrary user-supplied models. Package/download redistribution obligations should be retained in notices; this design downloads official public assets and does not assume weight bundling rights. This is a dependency policy record, not a legal eligibility determination.

## Downloader decision

Three approaches were examined:

1. **Retain manual folder choice.** Minimal code but fails the owner-approved normal experience. Keep only as an advanced override.
2. **Call pinned `ModelHub.download` into a managed staging directory.** It has useful tested resume/cancellation/retry behavior and can be pinned via process-global `ModelRegistry.revisionOverrides`, but also accepts global registry/repo overrides, ambient Hugging Face tokens, extra metadata selection and size-only artifact validation. Public progress exposes fraction/phase rather than exact byte counts. Its recovery logic may delete/replace managed cache paths. Hash validation and policy isolation would still need an app wrapper.
3. **Recommended: a small fixed-manifest Foundation downloader.** Reuse every FluidAudio inference/loading/capture port; use native `URLSessionDownloadTask` only for the21 pinned public files. No new voice framework or SDK, mutable remote discovery, ambient HF/OAuth token or registry-global mutation. Exact byte progress, immutable URLs and SHA-256 bounds are explicit. Reuse upstream cancellation/resume/testing lessons, not hidden private APIs or a wholesale downloader copy.

The pinned SDK source/tests were inspected: `Shared/Download/{ModelHub,FileDownloader,DownloadTypes}.swift`, `ModelRegistry.swift`, `ModelNames.swift`, and `ModelHubFileSelectionTests`, `ModelHubOfflineTests`, `DownloadArtifactValidationTests`, `FileDownloaderCancellationTests`, `DownloadCancellationTests`, `DownloadResumeTests`. The pre-cancelled-attachment regression is especially relevant: cancellation must latch before URLSession task registration so a cancelled action cannot start a request afterward. These upstream tests were read, not executed; some require model/network operations and global environment mutation.

Apple documents that [URLSessionDownloadTask](https://developer.apple.com/documentation/foundation/urlsessiondownloadtask) streams to a temporary file, reports written bytes, requires checking HTTP responses separately from client errors, and supports cancellation/resume when the server does. Use a foreground owned session; do not introduce background transfers that outlive cancelled setup.

## Managed cache, integrity and retry contract

- Managed root: `~/Library/Application Support/Relay/Speech/v1/<manifestID>/`. Preserve the existing adapter layout under `parakeet-eou-streaming/320ms/`; return the exact VAD bundle URL separately. Data is public model assets only, never recordings/transcripts/credentials. No model/cache files in Git.
- Build in a separate UUID staging directory under the managed root. Paths come only from the checked manifest; reject symlinks, traversal, unexpected files, wrong file type and any destination outside that root. Do not extract arbitrary archives. Mark ready only after all exact file sizes/hashes pass and the completed tree/manifest marker is atomically published. A marker alone is insufficient on subsequent starts.
- Required free-space preflight: at least1GiB before fetching this225MB set, to allow staging/retry/current assets. This is a conservative setup threshold, not a guarantee about CoreML runtime caches. Keep at most one active managed set, one previous set and one staging operation; never evict active/in-use assets. Do not delete shared FluidAudio caches or user override directories.
- Warm Start validates all21 local files asynchronously without network and returns the prepared-assets value. Keep startup hashing off MainActor. Missing/corrupt files require managed repair; file presence alone is not ready. The runtime's existing actual model load remains the final compatibility test before capture begins. The normal UI must not call assets verified equivalent to audio permission or a working recognizer.
- HTTPS immutable `resolve/<revision>/<path>` only, no auth header/cookies or caller-provided account identity. Follow only HTTPS redirects and enforce manifest byte bounds during transfer and final SHA-256 afterward. HTML/error bodies, unexpected status, oversized/short data and checksum mismatches fail; no arbitrary mirror/model fallback.
- At most two files concurrently. Keep one owned URLSession task/delegate record per active file, no whole-weight `Data` buffering. Aggregate actual stored/download byte progress plus completed files. If exact byte totals are unavailable, use indeterminate/fraction progress, not invented exact counts.
- Retry transient connection failures/408/429/5xx at most three attempts with bounded backoff and `Retry-After` capped at30s; never retry cancelled/permanent404/auth/checksum failures indefinitely. A checksum mismatch can discard and refetch only the named managed artifact once within the same finite budget. Corruption is not authorization to erase an arbitrary directory.
- Retain opaque resume data/partials only in this manifest's staging area and only for the exact immutable URL/length/validator. Final length and SHA-256 remain mandatory after resume. If safe resume cannot be established, restart that file. Cancellation/offline never promotes partial files. One explicit Retry restarts/resumes the same pinned plan.
- Offline + valid cache succeeds with no network. Offline + missing assets is a truthful unavailable state with Retry when connected; no cloud ASR or implicit alternate model. Model updates require a reviewed release manifest, not following mutable `main` on a later Start.

## Readiness API and UI boundary

Proposed API in the already-linked `RelaySessionCapture` product (no new package dependency):

```swift
enum SpeechSetupStage { case notPrepared, checking, downloading, validating, ready, unavailable, cancelled }
struct SpeechSetupSnapshot {
    let stage: SpeechSetupStage
    let completedBytes: UInt64?
    let totalBytes: UInt64?
    let progressFraction: Double?
    let userMessage: String
    let recovery: SpeechSetupRecovery // none, retry, openSettings
    let isBusy: Bool                 // includes real cancellation cleanup
}
@MainActor final class SpeechSetupCoordinator: ObservableObject {
    var snapshot: SpeechSetupSnapshot { get }
    func prepare() async throws -> PreparedSpeechAssets
    func cancel()                     // retires intent synchronously
    func waitForQuiescence() async
}
```

`PreparedSpeechAssets` has no public arbitrary-path constructor. It holds the reviewed manifest/policy identity and validated ASR root/VAD URL; it grants no capture or account authority. Snapshot `.ready` means local files verified, not permissions granted, recognizers loaded, account eligible, or interview audio observed. Fixed failure categories: offline, downloadUnavailable, insufficientStorage, invalidArtifacts, unsupportedPlatform, cancelled, advancedOverrideInvalid. Keep provider/raw errors out of ordinary UI and public logs; advanced Settings can expose bounded diagnostic codes.

UI/model adapter commands can be `prepareAndStart()`, `cancelPreparation()` and `retryPreparation()`. `retryPreparation` must not revive a cancelled Start intent automatically. `start()` may remain the single existing user action and internally prepare before starting. UI observes the coordinator rather than choosing model paths. Agreement with UI lane: all technical choices move to Settings; normal home shows one Start plus actual progress/error/retry, while source/permission state stays separate. `progressFraction` is optional alongside byte fields so no false precision is needed for an alternate downloader.

### Exact app bridge needed from the UI/root owner

1. **Init/readiness fields:** inject/own the coordinator with an inert default. Remove normal-flow ASR/VAD/license user fields; advanced override configuration is explicit and idle-only. No network, model load or OS prompt in init/fixture mode.
2. **Start/startOwned:** reserve one Start-intent UUID and existing `starting` state, validate explicit conversation/source choice, await `speechSetup.prepare()`, check the same uncancelled intent, create managed capture configuration, then call the existing native start. Resolve assets before creating a new helper solely for a doomed start. Actual `.running` remains dependent on native capture phase. Missing assets/download errors do not needlessly lock an existing protected profile.
3. **Retirement:** synchronously retire Start intent and call coordinator cancellation before the first await. Add `waitForQuiescence` to the existing pause/end/start-owner barrier before restart becomes possible. Do not set readiness/canResume from a local timer. Old completion callbacks cannot start capture, overwrite new progress or promote a replaced manifest.
4. **Advanced Settings:** optional explicit roots validated through a separate override policy; never mutate/corrupt managed assets or switch models mid-session. App start/source and visual-probe gating remain under existing native ownership.

Root accepted this API and assigned the automatic lane the narrow `SessionApplicationModel` init/start/cancel/retirement/readiness regions. The UI lane observes `model.speechSetup`, continues calling `await model.start()`, and may call `model.cancelPreparation()` or `await model.retryPreparation()`; it does not edit that model file. SwiftUI layout/window/Settings views remain the UI lane. Runtime work still waits for the isolated implementation checkout/branch assignment.

## Source choice and real permission behavior

Automatic model selection does not authorize arbitrary audio. Preserve an explicitly configured/previously approved selected app if available and visibly name it on Start. If no meaningful choice is available, request a meeting-source choice; do not silently select an unrelated app from ambiguity or broaden to all system audio. A unique known-meeting-app/previous-frontmost suggestion may reduce friction only as a visible suggestion confirmed by Start, with exact bundle/process resolution by the existing port. This lane does not invent or execute a new app allowlist.

Keep microphone inclusion separately controllable. Apple [authorization documentation](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media) requires real capture access and usage descriptions; the existing mic code requests at the user action and surfaces denial. Existing selected-app tap reports permission-unverified because no public process-tap TCC preflight is supplied. [CATapDescription](https://developer.apple.com/documentation/coreaudio/catapdescription) mixes the specified processes; it is not per-tab consent. No automatic global tap or alternate-app fallback. Source disappearance/permission revocation uses existing actual stop/quiescence and a useful source-specific recovery message.

Readiness must keep these states separate: asset preparation, selected source availability, microphone authorization, actual native capture phase, helper/account mode and visual verification. Neither `.ready`, a file hash nor an OAuth toggle establishes the others. Account/sign-in/chat/history/résumé design is outside this lane.

## Proposed disjoint write set after root approval

Automatic lane, new files only unless explicitly delegated:

- `spikes/macos-session/Sources/RelaySessionCapture/SpeechAssetManifest.swift`
- `spikes/macos-session/Sources/RelaySessionCapture/SpeechAssetStore.swift`
- `spikes/macos-session/Sources/RelaySessionCapture/SpeechAssetDownloader.swift`
- `spikes/macos-session/Sources/RelaySessionCapture/SpeechSetupCoordinator.swift`
- `spikes/macos-session/Tests/RelaySessionCaptureTests/SpeechSetupTests.swift` (split into targeted test files if needed)
- Narrow managed-assets initializer/policy seam in `NativeCaptureConfiguration.swift`, only after explicit file/region delegation.
- Assigned regions in `spikes/macos-panel/Sources/RelayPanelSession/SessionApplicationModel.swift`: stored/injected `speechSetup`, init, managed Start, cancel/retry, readiness predicates and retirement's cancel/join. No view/layout edits.

No changes proposed to native event/lease/controller, SourcePipeline, image authority, Python helper, profile/account core or capture teardown. UI lane owns views/Settings/window shell; the automatic lane owns the model bridge regions above. Root owns global docs/contracts/assembly. Third-party notices must be updated in the eventual implementation lane without concurrent edits to another owner's files.

## Required focused verification before delivery

Injected downloader/store tests, no weights/ASR/capture in default CI: empty cache; valid warm offline cache; corrupt/truncated/hash-mismatched file; invalid manifest/path/symlink; interrupted/resumed/cancelled transfer; cancellation before task registration; cancellation during validation; late callback after new intent; exact byte bounds; transient/permanent retry budgets; single-flight setup; bounded two-file concurrency; no new preparation before actual quiescence; wrong manifest revision; managed vs advanced ownership; actual Start bridge passes exact URLs/policy only after readiness; cancelled Start never calls capture; source/recording denial remains distinct; fixture/init make zero downloads or permission calls.

Production verification later: automatic225MB fetch and SHA validation to an isolated managed cache, app build, then authorized model load/capture/overlap/resource/latency checks after the Mac is unlocked. No full baseline suite rerun merely to repeat accepted capture evidence; run affected setup/native and app bridge checks, then root's joined gates. Real first-use permission, selected-app silence/denial and16GBM2Pro cold/warm resource behavior remain unmeasured.

## Exact v1 asset hashes

Public metadata checked2026-10-23. SHA-256 for LFS objects comes from the immutable Hub tree's LFS OID; SHA-256 for the small non-LFS graph/metadata/vocab files was computed from their immutable public resolve bytes in memory. No large weight tensor was fetched, no model loaded, no OS capture/permissions/private files/OAuth used. API sources: [ASR revision](https://huggingface.co/api/models/FluidInference/parakeet-realtime-eou-120m-coreml/revision/40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355), [VAD revision](https://huggingface.co/api/models/FluidInference/silero-vad-coreml/revision/b419383c55c110e2c9271fa6ee0ea83d03c70d96). Model tree files are the manifest boundary, not a dynamic runtime listing.

```text
# ASR paths relative to repository revision40a23f4c...
243    3996975a8cbc1949159c55605b3132b39b2484f51acbd55d796d93c70de02b49 320ms/decoder.mlmodelc/analytics/coremldata.bin
497    c3ccbff963d8cf07e2be2bd56ea3384a89ea49628922c6bd95ff62e2ae57dc34 320ms/decoder.mlmodelc/coremldata.bin
3283   0977480649f2756894b0acfe2fdf4231a991f25e3fe02562bfb71b65ca944575 320ms/decoder.mlmodelc/metadata.json
7409   b7c084a35bdbc887d69d6226cd533e2c11b2792c37d7352cf878f9f6f3c13555 320ms/decoder.mlmodelc/model.mil
7873600 0b4cacecdcd9df79ab1e56de67230baf5a8664d2afe0bb8f3408eefa972cb2f4 320ms/decoder.mlmodelc/weights/weight.bin
243    5bca32ad130dcad6605cc00044c752aa5b45ef57d14c17f2d1a2fa49d6cf55b5 320ms/joint_decision.mlmodelc/analytics/coremldata.bin
493    22d4abc4625b935ee035b5f8ce7cb28d1041b9b01c12173e287bf4b5f5d99625 320ms/joint_decision.mlmodelc/coremldata.bin
3181   e970ae87137730020690d24d971813db3633bbdfed602d43b6a9c84deced6dc8 320ms/joint_decision.mlmodelc/metadata.json
9608   45e8590bc87e34c162b547e43a4f60e64db15b017f48395d7835a6867884804f 320ms/joint_decision.mlmodelc/model.mil
2794182 7039b2010a269153f5a96edf28637f921a86ef8822f248f2d6712f7a6bce84b4 320ms/joint_decision.mlmodelc/weights/weight.bin
243    ae0a559f8d53c43fe13c5c142b15ca237b97812febde71a36475b7b9612baec5 320ms/streaming_encoder.mlmodelc/analytics/coremldata.bin
670    b57dfe32ed2acb0081f97d7a9e410117005823e3d2d995e21feb9e60775443c3 320ms/streaming_encoder.mlmodelc/coremldata.bin
5327   3adc7839db0f5d20b19e2dcd1c009bcf935a7edc61d7473c8150be444bd80488 320ms/streaming_encoder.mlmodelc/metadata.json
655998 eb9d56d7467ad3a8796ec9098b27fb89197638b31e24ede6dd924807d25086e6 320ms/streaming_encoder.mlmodelc/model.mil
212865856 ff553fcb4f4560cfce1e558e16bb9d856e4b4f6a4c08f800d5c126fce4196822 320ms/streaming_encoder.mlmodelc/weights/weight.bin
17437  83fd42ad33dae1bd3ceee6c0bb6c625f314cf0b2dc8430be441ac1e2643d5c36 320ms/vocab.json
# VAD paths relative to repository revisionb419383c...
243    8067594eb3126ab8318af507f0c00cabfed40d5fedb8a0ee5075dd02e903d909 silero-vad-unified-256ms-v6.2.1.mlmodelc/analytics/coremldata.bin
625    7db35a4fd995222a7fb0129713473b15d1462572ab4a2e5e4d56bcaad9e40f41 silero-vad-unified-256ms-v6.2.1.mlmodelc/coremldata.bin
3335   2740be542c611e1ba358e1849b4e265c65cdf0b17192767e1e5de86a31ac94d6 silero-vad-unified-256ms-v6.2.1.mlmodelc/metadata.json
176918 c6a9d1bf22d413265da0a07a1d14151c3ea2fad296b3aa5859275b33ef1c3270 silero-vad-unified-256ms-v6.2.1.mlmodelc/model.mil
882304 53ecc8b5081146140ab654c89109cf001f2183abddd7a2411c5081feeffff063 silero-vad-unified-256ms-v6.2.1.mlmodelc/weights/weight.bin
```

Research limitation: current primary model/API metadata was fetched; no weight/model runtime load, capture, real permission flow, account inference or locked-Mac bypass was attempted. Broad marketing claims about models were not used as proof of Relay behavior. The existing pinned source/test cache was read only. Initial sandbox DNS prevented direct public metadata requests; scoped read-only metadata/doc fetches were then authorized through the normal tool approval reviewer. No extra operator permission or model-weight download was required for this research.
