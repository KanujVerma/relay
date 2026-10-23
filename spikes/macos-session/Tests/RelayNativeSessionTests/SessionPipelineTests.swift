import Dispatch
import Foundation
import RelayAudioBuffer
import XCTest
@testable import RelayNativeSession

final class EventProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [NativeSessionEvent] = []
    func append(_ event: NativeSessionEvent) { lock.withLock { stored.append(event) } }
    var events: [NativeSessionEvent] { lock.withLock { stored } }
}
actor ScriptVad: SpeechActivityDetector {
    nonisolated let chunkSamples = 512
    let events: [Int: SpeechBoundary.Kind]
    var count = 0
    init(_ events: [Int: SpeechBoundary.Kind]) { self.events = events }
    func accept(_ samples: [Float]) async throws -> [SpeechBoundary] {
        count += 1
        guard let kind = events[count] else { return [] }
        return [SpeechBoundary(kind: kind, sampleIndex: UInt64(kind == .start ? (count - 1) * 512 : count * 512))]
    }
}
actor RecordingRecognizer: ActivityRecognizer {
    private(set) var inputs: [[Float]] = []
    let text: String
    init(_ text: String = "explain joins including null values") { self.text = text }
    func recognize(_ samples: [Float]) async throws -> String { inputs.append(samples); return text }
}
actor HeldRecognizer: ActivityRecognizer {
    private var pending: CheckedContinuation<String, Never>?
    func recognize(_ samples: [Float]) async throws -> String {
        await withCheckedContinuation { pending = $0 }
    }
    var entered: Bool { pending != nil }
    func release() { pending?.resume(returning: "old answer"); pending = nil }
}

