# Relay macOS audio stack: open-source reuse assessment

**Status:** research and implementation recommendation, NOT a selected production dependency or a passing Mac audio test. Reviewed 2026-10-22. Parallel issue: https://github.com/KanujVerma/relay/issues/19.

## Product requirement and ownership boundary

Relay needs authorized, low-latency spoken-question recognition in Zoom/other meeting apps on a 16 GB M2 Pro Mac. It is a personalized interview copilot, not an audio-recording product or an education platform. Priorities are: accurate question text, microphone versus remote-call attribution, interrupted/corrected turns, modest memory/CPU, and no separately billed transcription API.

This research is **independent of Issue #17** (verified-fact/provenance SQLite schema). It does not modify Personal Brain data definitions, streaming_qa.py, HANDOFF.md, or accepted ADRs. Future audio events must enter a narrow typed boundary rather than coupling to a memory database.

## Source-code review and reusable candidates

| Component | License / evidence | What already exists | Fit and critical gap |
|---|---|---|---|
| Apple's Core Audio process taps | Official platform sample | Capture outgoing audio from a process/group via a process tap and aggregate device | Best native API reference; custom real-time PCM handoff and permission/error handling still needed |
| SystemAudioKit by pieralukasz | MIT; Package.swift targets macOS 14.2+; new project with a small upstream history as of review | Select-app or all-system audio taps, ScreenCaptureKit fallback, mic capture, host-clock-aligned tracks and meeting detector | **Not a drop-in live ASR input.** Its public AudioRecorder exposes onLevels, while AudioRecorder + AlignedTrackWriter write mic/system WAV to disk. Adapt/fork a *buffer sink* only after a Mac smoke test, preserve notices |
| AudioCap by insidegui | BSD-2-Clause; educational Core Audio sample | Shows CATapDescription, AudioHardwareCreateProcessTap, aggregate device, tap callback and cleanup | Useful independent reference to verify SystemAudioKit tap and lifecycle logic; file-oriented sample is not an always-on transcription service |
| FluidAudio by FluidInference | Apache-2.0 SDK, Swift/CoreML; check individual model licenses separately | Local ASR, Silero VAD, streaming English Parakeet EOU, batch Parakeet, speaker diarization, optional echo reduction | Strong first ASR candidate. Compare EOU latency/accuracy, cold-start and RAM on target M2 Pro before committing to a particular model/version |
| Argmax OSS Swift (WhisperKit/SpeakerKit) | MIT umbrella repo, upstream third-party notices apply | CoreML Whisper transcription, speaker toolkit and open-source mic streaming example | Good fallback/quality reference. Advanced real-time transcription with speakers/custom vocabulary is advertised separately in **Argmax Pro**; do not assume paid-only capabilities are in OSS |

Source URLs and inspected code (all accessed 2026-10-22):
- https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps
- https://github.com/pieralukasz/SystemAudioKit
- https://github.com/pieralukasz/SystemAudioKit/blob/main/Sources/SystemAudioKit/AudioRecorder.swift
- https://github.com/pieralukasz/SystemAudioKit/blob/main/Sources/SystemAudioKit/AlignedTrackWriter.swift
- https://github.com/pieralukasz/SystemAudioKit/blob/main/Sources/SystemAudioKit/ProcessTapCapture.swift
- https://github.com/pieralukasz/SystemAudioKit/blob/main/Sources/SystemAudioKit/MicrophoneCapture.swift
- https://github.com/insidegui/AudioCap
- https://github.com/FluidInference/FluidAudio
- https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/GettingStarted.md
- https://github.com/FluidInference/FluidAudio/blob/main/Documentation/API.md
- https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md
- https://github.com/argmaxinc/argmax-oss-swift

### Important finding: capture versus in-memory streaming

SystemAudioKit provides a useful **capture mechanism and synchronization reference**, but the inspected AudioRecorder.start creates recording files (system.wav and microphone.wav). AlignedTrackWriter's public output is a WAV, with an onLevel callback for metering rather than a documented public PCM chunk stream. Writing files by default conflicts with Relay's low-latency, no-retention-by-default posture.

Recommendation: prototype an in-memory, bounded Swift PCM sink using the Core Audio process-tap callbacks and microphone buffers. Reuse or adapt SystemAudioKit's app selection, device-change lifecycle, host-time alignment and permission checks where source code proves appropriate. Do not perform file I/O, ASR inference, allocation-heavy resampling, or UI updates on a real-time audio callback. Copy only needed components subject to preserving MIT/BSD notices; a targeted adapter is preferable to importing the entire recorder without an in-memory path.

