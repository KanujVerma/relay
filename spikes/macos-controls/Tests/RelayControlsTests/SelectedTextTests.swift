import Foundation
import Testing
@testable import RelayControls

@MainActor @Suite struct SelectedTextTests {
    @Test func enableIsExplicitAndUntrustedOrUnapprovedAppNeverReads() async throws {
        let environment = SelectionEnvironment()
        #expect(environment.provider.prompts == 0)
        await #expect(throws: SelectionError.disabled) { try await environment.service.read(request: environment.request) }
        try environment.service.enable(allowedBundleIDs: ["com.example.Editor"], requestPermission: false)
        environment.provider.trusted = false
        await #expect(throws: SelectionError.permissionRequired) { try await environment.service.read(request: environment.request) }
        environment.provider.trusted = true
        environment.app = .init(bundleID: "com.example.Other", processID: 10, launchDate: .distantPast)
        await #expect(throws: SelectionError.applicationNotAllowed) { try await environment.service.read(request: environment.request) }
        #expect(environment.provider.reads == 0)
        environment.service.revoke()
        try environment.service.enable(allowedBundleIDs: ["com.example.Editor"], requestPermission: true)
        #expect(environment.provider.prompts == 1)
    }

    @Test func selectedTextRetainsOriginalNativeIdentityAndCannotSurviveRequestChange() async throws {
        let environment = SelectionEnvironment()
        try environment.enable()
        let snapshot = try await environment.service.read(request: environment.request)
        #expect(snapshot.text == "SELECT count(*) FROM orders;\n")
        #expect(snapshot.provenance == "selected_accessibility_text")
        #expect(snapshot.request == environment.request)
        #expect(snapshot.application.processID == 9)
        #expect(environment.service.validateCurrent(snapshot))
        environment.request = .init(sessionID: UUID(), sessionEpoch: 2, presentationGeneration: 3, requestID: UUID())
        #expect(!environment.service.validateCurrent(snapshot))
    }

    @Test func secureUnsupportedEmptyAndOversizedSelectionsAreRejected() async throws {
        let environment = SelectionEnvironment()
        try environment.enable()
        environment.provider.observation = .init(application: environment.app!, role: "AXTextField", subrole: "AXSecureTextField", text: "private")
        await #expect(throws: SelectionError.secureField) { try await environment.service.read(request: environment.request) }
        environment.provider.observation = .init(application: environment.app!, role: "AXWebArea", subrole: nil, text: "page")
        await #expect(throws: SelectionError.unsupportedSelection) { try await environment.service.read(request: environment.request) }
        environment.provider.observation = .init(application: environment.app!, role: "AXTextArea", subrole: nil, text: "  \n")
        await #expect(throws: SelectionError.emptySelection) { try await environment.service.read(request: environment.request) }
        environment.provider.observation = .init(application: environment.app!, role: "AXTextArea", subrole: nil, text: String(repeating: "é", count: 4097))
        await #expect(throws: SelectionError.tooLarge) { try await environment.service.read(request: environment.request) }
    }

    @Test func focusTrustConsentAndRequestChangesDuringReadInvalidateResult() async throws {
        for change in 0..<4 {
            let environment = SelectionEnvironment()
            try environment.enable()
            environment.provider.duringRead = {
                switch change {
                case 0: environment.app = .init(bundleID: "com.example.Other", processID: 10, launchDate: .distantPast)
                case 1: environment.provider.trusted = false
                case 2: environment.service.revoke()
                default: environment.request = .init(sessionID: UUID(), sessionEpoch: 2, presentationGeneration: 3, requestID: UUID())
                }
            }
            await #expect(throws: SelectionError.stale) { try await environment.service.read(request: environment.request) }
        }
    }

