# Managed local speech dependencies

Reviewed 2026-10-23. Relay's normal Start prepares the fixed public runtime files below. The managed download is 225,301,695 bytes across 21 files. Models run through the existing FluidAudio ports; downloading files does not establish recording permission, account eligibility or runtime quality.

| Component | Exact source | License |
| --- | --- | --- |
| FluidAudio SDK | [c79c4106b954f81205113c3343e5a7e59a1089b5](https://github.com/FluidInference/FluidAudio/tree/c79c4106b954f81205113c3343e5a7e59a1089b5) | Apache-2.0; retained existing SDK notices apply |
| Parakeet realtime EOU 120M Core ML, 320 ms | [FluidInference/parakeet-realtime-eou-120m-coreml at 40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml/tree/40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355) | Model card declares NVIDIA Open Model License, distinct from the SDK license |
| Silero VAD unified 256 ms v6.2.1 Core ML | [FluidInference/silero-vad-coreml at b419383c55c110e2c9271fa6ee0ea83d03c70d96](https://huggingface.co/FluidInference/silero-vad-coreml/tree/b419383c55c110e2c9271fa6ee0ea83d03c70d96) | MIT, as declared by the model card |

The ASR original is [NVIDIA parakeet_realtime_eou_120m-v1](https://huggingface.co/nvidia/parakeet_realtime_eou_120m-v1). Read the [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/) for its terms. The reviewed default is English only and does not add punctuation or capitalization. Upstream benchmark claims are not Relay measurements.

`SpeechAssetManifest.managedDefault` is the exact file/byte/SHA-256 boundary. It selects 16 ASR compiled-runtime files (224,238,270 bytes) and 5 VAD compiled-runtime files (1,063,425 bytes); conversion scripts and `.mlpackage` source archives are excluded. LFS hashes were checked against immutable public tree metadata; small non-LFS files were fetched from the pinned resolve URLs and hashed during research. No weight files are committed or fetched by ordinary tests/CI.

The owner delegated reviewed default selection/download. Managed dependency policy is established by this app manifest and notices, not a fabricated user checkbox or file-existence-based legal approval. Explicit local-folder overrides retain their separate acknowledgment policy. Audio-source choice, authorized-conversation consent and actual macOS access remain independent.

## Actual reuse and rejected alternatives

Existing FluidAudio recognition/VAD and native capture loaders remain unchanged. The new adapter invokes Foundation `URLSessionDownloadTask` and CryptoKit SHA-256; it copies no upstream downloader implementation. The pinned FluidAudio `Shared/Download` source and cancellation/offline/resume/artifact tests were inspected as design evidence, not executed as Relay tests. Direct `ModelHub` provisioning was rejected because this fixed plan must avoid process-global registry/revision overrides, ambient Hugging Face credentials, dynamic file discovery and size-only validation. No new voice framework, inference endpoint or account path is introduced.

Apple documents temporary-file streaming and separate HTTP status validation in [URLSessionDownloadTask](https://developer.apple.com/documentation/foundation/urlsessiondownloadtask). The app uses foreground owned transfers and accepts HTTPS redirects only. No background download survives canceled setup. A failed file restarts within the finite attempt budget; opaque resume data is not persisted in this implementation.
