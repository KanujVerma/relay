# Native continuous conversation session

Issue #60. Implemented in `spikes/macos-session`; the accepted shared protocol remains [BUILD_CONTRACT](BUILD_CONTRACT.md). This package provides real capture and local model adapters plus synthetic tests. No hardware/model recognition quality or latency is established by those tests.

## Public integration port

The ordinary panel depends on products `RelayNativeSession` and `RelaySessionCapture` and passes the **same** `SessionPresentationAuthority` to its paint gate and `NativeCaptureSession`.

```swift
let authority = SessionPresentationAuthority()
let capture = NativeCaptureSession(authority: authority, onEvent: { event in
    try boundedHelperTransport.enqueue(event.encodedFrame())
})
try await capture.start(configuration: NativeCaptureConfiguration(
    microphoneEnabled: true, selectedBundleID: selectedBundleID,
    asrModelRoot: localASRRoot, vadCompiledModel: localVADCompiledModel,
    authorizedConversation: userConfirmedAuthorizedConversation,
    localModelLicensesAcknowledged: userAcknowledgedLocalModelLicenses
))
// Stop / pause / consent withdrawal closes authority before its first await.
await capture.stop(reason: .userStop)
```

The callback is synchronous, ordered globally across sources and throwing. It must enqueue bounded work and return promptly, never wait for Python or a pipe. A thrown error retires admission. The panel owns helper lifetime and checks `authority.withCurrentLease(event.lease) { /* actual MainActor state commit */ }`. Native-observed remote onset invalidates that same authority before callback delivery. Mic onset/finals update context while remote talking points remain visible. Source channels never identify people.

`capture.phase` is idle/preparing/starting/running/stopping. Default construction starts nothing. Start validates explicit source selection, authorization acknowledgement and local artifact paths before model/device operations. Stop cancels the input/VAD/recognizer tasks, stops both real producers, and joins the SPSC consumer and actual model ownership. An in-flight CoreML call may ignore cancellation until it returns. The two-second UI wait is a deadline, not quiescence: `stopped.quiesced=false` leaves phase stopping and restart closed until the retained shutdown task actually finishes. Dropping the owner also retires authority and schedules real teardown while retaining resources. Pause is Stop; Resume is a fresh explicit Start with a new UUID and new source/model state.

The lower-level controller exposes `beginStop`, `waitForQuiescence`, and `finishStop(quiesced:)` for owned lifecycle composition. Its convenience synchronous `stop` cannot attest quiescence and emits false. Reusing that controller requires joining `waitForQuiescence` first. The capture wrapper performs this sequence.

## Actual audio and provenance path

Each selected source has its own owned `TPCircularBuffer` ring, converter, FluidAudio VAD state and Parakeet EOU recognizer. Mic and selected-app PCM are never mixed. A single non-realtime ring consumer detaches/normalizes samples and dispatches to independent bounded source drainers. Slow ASR does not sit in front of VAD onset observation. No PCM crosses a helper pipe, no audio files are written and no global output tap is created.

The real adapter calls the pinned `VadManager.processStreamingChunk` API with integer sample indices and a fresh stream state per source. It loads an explicitly supplied compiled model with `MLModel(contentsOf:)` and the provided-model VadManager initializer. It deliberately avoids VadManager's default/directory initializers, which may download through ModelHub.

A VAD activity records its start, end and source input sequences. Only after closure is its complete retained sample interval submitted to that source's recognizer. The real ASR adapter calls existing `FluidEouRecognizer.accept` for **every** sample chunk, ignores early EOU hints, then calls finish once and resets under the same single-flight owner. Pinned upstream process() continues encoding after an EOU hint; an early hint cannot omit later same-activity constraints here. This is a conservative first integration with additional closure and recognition delay, not a first-word latency claim.

The final allocates an independent ASR segment identity and explicitly associates it with the closed VAD activity and actual consumed sequence range. It does not match two counters or infer association from callback arrival. Blank recognized text is an explicit final. Missing ASR confidence serializes null; VAD probability is not transcript confidence. Valid late closed finals preserve their original presentation lease for host context-only handling. Source-invalid or stopped-session results are discarded.

Timebase calibration uses mach host ticks and Dispatch monotonic uptime, including checked full-width integer arithmetic and signed offset floor division matching Python. Inner EOU retains exactly 13 keys. Outer counters remain lossless UInt64 and fields include requestID only on remote EOU. Endpoints describe the actual retained normalized sample interval and its source packet provenance, not word alignment or biometric identity.