    @Test func wrongPIDTimeoutAndExpiredSnapshotCannotPublish() async throws {
        let environment = SelectionEnvironment()
        try environment.enable()
        environment.provider.observation = .init(application: .init(bundleID: "com.example.Editor", processID: 99, launchDate: .distantPast), role: "AXTextArea", subrole: nil, text: "wrong process")
        await #expect(throws: SelectionError.stale) { try await environment.service.read(request: environment.request) }
        environment.provider.observation = nil
        environment.provider.duringRead = { environment.uptime += 800_000_000 }
        await #expect(throws: SelectionError.timedOut) { try await environment.service.read(request: environment.request) }
        environment.provider.duringRead = nil
        let snapshot = try await environment.service.read(request: environment.request)
        environment.uptime += 5_000_000_001
        #expect(!environment.service.validateCurrent(snapshot))
    }

    @Test func invalidateAndNewReadRetirePreviouslyIssuedSelection() async throws {
        let environment = SelectionEnvironment()
        try environment.enable()
        let first = try await environment.service.read(request: environment.request)
        let second = try await environment.service.read(request: environment.request)
        #expect(!environment.service.validateCurrent(first))
        #expect(environment.service.validateCurrent(second))
        environment.service.invalidate()
        #expect(!environment.service.validateCurrent(second))
    }

    @Test func concurrentReadsCannotReplaceTheOriginalInFlightRequest() async throws {
        let environment = SelectionEnvironment()
        try environment.enable()
        environment.provider.waitForRelease = true
        let first = Task { try await environment.service.read(request: environment.request) }
        await environment.provider.waitUntilStarted()
        await #expect(throws: SelectionError.busy) { try await environment.service.read(request: environment.request) }
        environment.service.invalidate()
        environment.provider.release?()
        await #expect(throws: SelectionError.stale) { try await first.value }
        #expect(environment.provider.cancelled)
        #expect(!environment.service.isReading)
    }

    @Test func observedTrustLossPermanentlyRetiresAnIssuedSnapshot() async throws {
        let environment = SelectionEnvironment()
        try environment.enable()
        let snapshot = try await environment.service.read(request: environment.request)
        environment.provider.trusted = false
        #expect(!environment.service.validateCurrent(snapshot))
        environment.provider.trusted = true
        #expect(!environment.service.validateCurrent(snapshot))
    }
}

@MainActor final class SelectionEnvironment {
    var app: ApplicationIdentity? = .init(bundleID: "com.example.Editor", processID: 9, launchDate: .distantPast)
    var request = SelectionRequestIdentity(sessionID: UUID(), sessionEpoch: 2, presentationGeneration: 3, requestID: UUID())
    var uptime: UInt64 = 1_000_000_000
    let provider = FakeSelectionProvider()
    lazy var service = SelectedTextService(provider: provider, frontmostApplication: { self.app }, currentRequest: { self.request }, uptimeNanoseconds: { self.uptime })
    func enable() throws { try service.enable(allowedBundleIDs: ["com.example.Editor"], requestPermission: false) }
}

@MainActor final class FakeSelectionProvider: SelectedTextProviding {
    var trusted = true
    var prompts = 0
    var reads = 0
    var observation: SelectedTextObservation?
    var duringRead: (@MainActor () -> Void)?
    var waitForRelease = false
    var release: (() -> Void)?
    var cancelled = false
    private var startedWaiter: CheckedContinuation<Void, Never>?
    func waitUntilStarted() async {
        if reads > 0 { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }
    func isTrusted(prompt: Bool) -> Bool { if prompt { prompts += 1 }; return trusted }
    func selectedText(from application: ApplicationIdentity) async throws -> SelectedTextObservation {
        reads += 1
        startedWaiter?.resume()
        startedWaiter = nil
        if waitForRelease {
            await withCheckedContinuation { continuation in release = { continuation.resume() } }
        }
        cancelled = Task.isCancelled
        duringRead?()
        return observation ?? .init(application: application, role: "AXTextArea", subrole: nil, text: "SELECT count(*) FROM orders;\n")
    }
}
