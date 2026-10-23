import Foundation
import RelayLocalASR
import XCTest
@testable import RelaySessionCapture

actor HintRecognizer: LocalEouRecognizer {
    private(set) var received: [Float] = []
    private(set) var finishes = 0
    private(set) var resets = 0
    func accept(_ samples: [Float]) async throws -> Bool { received.append(contentsOf: samples); return true }
    func finish() async throws -> String { finishes += 1; return "complete constraint" }
    func reset() async { resets += 1 }
}
final class FluidAdapterTests: XCTestCase {
    func testEarlyEOUHintDoesNotDropLaterActivitySamples() async throws {
        let backend = HintRecognizer()
        let adapter = FluidClosedActivityRecognizer(backend: backend)
        var audio = Array(repeating: Float(1), count: 5120)
        audio.append(contentsOf: Array(repeating: Float(2), count: 5120))
        let result = try await adapter.recognize(audio)
        XCTAssertEqual(result, "complete constraint")
        let received = await backend.received
        let finishes = await backend.finishes
        XCTAssertEqual(received, audio)
        XCTAssertEqual(finishes, 1)
    }
    func testMissingLocalModelAndNoConsentFailBeforeCapture() async throws {
        let configuration = NativeCaptureConfiguration(microphoneEnabled: false, selectedBundleID: nil,
            asrModelRoot: URL(fileURLWithPath: "/nonexistent/relay-asr"),
            vadCompiledModel: URL(fileURLWithPath: "/nonexistent/relay-vad.mlmodelc"),
            authorizedConversation: false, localModelLicensesAcknowledged: false)
        XCTAssertThrowsError(try configuration.validate())
        let selected = NativeCaptureConfiguration(microphoneEnabled: true, selectedBundleID: nil,
            asrModelRoot: configuration.asrModelRoot, vadCompiledModel: configuration.vadCompiledModel,
            authorizedConversation: true, localModelLicensesAcknowledged: true)
        XCTAssertThrowsError(try selected.validateLocalModels())
    }
}
