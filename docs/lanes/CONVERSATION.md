# Conversation lane

Issue: #60. Branch: feature/conversation-runtime-2026-10-23.

Base: 3e0eb379fdc8a710dd9ebee51bc93b8c6004e02d. Implementation underway. No capture, permission prompt, model load/download or inference has run.

Next action: compile fake-driven native event/authority tests, then closed-activity source pipeline. Plan: ../superpowers/plans/2026-10-23-continuous-conversation.md.

Checkpoint 1: implemented native lossless envelope/framing, real host-clock calibration and synchronous presentation lease guard. `swift test --package-path spikes/macos-session --scratch-path /private/tmp/relay-session-build --filter SessionContractTests` passed 3 tests. Compiler/package-cache escalation was used; no model/device access. Frozen contract now includes outer requestID and speech_ended; mic events retain the current remote presentation lease. Next: source activity pipeline and provenance tests.

Checkpoint 2: native source pipelines implemented with separate VAD/recognizer ownership, one-second queued VAD cap, 20-second activity cap, explicit closed-range provenance and an independent ASR segment counter. Remote onset invalidates synchronously; mic replies preserve talking points. Late valid finals retain the original activity lease for context-only host admission. Source gaps/rate/generation changes retire that source until a fresh explicit session. Stop suppresses all late VAD/ASR. Ten synthetic Swift tests passed in `/private/tmp/relay-session-checkpoint2.log`; no hardware/model access. Fractional negative clock offset was reproduced red and corrected to match Python floor division. Next: bounded dedicated-pipe writer, actual local FluidAudio adapters and capture executable.
