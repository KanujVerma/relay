# Managed speech dependencies

Research/selection verified2026-10-23. This is a reviewed application dependency policy, not an assertion that a user accepted terms because files exist. Normal setup has no model/detector chooser or per-start model-license checkbox. Source/recording/assistance permission remains independent.

## Runtime source

FluidAudio SDK is Apache-2.0 at [`c79c4106b954f81205113c3343e5a7e59a1089b5`](https://github.com/FluidInference/FluidAudio/tree/c79c4106b954f81205113c3343e5a7e59a1089b5). Existing Relay adapters invoke `StreamingEouAsrManager`, provided-model `VadManager`, native CoreML and `AudioConverter`. No upstream inference source is copied or patched, and no new voice framework is added. Existing notices in `spikes/macos-session/THIRD_PARTY_NOTICES.md` and `spikes/macos-audio/asr/THIRD_PARTY_NOTICES.md` remain applicable.

## Selected model assets, separate licenses

- ASR: [FluidInference/parakeet-realtime-eou-120m-coreml](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml/tree/40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355/320ms), revision `40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355`, only compiled320ms encoder/decoder/joint and vocab.16 files,224,238,270bytes. Card declares `license:other`, `license_name:nvidia-open-model-license`, with the [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/). Original model: [nvidia/parakeet_realtime_eou_120m-v1](https://huggingface.co/nvidia/parakeet_realtime_eou_120m-v1). English only; no punctuation/capitalization. A chunk duration is not an end-to-end transcription/answer latency promise.
- VAD: [FluidInference/silero-vad-coreml](https://huggingface.co/FluidInference/silero-vad-coreml/tree/b419383c55c110e2c9271fa6ee0ea83d03c70d96), revision `b419383c55c110e2c9271fa6ee0ea83d03c70d96`, only `silero-vad-unified-256ms-v6.2.1.mlmodelc`.5 files,1,063,425bytes. Model card declares MIT; original [Silero VAD](https://github.com/snakers4/silero-vad) retains its own notice.

Combined set:225,301,695bytes/21 files. Exact paths, sizes and SHA-256 are in `SpeechAssetManifest.swift`; LFS hashes were read from immutable public metadata, and small non-LFS file hashes were computed from immutable source bytes. SDK source pinning alone would not pin model bytes. Do not follow mutable `main`, download alternate model variants, or treat SDK Apache-2.0 as the weights' license.

Weights remain outside Git/CI. The managed downloader fetches official public assets; this record does not assume redistribution/bundling rights. Retain the linked license/attribution information in About/Settings and managed model notices. Arbitrary advanced local roots retain their separate explicit policy. None of these records grants microphone/process-tap/screen permission or account inference capability.

## Native provisioning reuse

Foundation `URLSessionDownloadTask` and CryptoKit supply streaming downloads/progress/cancellation and integrity. [Apple download documentation](https://developer.apple.com/documentation/foundation/urlsessiondownloadtask) documents temporary-file placement, written-byte progress and cancellation/resume. No model/HF/OAuth credential is needed for these public assets.

Pinned upstream `ModelHub`, `FileDownloader`, `DownloadTypes`, `ModelRegistry`, file-selection/offline/artifact-validation/cancellation/resume tests were inspected. Their public repository download API allows mutable registry/revision globals, ambient HF tokens and extra metadata selection, exposes fraction/phase rather than exact raw byte progress and validates size rather than this manifest's SHA-256. Relay therefore uses a narrow fixed-manifest native provisioning layer while preserving all existing FluidAudio model-loading/inference ports. Cancellation-before-task-registration, finite retries, atomic placement and cache ownership are reused lifecycle lessons; no upstream downloader code is copied.

Real16GBM2Pro model load, dual-source resources, permission behavior, audio quality and latency are separate acceptance measurements. Initial implementation verification uses generated tiny artifacts and injected transport, no real speech/capture/account operations.