@MainActor final class SessionPipelineTests: XCTestCase {
    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<1000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("synthetic operation did not complete")
    }
    private func pastHostTicks() -> UInt64 {
        let clock = NativeClockCalibration.now()
        return mach_absolute_time() - UInt64(2_000_000_000 * Double(clock.nsDenom) / Double(clock.nsNumer))
    }
    private func packet(_ source: PCMSource = .remoteAudio, sequence: UInt64, generation: UInt64 = 1,
                        value: Float = 0.2, count: Int = 512) -> SessionAudioPacket {
        SessionAudioPacket(source: source, streamGeneration: generation, sequence: sequence,
            hostTime: pastHostTicks(), samples: Array(repeating: value, count: count))
    }
    func testClosedActivityConsumesLaterSameActivityConstraintsAndExactEOU() async throws {
        let probe = EventProbe(), recognizer = RecordingRecognizer()
        let controller = NativeSessionController(onEvent: probe.append)
        try controller.start(selectedBundleID: "com.example.meeting", microphoneEnabled: false,
            components: [2: SourceComponents(vad: ScriptVad([1: .start, 3: .end]), recognizer: recognizer)])
        controller.ingest(packet(sequence: 1, value: 1))
        controller.ingest(packet(sequence: 2, value: 2))
        controller.ingest(packet(sequence: 3, value: 3))
        try await waitUntil { probe.events.contains { $0.kind == .eou } }
        let inputs = await recognizer.inputs
        XCTAssertEqual(inputs.first?.count, 1536)
        XCTAssertEqual(inputs.first?.last, 3)
        let final = try XCTUnwrap(probe.events.first { $0.kind == .eou })
        XCTAssertNotNil(final.requestID)
        XCTAssertEqual(final.payload["activityClosed"], .bool(true))
        XCTAssertEqual(final.payload["lastSpeechInputSequence"], .uint(3))
        guard case .object(let inner) = final.payload["event"] else { return XCTFail("missing EOU") }
        XCTAssertEqual(inner.count, 13)
        XCTAssertEqual(inner["confidence"], .null)
        XCTAssertEqual(probe.events.map(\.kind), [.sessionStarted, .speechStarted, .speechEnded, .eou])
        controller.stop()
    }
    func testMicSpeechKeepsRemoteLeaseAndDoesNotMintRequest() async throws {
        let probe = EventProbe()
        let controller = NativeSessionController(onEvent: probe.append)
        try controller.start(selectedBundleID: nil, microphoneEnabled: true,
            components: [1: SourceComponents(vad: ScriptVad([1: .start, 2: .end]), recognizer: RecordingRecognizer())])
        let lease = try XCTUnwrap(controller.authority.snapshot())
        controller.ingest(packet(.microphone, sequence: 1))
        controller.ingest(packet(.microphone, sequence: 2))
        try await waitUntil { probe.events.contains { $0.kind == .eou } }
        XCTAssertEqual(controller.authority.snapshot(), lease)
        XCTAssertNil(probe.events.first { $0.kind == .eou }?.requestID)
        controller.stop()
    }
    func testRemoteOnsetInvalidatesBeforeBlockedASRAndStopSuppressesLateFinal() async throws {
        let probe = EventProbe(), recognizer = HeldRecognizer()
        let controller = NativeSessionController(onEvent: probe.append)
        try controller.start(selectedBundleID: "com.example.meeting", microphoneEnabled: false,
            components: [2: SourceComponents(vad: ScriptVad([1: .start, 2: .end, 3: .start]), recognizer: recognizer)])
        let old = try XCTUnwrap(controller.authority.snapshot())
        controller.ingest(packet(sequence: 1)); controller.ingest(packet(sequence: 2))
        try await waitUntil { await recognizer.entered }
        XCTAssertFalse(controller.authority.withCurrentLease(old) { XCTFail("stale paint") })
        let firstActivityLease = try XCTUnwrap(controller.authority.snapshot())
        controller.ingest(packet(sequence: 3))
        try await waitUntil { probe.events.filter { $0.kind == .speechStarted }.count == 2 }
        XCTAssertNotEqual(controller.authority.snapshot(), firstActivityLease)
        controller.stop()
        await recognizer.release()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(probe.events.contains { $0.kind == .eou })
        XCTAssertEqual(probe.events.suffix(2).map(\.kind), [.stopping, .stopped])
    }
    func testSequenceGapInvalidatesBeforeNewAudioAndBlankFinalIsExplicit() async throws {
        let probe = EventProbe()
        let controller = NativeSessionController(onEvent: probe.append)
        try controller.start(selectedBundleID: "com.example.meeting", microphoneEnabled: false,
            components: [2: SourceComponents(vad: ScriptVad([1: .start, 2: .end]), recognizer: RecordingRecognizer(""))])
        controller.ingest(packet(sequence: 1)); controller.ingest(packet(sequence: 3))
        try await waitUntil { probe.events.contains { $0.kind == .discontinuity } }
        XCTAssertFalse(probe.events.contains { $0.kind == .eou })
        controller.stop()
        let second = NativeSessionController(onEvent: probe.append)
        try second.start(selectedBundleID: "com.example.meeting", microphoneEnabled: false,
            components: [2: SourceComponents(vad: ScriptVad([1: .start, 2: .end]), recognizer: RecordingRecognizer(""))])
        second.ingest(packet(sequence: 1)); second.ingest(packet(sequence: 2))
        try await waitUntil { probe.events.contains { $0.kind == .eou } }
        let event = try XCTUnwrap(probe.events.first { $0.kind == .eou })
        guard case .object(let inner) = event.payload["event"] else { return XCTFail("missing EOU") }
        XCTAssertEqual(inner["text"], .string(""))
        second.stop()
    }
}