### Streaming ASR choice

FluidAudio's *Parakeet EOU* is a specifically documented streaming 120M English model. Its StreamingEouAsrManager handles 160/320/1600 ms chunks and end-of-utterance detection. **This EOU manager does not emit partial text from `process(audioBuffer:)`: it returns an empty string until a finalized transcript is obtained via `finish()` after EOU.** The later hardware spike must measure time-to-final-text for this manager, not claim a first partial. If an early on-screen partial proves necessary, compare a different explicitly partial-producing API (such as FluidAudio's SlidingWindowAsrManager) in a separate measured test. The documented default EOU silence debounce is approximately 1280 ms, so the setting itself can add more than a second after speech ends. This is a parameter to measure/tune for question recognition, not an optimal setting that we should hard-code.

Upstream benchmarks on an **M2 Mac, macOS 26** reported LibriSpeech test-clean average WER **8.23% at 160 ms** versus **4.88% at 320 ms**. These are upstream **dataset-specific** numbers, NOT Relay accuracy on a user's M2 Pro, nor an evaluated SQL vocabulary result. Start with a 320 ms baseline, compare 160 ms on actual interview-like audio, and report accuracy *and* end-of-question latency. The cheaper/faster setting may be wrong for jargon and code-spelling tasks.

Batch Parakeet models (including v2 English, v3 and ultra) may be useful as an optional post-utterance re-transcription or quality baseline, but should not replace the actual streaming endpoint without latency tests. Keep neural diarization off by default when mic and remote audio are genuinely captured separately. FluidAudio offers optional echo suppression (LocalVQE beta), but that should be evaluated only if speaker audio leaks back into the microphone.

Argmax OSS WhisperKit is a valuable backup benchmark because the open-source project supports Apple Silicon and streaming microphone transcription. Its separately advertised Pro real-time-with-speakers capabilities are not free OSS features; avoid assuming they are available without new costs.

## Provisional architecture, with narrow boundaries

    authorized Zoom/System Audio ──> Core Audio process tap ──┐
                                                             ├── bounded PCM queues
    authorized local microphone ──> AVAudioEngine mic tap ────┘         |
                                                                       v
                                                        per-channel normalization
                                                          16 kHz mono Float32
                                                                       |
                                                 local streaming ASR + EOU (FluidAudio)
                                                                       |
                                                    timestamped transcript events
                                                                       |
                                           question/turn detection in a later slice
                                                                       |
                                       existing turn-safe streaming QA (separate)

The **capture source** supplies a first-level user-versus-remote label, not definitive voice biometrics. Remote output can contain multiple interviewers; channel separation alone cannot identify each. Acoustic echo, headphones changing, virtual devices, browser audio helpers and app mixing must be handled explicitly. Only add speaker diarization for multiple remote participants after a real use case and latency budget justify it.

### Interface proposal, not committed schema

- AudioFrame: source_channel (microphone or remote), monotonic_host_timestamp, sample_rate, **owned** float32_mono_samples in a fixed-capacity bounded ring slot (or an equivalent transferred-ownership buffer), frame_count, stream_generation, discontinuity/drop flag. **Never queue a borrowed Core Audio `AudioBufferList` or a no-copy `AVAudioPCMBuffer` whose backing storage can be reused as soon as the capture callback returns.** Release/recycle owned slots only after the consumer completes; copy efficiently on the callback thread without blocking, heap allocation, file I/O or neural inference.
- TranscriptEvent: source_channel, segment_id, start/end time, partial_or_final, text, optional confidence, EOU marker, stream_generation.
- AudioSourceState: permission_state, selected_processes, mic_device_id, capture_status, error_reason, start/stop time.
- Event downstream MUST be immutable after finalization; interim partials are replaceable by matching segment ID and generation. Never write audio to the Personal Brain or label a speaker's utterance as confirmed autobiographical history.
- Implement bounded queues with clear overflow policy (drop/mark missing frames), never block Core Audio realtime callback. On stop/revocation, stop tap and discard in-memory buffers immediately.
- Keep sources separate through ASR. Combine into conversational turn IDs only in the question state machine, which already uses ID/version/generation for stale cancellation.

### Permission boundaries

