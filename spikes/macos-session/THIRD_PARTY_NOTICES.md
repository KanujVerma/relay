# Native session dependencies and adapted patterns

FluidAudio SDK source is pinned to `c79c4106b954f81205113c3343e5a7e59a1089b5`, Apache-2.0: https://github.com/FluidInference/FluidAudio/tree/c79c4106b954f81205113c3343e5a7e59a1089b5 . Relay links `VadManager`, `VadStreamState`, `processStreamingChunk`, `StreamingEouAsrManager` through the existing `RelayLocalASR` adapter, and `AudioConverter`. No recognition source is copied. The dependency retains its upstream license/notices and pinned NemoTextProcessing binary artifact. Model weights are separate artifacts/licenses. Parakeet EOU weights use the NVIDIA Open Model License; see ../macos-audio/asr/THIRD_PARTY_NOTICES.md. The VAD compiled model is explicitly supplied by the user; no artifact licensing or byte-level reproducibility is inferred from the SDK license. No model downloader is invoked in this package. The actual provided-model VadManager initializer avoids its directory loader's ModelHub/download fallback.

Existing `RelayAudioBuffer` selected-app/microphone adaptations and pinned TPCircularBuffer remain governed by ../macos-audio/THIRD_PARTY_NOTICES.md. No global tap or recorder was added.

SourcePipeline.swift and NativeCaptureSession.swift narrowly adapt the generation/single-drainer and cancel-during-start/quiescent-shutdown ownership patterns from Muesli at `cb0ceb9da89a2d95b17d26d149c2865e43f7e54e`: https://github.com/Muesli-HQ/muesli/tree/cb0ceb9da89a2d95b17d26d149c2865e43f7e54e . Inspected source: StreamingVadController.swift, MeetingCaptureLifecycle.swift and MeetingCaptureShutdown.swift; inspected tests: StreamingVadControllerTests.swift. Local tests replace upstream's timers and large application dependencies with deterministic fake producer/model barriers. Relay caps its pending VAD queue, removes wall clock, recording URLs, logging of raw errors, WAV/dual-track/AEC/retention code and automatic source fallback. Upstream tests were read, not executed. The matching MIT notice follows.

MIT License

Copyright (c) 2026 Pranav Hari

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
