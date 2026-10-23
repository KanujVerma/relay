# Continuous conversation native session implementation plan

> **For agentic workers:** Execute inline with test-driven-development and verification-before-completion. This worker does not delegate.

**Goal:** Explicit authorized microphone and selected-app capture produces bounded, calibrated session events with real closed-activity audio provenance and immediate native presentation invalidation.

**Architecture:** Independent source pipelines serialize VAD and retain bounded owned PCM. Only a closed VAD activity is submitted to its own local recognizer; all activity samples are consumed before one final is emitted, even when the recognizer signals early EOU. A synchronous native presentation authority invalidates before event callbacks or awaited inference. Source-local generations and session UUIDs fence stale work.

**Tech stack:** Swift 6, existing RelayAudioBuffer/SystemAudioKit/TPCircularBuffer, pinned FluidAudio VAD and Parakeet EOU. No default model acquisition or capture.

**Spec:** `docs/SESSION_BRIDGE.md`; controller-owned shared fixtures freeze exact payload spelling.

## Global constraints

- Preserve exact inner EOU v1 13-key shape and null transcript confidence.
- Source channels identify capture sources, never people.
- No PCM IPC, disk recording, private content logging, implicit capture/model loading or global output fallback.
- Default verification uses synthetic injected VAD/recognizers and no permissions.
- Stop closes admission synchronously; cancellation never flushes an incomplete sentence.
- Keep changes in the assigned native lane and record scoped passing commits.

### Task 1: Native event and synchronous authority contract

Files: `spikes/macos-session/Package.swift`, `Sources/RelayNativeSession/SessionEvent.swift`, `NativeClockCalibration.swift`, `SessionPresentationAuthority.swift`, `Tests/RelayNativeSessionTests/SessionContractTests.swift`.

Interfaces: `SessionPresentationAuthority.snapshot() -> PresentationLease?`, `invalidate() -> PresentationLease?`, `withCurrentLease(_:perform:) -> Bool`; `NativeSessionEvent.encodedFrame() throws -> Data`. Callbacks are synchronous `@Sendable (NativeSessionEvent) throws -> Void`; transport errors retire admission.

- [ ] Write tests proving lease invalidation rejects queued old commits, exact EOU keys remain 13, nonunit clock conversion uses checked arithmetic, and frame bounds reject overflow.
- [ ] Run `swift test --package-path spikes/macos-session --filter SessionContractTests`; confirm missing implementation failure.
- [ ] Implement explicit Codable event types, checked native clock conversion, lock-backed lease ownership.
- [ ] Run contract tests; record passing checkpoint and commit.

### Task 2: Closed activity and independent recognizer pipelines

Files: `Sources/RelayNativeSession/SourcePipeline.swift`, `SessionController.swift`, `Tests/RelayNativeSessionTests/SessionPipelineTests.swift`; public PCMFrame construction seam if required.

Interfaces: `SpeechActivityDetector.accept(_ samples: [Float]) async throws -> [SpeechBoundary]`, `ActivityRecognizer.recognize(_ samples: [Float]) async throws -> String`, `SessionController.ingest(_ frame: PCMFrame)`; one bounded non-realtime drainer per source.

- [ ] Test onset before delayed recognizer, early EOU cannot omit later samples, blank final, overlap, sequence/generation/rate changes, bounded backlog and stop/restart while VAD/ASR await.
- [ ] Run pipeline tests and confirm expected red failures.
- [ ] Implement bounded per-source VAD input and closed-activity recognition with source sequence/sample ranges, cancellation epochs and explicit failure events.
- [ ] Run all synthetic native tests and commit with lane record.

### Task 3: Real adapters, explicit capture executable and integration port

Files: `Sources/RelaySessionCapture/FluidSessionAdapters.swift`, `NativeCaptureSession.swift`, `Sources/RelaySessionCLI/main.swift`, `Packaging/Info.plist`, `scripts/build-session-app.sh`, `THIRD_PARTY_NOTICES.md`, `docs/NATIVE_SESSION.md`.

Interfaces: `NativeCaptureSession.start(configuration:onEvent:) async throws`; configuration requires explicit mic/selected app choice and local ASR/VAD paths. Stop uses existing producers' quiescent shutdown before queue release. Panel can depend on the library and use its synchronous authority at MainActor state commit.

- [ ] Inspect exact pinned upstream VAD/ASR APIs, source and tests; preserve license and provenance.
- [ ] Test configuration rejects default/no-source start and missing local models without capture; verify real adapters compile.
- [ ] Implement local-only model load adapters, independent streams, two owned capture queues, fixed-status source monitoring and explicit Start/Stop executable.
- [ ] Run fake tests, build executable, verify no-argument launch prints safe help without capture/model load, document real hardware/model acceptance still pending.
- [ ] Push verified branch slices and request controller foundation base before draft PR.