## Bounded initial policies and recovery

- Each capture ring is 1 MiB, with packets limited by the existing 2048-frame bridge. One producer and consumer per ring.
- Each VAD input queue is at most 16,000 normalized samples (one second), 64 packets, plus one bounded in-flight packet. There is one drainer task per source, never a task per callback.
- Idle VAD retains at most 8192 samples of lookback. A start older than retained provenance fails closed.
- Each continuous activity is at most 1,920,000 samples, 120 seconds at 16 kHz, matching the existing EOU wire maximum. The sample payload is at most 7.68 MB per retained activity/source, with a separate owned recognition interval while the next activity is observed. The closure packet cannot bypass the cap. Session duration itself has no timer cap.
- One recognition operation per source. If another activity closes while that recognizer is still occupied, explicit `asr_unavailable` retires the source; no unbounded recognition backlog is queued.
- Text remains bounded by existing inner wire rules (1200 characters); the panel's semantic question bound is a separate 500 UTF-8 bytes. Overflow withholds, never truncates a question or fabricates text.
- Frame maximum is 16 KiB. Writer caps include its in-flight frame: 32 frames and 256 KiB total. A blocked single write has a 500 ms deadline. Overflow, closed reader/SIGPIPE, or deadline retires the writer and native authority; controls cannot be silently dropped.

A sequence gap, rate/generation change, invalid clock, overlong activity, VAD/ASR failure or selected-app loss produces a fixed source control and ends the live capture session. Silence alone does not assert a permission failure. The initial recovery is explicit Stop/Start after quiescence, using fresh rings/models/session identity, with no global fallback. A reply exceeding the activity/text cap is lost as an answer candidate, visibly withheld, and cannot be described as captured whole-conversation history. Continuous long-speech recognition, segmented-context stitching and faster bounded recovery remain follow-up performance work.

## Standalone command and bundle

`spikes/macos-session/scripts/build-session-app.sh` builds and ad-hoc signs a local command bundle with continuous-session purpose strings. It does not start capture, request permissions, download/load models or run inference. `RELAY_SWIFT_SCRATCH_PATH` optionally selects a build cache. The final ordinary panel bundle belongs to the answers lane.

Default executable launch and `--help` are inert. Actual capture requires all of:

```text
--start --authorized-conversation --acknowledge-local-model-licenses
--mic and/or --selected-app com.example.meeting
--asr-model-root /local/model-root
--vad-model /local/silero_vad.mlmodelc --event-fd 3
```

The ASR root must contain `parakeet-eou-streaming/320ms/{streaming_encoder.mlmodelc,decoder.mlmodelc,joint_decision.mlmodelc,vocab.json}`. The VAD path is an existing compiled model directory. There is no downloader in this package. SDK license and weight licenses are separate; see `spikes/macos-session/THIRD_PARTY_NOTICES.md`. Artifact rights, staging and actual model use remain explicit owner gates. No model artifact is committed.

Supply a dedicated inherited writable pipe descriptor >=3. It carries four-byte big-endian length-prefixed events. Stdout is not the protocol. Return/EOF or Ctrl-C requests actual capture stop; diagnostics are fixed reason strings without paths, audio or text. This CLI emits events only. Automatic answer generation and the visible ordinary window are composed by the answer lane.

## Verification and remaining acceptance

Default tests inject fake VAD/recognizers/drivers and use real local pipes. They cover whole closed-activity consumption despite early EOU, long replies and cap failure, mic/remote overlap without mixing, blank finals, native clock conversion, source changes, queue overflow, single blocked writes/EOF, stop during preparation, slow producer/model shutdown, owner drop, cancellation, late results, strict framing and fresh restart.

The overlap test can export **synthetic** native frames when `RELAY_SYNTHETIC_EVENTS_PATH` is set. Those generated frames have been decoded by the answer lane's actual strict Python decoder and session host: both sources entered bounded dialogue, only remote EOU minted a request, no model request ran in the no-inference mode, and Stop closed host state.

Still unmeasured: target M2 Pro permissions/denial/device switching, real spoken-word recognition, VAD boundaries, both-source echo, speech-start-to-clear draw delay, closed-activity-to-final and useful-answer p50/p95 latency, CPU/RSS, long-activity recognition cost and model artifact byte provenance. Separate model instances are used because the pinned ASR manager does not expose an established safe immutable-model sharing constructor. No memory, latency, Zoom reliability or model quality claim is inferred from compilation or fake tests.
