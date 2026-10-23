import Foundation
import RelayAudioBuffer
import RelayNativeSession
import XCTest
@testable import RelaySessionCapture

actor EmptyVad: SpeechActivityDetector {
    nonisolated let chunkSamples = 512
    func accept(_ samples: [Float]) async throws -> [SpeechBoundary] { [] }
}
actor EmptyRecognizer: ActivityRecognizer { func recognize(_ samples: [Float]) async throws -> String { "" } }
actor PrepareGate {
    var continuation: CheckedContinuation<Void, Never>?
    var entered: Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
actor FakeCaptureDriver: SessionCaptureDriver {
    nonisolated let source = PCMSource.microphone
    nonisolated let queue: OwnedPCMQueue
    private(set) var starts = 0
    private(set) var stops = 0
    private var stopContinuation: CheckedContinuation<Void, Never>?
    var holdStop = false
    init() throws { queue = try OwnedPCMQueue(source: .microphone) }
    func start() async throws { starts += 1 }
    func stop() async {
        stops += 1
        if holdStop { await withCheckedContinuation { stopContinuation = $0 } }
    }
    func setHoldStop() { holdStop = true }
    var stopping: Bool { stopContinuation != nil }
    func releaseStop() { holdStop = false; stopContinuation?.resume(); stopContinuation = nil }
    func unavailableReason() async -> SessionReason? { nil }
}
@MainActor final class CaptureLifecycleTests: XCTestCase {
    private var config: NativeCaptureConfiguration {
        NativeCaptureConfiguration(microphoneEnabled: true, selectedBundleID: nil,
            asrModelRoot: URL(fileURLWithPath: "/fixture/asr"), vadCompiledModel: URL(fileURLWithPath: "/fixture/vad.mlmodelc"),
            authorizedConversation: true, localModelLicensesAcknowledged: true)
    }
    private func waitUntil(_ predicate: () async -> Bool) async throws {
        for _ in 0..<1000 { if await predicate() { return }; try await Task.sleep(for: .milliseconds(1)) }
        XCTFail("synthetic lifecycle did not progress")
    }
    func testStopDuringPreparationNeverStartsProducerAndKeepsRestartClosedUntilQuiescence() async throws {
        let gate = PrepareGate(), driver = try FakeCaptureDriver(), authority = SessionPresentationAuthority()
        let session = NativeCaptureSession(authority: authority, onEvent: { _ in },
            prepare: { _ in await gate.wait(); return [1: SourceComponents(vad: EmptyVad(), recognizer: EmptyRecognizer())] },
            makeDrivers: { _ in [driver] }, stopTimeoutMilliseconds: 20)
        let start = Task { try await session.start(configuration: config) }
        try await waitUntil { await gate.entered }
        await session.stop()
        XCTAssertEqual(session.phase, .stopping)
        XCTAssertNil(authority.snapshot())
        await gate.release()
        _ = await start.result
        XCTAssertEqual(session.phase, .idle)
        let starts = await driver.starts
        XCTAssertEqual(starts, 0)
    }
    func testStopClosesAuthorityBeforeSlowProducerAndTimeoutDoesNotReleaseRestart() async throws {
        let driver = try FakeCaptureDriver(), authority = SessionPresentationAuthority()
        await driver.setHoldStop()
        let session = NativeCaptureSession(authority: authority, onEvent: { _ in },
            prepare: { _ in [1: SourceComponents(vad: EmptyVad(), recognizer: EmptyRecognizer())] },
            makeDrivers: { _ in [driver] }, stopTimeoutMilliseconds: 20)
        try await session.start(configuration: config)
        XCTAssertEqual(session.phase, .running)
        let stopping = Task { await session.stop() }
        try await waitUntil { await driver.stopping }
        XCTAssertNil(authority.snapshot())
        await stopping.value
        XCTAssertEqual(session.phase, .stopping)
        do { try await session.start(configuration: config); XCTFail("restart before quiescence") } catch {}
        await driver.releaseStop()
        try await waitUntil { session.phase == .idle }
        let stops = await driver.stops
        XCTAssertEqual(stops, 1)
    }
}

actor TwoChunkVad: SpeechActivityDetector {
    nonisolated let chunkSamples = 512
    var count = 0
    func accept(_ samples: [Float]) async throws -> [SpeechBoundary] {
        count += 1
        return [SpeechBoundary(kind: count == 1 ? .start : .end, sampleIndex: count == 1 ? 0 : 1024)]
    }
}
actor UncancellableCaptureRecognizer: ActivityRecognizer {
    private var continuation: CheckedContinuation<String, Never>?
    var entered: Bool { continuation != nil }
    func recognize(_ samples: [Float]) async throws -> String { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(returning: "synthetic late reply"); continuation = nil }
}
extension CaptureLifecycleTests {
    func testStopTimeoutRetainsModelOwnershipUntilUncancellableCoreMLStandInReturns() async throws {
        let driver = try FakeCaptureDriver(), recognizer = UncancellableCaptureRecognizer()
        let authority = SessionPresentationAuthority()
        let session = NativeCaptureSession(authority: authority, onEvent: { _ in },
            prepare: { _ in [1: SourceComponents(vad: TwoChunkVad(), recognizer: recognizer)] },
            makeDrivers: { _ in [driver] }, stopTimeoutMilliseconds: 20)
        try await session.start(configuration: config)
        let clock = NativeClockCalibration.now()
        let ticks = mach_absolute_time() - UInt64(2_000_000_000 * Double(clock.nsDenom) / Double(clock.nsNumer))
        let samples = Array(repeating: Float(0.1), count: 1024)
        let accepted = samples.withUnsafeBufferPointer {
            driver.queue.enqueueInterleaved(samples: $0.baseAddress!, frames: 1024, channels: 1,
                sampleRate: 16_000, hostTime: ticks, streamGeneration: 1)
        }
        XCTAssertTrue(accepted)
        try await waitUntil { await recognizer.entered }
        await session.stop()
        XCTAssertNil(authority.snapshot())
        XCTAssertEqual(session.phase, .stopping)
        await recognizer.release()
        try await waitUntil { session.phase == .idle }
    }
}

extension CaptureLifecycleTests {
    func testDroppingOwnerClosesAuthorityAndStopsActualDriver() async throws {
        let driver = try FakeCaptureDriver(), authority = SessionPresentationAuthority()
        var session: NativeCaptureSession? = NativeCaptureSession(authority: authority, onEvent: { _ in },
            prepare: { _ in [1: SourceComponents(vad: EmptyVad(), recognizer: EmptyRecognizer())] },
            makeDrivers: { _ in [driver] }, stopTimeoutMilliseconds: 20)
        try await session?.start(configuration: config)
        XCTAssertNotNil(authority.snapshot())
        session = nil
        try await waitUntil { await driver.stops == 1 }
        XCTAssertNil(authority.snapshot())
    }
}

private final class CaptureEventProbe:@unchecked Sendable {
    private let lock=NSLock();private var stored:[NativeSessionEvent]=[]
    func append(_ event:NativeSessionEvent){lock.withLock{stored.append(event)}}
    var events:[NativeSessionEvent]{lock.withLock{stored}}
}
extension CaptureLifecycleTests {
    func testSynchronousRetirementThenRepeatedAsyncStopKeepsOneStopPairAndRealOwnership() async throws {
        let driver=try FakeCaptureDriver();await driver.setHoldStop()
        let authority=SessionPresentationAuthority();let probe=CaptureEventProbe()
        let session=NativeCaptureSession(authority:authority,onEvent:probe.append,
            prepare:{_ in [1:SourceComponents(vad:EmptyVad(),recognizer:EmptyRecognizer())]},makeDrivers:{_ in [driver]},stopTimeoutMilliseconds:20)
        try await session.start(configuration:config)
        session.retireAdmission();session.retireAdmission()
        XCTAssertNil(authority.snapshot());XCTAssertFalse(session.controller.isSourceActive(.microphone))
        await session.stop();await session.stop()
        XCTAssertEqual(session.phase,.stopping)
        XCTAssertEqual(probe.events.filter{$0.kind == .stopping}.count,1)
        XCTAssertEqual(probe.events.filter{$0.kind == .stopped}.count,1)
        XCTAssertEqual(probe.events.last?.payload["quiesced"],.bool(false))
        do {try await session.start(configuration:config);XCTFail("restart before actual producer return")}catch{}
        await driver.releaseStop();try await waitUntil{session.phase == .idle}
        let stops=await driver.stops;XCTAssertEqual(stops,1)
    }
    func testSynchronousRetirementDuringPreparationKeepsStartOwnerUntilReturn() async throws {
        let gate=PrepareGate();let driver=try FakeCaptureDriver();let authority=SessionPresentationAuthority()
        let session=NativeCaptureSession(authority:authority,onEvent:{_ in},prepare:{_ in await gate.wait();return [1:SourceComponents(vad:EmptyVad(),recognizer:EmptyRecognizer())]},makeDrivers:{_ in [driver]},stopTimeoutMilliseconds:20)
        let start=Task{try await session.start(configuration:config)}
        try await waitUntil{await gate.entered}
        session.retireAdmission();session.retireAdmission();await session.stop()
        XCTAssertEqual(session.phase,.stopping);XCTAssertNil(authority.snapshot())
        await gate.release();_ = await start.result
        XCTAssertEqual(session.phase,.idle)
        let starts=await driver.starts;XCTAssertEqual(starts,0)
    }
}