- Request macOS microphone permission using the public AVFoundation authorization API. For **Core Audio process taps**, there is **no equivalent public preflight/request API**: initiating tap I/O triggers the system's System Audio Recording Only prompt. SystemAudioKit's optional preflight uses **private TCC symbols**, which Relay should avoid adopting for a distributable application. Show explicit user-facing consent status and document the macOS setting to enable/re-enable access.
- If the user denies system-audio capture, the Core Audio tap may **continue returning zeroed/silent buffers instead of failing at startup**. Never interpret successful creation or a stream of silence as proof of permission. Distinguish permission-denied/silent output from legitimate quiet audio when possible using public signals, user-facing settings, and a known-audible synthetic test; mark uncertainty rather than presenting an authorized/healthy state. If Core Audio tap fails, ScreenCaptureKit fallback may need broader Screen Recording authorization; **never silently upgrade scope**.
- User decides whether meeting transcription is authorized; consent may vary by jurisdiction/platform.
- Default raw audio retention OFF, no automatic cloud upload and no hidden listening while disabled. An overlay is not reliably absent from every screen-sharing method.
- Connected ChatGPT inference does not inherit audio permissions. There is no need to send raw audio to ChatGPT for local ASR.

## Next independent native Mac experiment: 03A-1

**Do not mark audio capture complete from this research.** Create a small Swift Package/native command line capture spike on a real Mac, in a new slice after this research PR is reviewed. Limit the first implementation to system-app PCM callback + mic PCM callback + **on-device CoreML ASR inference** yielding finalized local transcript text for *synthetic/consented* speech; no Zoom UI, no ChatGPT/remote language-model inference, and no Personal Brain integration.

Suggested acceptance checks:

1. Mic and selected Zoom (or consented Meet) remote output produce separate, correctly attributed timestamped PCM streams. Test with wired/Bluetooth headphones and without; verify host-time alignment and silence gaps.
2. Verify microphone permission using the public API and system-audio permission via the OS prompt and user-visible settings. In a deliberately denied or revoked process-tap test, assert that apparently running but **all-zero audio does not register as successful authorized capture**. There is no supported system-audio preflight equivalent to microphone permission; do not rely on private TCC calls. Do not auto-switch to broader Screen Recording access.
3. Add in-memory bounded buffer plumbing, detect overrun, test stop/restart and output device switch. No per-session WAV written unless an explicit future recording feature is separately enabled.
4. Run FluidAudio's streaming EOU on isolated synthetic English/code/SQL clips at 160 and 320 ms; measure word error rate on *known reference transcript*, abbreviations and words such as CTE, LEFT JOIN, Big-O, PostgreSQL, NULL and GROUP BY. Treat upstream WER as context, not validation.
5. Record cold and warm ASR initialization, **time to first finalized EOU transcript** from `finish()` after a known spoken ending (not a nonexistent partial from `StreamingEouAsrManager.process(audioBuffer:)`), drop count, p50/p95 over a bounded repeated test, and incremental RSS/CPU on the 16 GB M2 Pro while Zoom and the usual browser are open. End-to-end latency includes capture, chunking, EOU debounce and finalize inference. If live partial updates are a true requirement, evaluate a separate partial-producing recognizer explicitly.
6. Validate overlapping speech, mic echo from speakers, abrupt interruption, silence, mute/unmute, browser helpers, non-English speech and Zoom quit/relaunch. Show uncertainty rather than assigning the wrong speaker.
7. Document Swift toolchain/OS version, exact dependency revisions/licenses and hardware, with a local command to reproduce. Keep any real audio, credentials or private transcripts outside Git/Actions.

Success criterion: reliable permission-controlled mic + selected remote audio, bounded in-memory stream, and a measured ASR transcript path. Do not commit a production architecture ADR or promise latency until the hardware tests demonstrate it. Future PR can then wire the typed transcript events to the existing synthetic turn/QA system. Avoid building a generic recording suite, streaming network server, TTS, emotion detector or complicated diarization by default.

## Parallel-work coordination

Issue #17 owns SQLite Personal Brain schema and provenance. This research owns this isolated document only. It deliberately does not edit AGENTS.md, HANDOFF.md, docs/DECISIONS.md, docs/SLICES.md, QA Python code, or database tests. If both tracks need an interface, prefer narrowly typed event names and a subsequent integration issue after both branches merge; do not import tables into the audio package.

**Research verdict (provisional):** Reuse native Core Audio capture techniques (and selected permissively licensed SystemAudioKit code where it really helps), use FluidAudio streaming EOU for the first ASR spike, compare against WhisperKit, and defer remote diarization until needed. Biggest technical unknown: a real-time, no-disk PCM bridge that works consistently for selected Zoom audio on the target Mac.
