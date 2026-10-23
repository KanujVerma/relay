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
