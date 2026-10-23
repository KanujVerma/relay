# Third-party code and model license audit (2026-10-22)

## FluidAudio SDK

Swift source: https://github.com/FluidInference/FluidAudio
Pinned Git revision: `c79c4106b954f81205113c3343e5a7e59a1089b5` (Oct 21, 2026).
SDK license: **Apache License, Version 2.0**. The license and original notices are retained by the upstream Swift Package Manager dependency. Relay links its public `StreamingEouAsrManager` and `AudioConverter`; **no copied recognition source** is vendored.

The pinned SwiftPM package includes other audio/TTS sources and a prebuilt `NemoTextProcessing.xcframework` dependency. Building the optional ASR package may require network access to retrieve the pinned source and that upstream binary. The main Relay audio capture package does not depend on FluidAudio or load its models.

## Parakeet EOU model weights, separate license

Model: https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml
Original: https://huggingface.co/nvidia/parakeet_realtime_eou_120m-v1

**Model weights are under the NVIDIA Open Model License, NOT the FluidAudio SDK's Apache-2.0 license.** Terms: https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/

The user must review the license before downloading, using the explicit CLI flags `--prepare-model --accept-nvidia-license`; the flag is an acknowledgement, not an evaluation of legal eligibility. Model redistribution/package bundling is NOT assumed. Neither weights nor any voice recordings are committed to public GitHub. Model files remain outside the repository in a user-specified local cache.

The pinned FluidAudio manager selects the `FluidInference/parakeet-realtime-eou-120m-coreml/320ms` artifact path, cached below `<ROOT>/parakeet-eou-streaming/320ms` with model bundles, vocab and decoder/joint. The SDK's downloadable model revision is provider-controlled unless separately pinned via a downloaded manifest; do not claim **model byte-level reproducibility** from pinning SDK source alone.

## Other audio foundation dependencies

`RelayAudioBuffer` is supplied from the adjacent existing `../Package.swift` package. It depends on upstream zlib-style Michael Tyson `TPCircularBuffer` at pinned SHA `cc520397504bb72bc6df79ff03eb72988a6dc50d`, and selected patterns in original MIT SystemAudioKit source. Their notices live at `../THIRD_PARTY_NOTICES.md`.

No cloud ASR API, paid transcription service, voice cloning, covert recording or speaker biometric inference is included.