actor HeldVad: SpeechActivityDetector {
    nonisolated let chunkSamples = 512
    private var continuation: CheckedContinuation<[SpeechBoundary], Never>?
    private(set) var calls = 0
    func accept(_ samples: [Float]) async throws -> [SpeechBoundary] {
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    var entered: Bool { continuation != nil }
    func release() { continuation?.resume(returning: [SpeechBoundary(kind: .start, sampleIndex: 0)]); continuation = nil }
}
extension SessionPipelineTests {
    func testBoundedVADBacklogInvalidatesSynchronouslyAndNeverOverlapsModelState() async throws {
        let probe = EventProbe(), vad = HeldVad()
        let controller = NativeSessionController(onEvent: probe.append)
        try controller.start(selectedBundleID: "com.example.meeting", microphoneEnabled: false,
            components: [2: SourceComponents(vad: vad, recognizer: RecordingRecognizer())])
        let initial = try XCTUnwrap(controller.authority.snapshot())
        controller.ingest(packet(sequence: 1))
        try await waitUntil { await vad.entered }
        controller.ingest(packet(sequence: 2, count: 8192))
        controller.ingest(packet(sequence: 3, count: 8192))
        controller.ingest(packet(sequence: 4, count: 512))
        XCTAssertNotEqual(controller.authority.snapshot(), initial)
        XCTAssertEqual(probe.events.last?.kind, .discontinuity)
        XCTAssertEqual(probe.events.last?.payload["reasonCode"], .string("queue_overflow"))
        let calls = await vad.calls
        XCTAssertEqual(calls, 1)
        controller.stop(); await vad.release()
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertFalse(probe.events.contains { $0.kind == .speechStarted })
    }
    func testFreshRestartRejectsOldDetectorCompletionAndSourceGenerationChange() async throws {
        let probe = EventProbe(), vad = HeldVad()
        let controller = NativeSessionController(onEvent: probe.append)
        try controller.start(selectedBundleID: "com.example.meeting", microphoneEnabled: false,
            components: [2: SourceComponents(vad: vad, recognizer: RecordingRecognizer())])
        let oldID = controller.authority.snapshot()?.captureSessionID
        controller.ingest(packet(sequence: 1)); try await waitUntil { await vad.entered }
        controller.stop()
        XCTAssertThrowsError(try controller.start(selectedBundleID: "com.example.meeting", microphoneEnabled: false,
            components: [2: SourceComponents(vad: ScriptVad([:]), recognizer: RecordingRecognizer())]))
        await vad.release()
        await controller.waitForQuiescence()
        try controller.start(selectedBundleID: "com.example.meeting", microphoneEnabled: false,
            components: [2: SourceComponents(vad: ScriptVad([1: .start, 2: .end]), recognizer: RecordingRecognizer())])
        XCTAssertNotEqual(controller.authority.snapshot()?.captureSessionID, oldID)
        controller.ingest(packet(sequence: 1)); controller.ingest(packet(sequence: 2, generation: 2))
        XCTAssertEqual(probe.events.last?.payload["reasonCode"], .string("device_changed"))
        controller.stop()
    }
    func testThrowingSinkRetiresAuthorityWithoutAwaitingHelper() throws {
        let controller = NativeSessionController(onEvent: { _ in throw NativeSessionError.transportClosed })
        XCTAssertThrowsError(try controller.start(selectedBundleID: "com.example.meeting", microphoneEnabled: false,
            components: [2: SourceComponents(vad: ScriptVad([:]), recognizer: RecordingRecognizer())]))
        XCTAssertNil(controller.authority.snapshot())
    }
}

actor CancelAwareRecognizer: ActivityRecognizer {
    let probe: FailureProbe
    private(set) var entered = false
    init(probe: FailureProbe) { self.probe = probe }
    func recognize(_ samples: [Float]) async throws -> String {
        entered = true
        return try await withTaskCancellationHandler(operation: {
            try await Task.sleep(for: .seconds(30)); return "must not finish after stop"
        }, onCancel: { self.probe.fail() })
    }
}
extension SessionPipelineTests {
    func testStopCancelsOwnedRecognizerTaskRatherThanOnlyHidingItsResult() async throws {
        let cancellation = FailureProbe(), probe = EventProbe()
        let recognizer = CancelAwareRecognizer(probe: cancellation)
        let controller = NativeSessionController(onEvent: probe.append)
        try controller.start(selectedBundleID: "com.example.meeting", microphoneEnabled: false,
            components: [2: SourceComponents(vad: ScriptVad([1: .start, 2: .end]), recognizer: recognizer)])
        controller.ingest(packet(sequence: 1)); controller.ingest(packet(sequence: 2))
        try await waitUntil { await recognizer.entered }
        controller.stop()
        for _ in 0..<100 { if cancellation.failed { break }; try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(cancellation.failed, "Stop must cancel the actual recognition task")
        XCTAssertFalse(probe.events.contains { $0.kind == .eou })
    }
}

actor WideVad: SpeechActivityDetector {
    nonisolated let chunkSamples = 8192
    private(set) var count = 0
    func accept(_ samples: [Float]) async throws -> [SpeechBoundary] {
        count += 1
        if count == 1 { return [SpeechBoundary(kind: .start, sampleIndex: 0)] }
        if count == 235 { return [SpeechBoundary(kind: .end, sampleIndex: UInt64(count * chunkSamples))] }
        return []
    }
}
extension SessionPipelineTests {
    func testClosureCrossingActivityLimitCannotBypassCap() async throws {
        let probe = EventProbe(), vad = WideVad(), recognizer = RecordingRecognizer()
        let controller = NativeSessionController(onEvent: probe.append)
        try controller.start(selectedBundleID: "com.example.meeting", microphoneEnabled: false,
            components: [2: SourceComponents(vad: vad, recognizer: recognizer)])
        for i in 1...235 {
            controller.ingest(packet(sequence: UInt64(i), count: 8192))
            try await waitUntil { await vad.count >= i }
        }
        try await waitUntil { probe.events.contains { $0.kind == .eou || $0.kind == .discontinuity } }
        XCTAssertFalse(probe.events.contains { $0.kind == .eou })
        XCTAssertEqual(probe.events.last?.payload["reasonCode"], .string("queue_overflow"))
        let inputs = await recognizer.inputs
        XCTAssertTrue(inputs.isEmpty)
        controller.stop()
    }
}

extension SessionPipelineTests {
    func testBothSourcesOverlapWithoutMixingAndExportNativeSessionFrames() async throws {
        let probe = EventProbe(), remote = RecordingRecognizer("explain a dictionary lookup including collisions")
        let microphone = RecordingRecognizer("I would first clarify how collisions are handled")
        let controller = NativeSessionController(onEvent: probe.append)
        try controller.start(selectedBundleID: "com.example.meeting", microphoneEnabled: true, components: [
            2: SourceComponents(vad: ScriptVad([1: .start, 2: .end]), recognizer: remote),
            1: SourceComponents(vad: ScriptVad([1: .start, 2: .end]), recognizer: microphone)])
        controller.ingest(packet(sequence: 1, value: 1))
        try await waitUntil { probe.events.contains { $0.kind == .speechStarted && $0.sourceCode == 2 } }
        let lease = controller.authority.snapshot()
        controller.ingest(packet(.microphone, sequence: 1, value: 2))
        controller.ingest(packet(sequence: 2, value: 1))
        controller.ingest(packet(.microphone, sequence: 2, value: 2))
        try await waitUntil { probe.events.filter { $0.kind == .eou }.count == 2 }
        XCTAssertEqual(controller.authority.snapshot(), lease)
        let remoteSamples = await remote.inputs.first, micSamples = await microphone.inputs.first
        XCTAssertTrue(remoteSamples?.allSatisfy { $0 == 1 } ?? false)
        XCTAssertTrue(micSamples?.allSatisfy { $0 == 2 } ?? false)
        controller.stop()
        let events = probe.events
        XCTAssertEqual(events.map(\.eventSequence), Array(1...UInt64(events.count)))
        XCTAssertEqual(events.filter { $0.requestID != nil }.count, 1)
        if let path = ProcessInfo.processInfo.environment["RELAY_SYNTHETIC_EVENTS_PATH"] {
            var data = Data()
            for event in events { data.append(try event.encodedFrame()) }
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
}

extension SessionPipelineTests {
    func testTransportAuthorityWithdrawalStillCancelsModelOwners() async throws {
        let cancellation = FailureProbe()
        let owned = CancelAwareRecognizer(probe: cancellation)
        let controller = NativeSessionController(onEvent: { _ in })
        try controller.start(selectedBundleID: "com.example.meeting", microphoneEnabled: false,
            components: [2: SourceComponents(vad: ScriptVad([1: .start, 2: .end]), recognizer: owned)])
        controller.ingest(packet(sequence: 1)); controller.ingest(packet(sequence: 2))
        try await waitUntil { await owned.entered }
        controller.authority.stop()
        controller.stop(reason: .transportClosed)
        await controller.waitForQuiescence()
        XCTAssertTrue(cancellation.failed)
    }
}
