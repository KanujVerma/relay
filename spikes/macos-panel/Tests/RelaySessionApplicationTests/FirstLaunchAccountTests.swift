import Foundation
import XCTest
import RelayAccount
import RelayProfile
@testable import RelayPanelSession

@MainActor private final class SetupPlanPreferences: ChatGPTPlanPreferences { var enabled = false }
@MainActor private final class SetupContextPreferences: SessionContextUsePreferences { var useInSessions = false }
private final class SetupKey: ProfileKeyProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func key(createIfMissing: Bool) throws -> Data { lock.withLock { count += 1 }; return Data(repeating: 74, count: 32) }
}
@MainActor private final class SetupEffects { var accounts = 0, browsers = 0, helpers = 0 }

@MainActor final class FirstLaunchAccountTests: XCTestCase {
    private var root: URL {
        var path = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { path.deleteLastPathComponent() }; return path
    }
    private func rig(fixture: Bool = false) throws -> (SessionApplicationModel, SetupKey, SetupEffects, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let key = SetupKey(), effects = SetupEffects()
        let ports = AccountApplicationPorts(storage: AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: key),
            preferences: SetupPlanPreferences(), control: { _, _ in effects.accounts += 1; throw AccountError.unavailable },
            openBrowser: { _ in effects.browsers += 1; return false }, sessionArguments: { runtime, _ in effects.helpers += 1; return runtime.arguments })
        let python = try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])
        var arguments = ["Relay", "--repository", root.path, "--python", python, "--role", "analytics"]
        if fixture { arguments += ["--fixture-suite", "reviewed"] }
        let model = SessionApplicationModel(arguments: arguments, contextPreferences: SetupContextPreferences(),
            profileVaultFactory: { ProfileVault(directory: directory.appendingPathComponent("Relay"), keys: key) }, accountPorts: ports)
        addTeardownBlock { await model.shutdown() }
        return (model, key, effects, directory)
    }
    private func router(_ model: SessionApplicationModel, open: @escaping () -> Void) -> RelayCommandRouter {
        RelayCommandRouter(state: { model.relayPresentation }, control: model.performWindowAction,
            start: { await model.start() }, cancelPreparation: model.cancelPreparation, retryPreparation: { await model.retryPreparation() },
            openContext: {}, openSettings: {}, openAISettings: { model.showAISettings(openWindow: open) }, showSession: {})
    }
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<2500 { if predicate() { return }; try await Task.sleep(for: .milliseconds(2)) }
        throw NSError(domain: "Synthetic first-launch route boundary was not reached", code: 1)
    }
    private func noAccountEffects(_ key: SetupKey, _ effects: SetupEffects, _ directory: URL) {
        XCTAssertEqual(key.calls, 0); XCTAssertEqual(effects.accounts, 0); XCTAssertEqual(effects.browsers, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Relay").path))
    }
    func testConnectSelectsAIInTheSameAlreadyOpenGeneralSettingsBeforeOpeningWithoutAnyAccountWork() async throws {
        let (model, key, effects, directory) = try rig()
        let settings = SessionSettingsView(model: model)
        XCTAssertEqual(settings.selectedSection, .general)
        var opened = 0
        let route = router(model, open: {
            XCTAssertEqual(settings.selectedSection, .ai, "The existing Settings instance must switch before it is raised")
            opened += 1
        })
        XCTAssertNil(route.perform(.connectChatGPT)); XCTAssertEqual(opened, 1)
        model.settingsSection = .screen
        XCTAssertNil(route.perform(.connectChatGPT)); XCTAssertEqual(opened, 2)
        XCTAssertEqual(settings.selectedSection, .ai)
        XCTAssertFalse(model.oauth); XCTAssertFalse(model.running); XCTAssertFalse(model.assistantActive)
        XCTAssertEqual(effects.helpers, 0); noAccountEffects(key, effects, directory)
    }
    func testConnectNavigationPreservesActualIdleOwnerCardDraftAndVisibleOriginalBasis() async throws {
        let (model, key, effects, directory) = try rig()
        model.assistant.draft = "What is the difference between WHERE and HAVING?"; model.assistant.submitDraft()
        try await waitUntil { model.snapshot.card != nil }
        model.assistant.draft = "What about those filters?"
        let basis = try XCTUnwrap(model.assistant.snapshot.basis?.requestID)
        let session = try XCTUnwrap(model.currentSessionID), helper = try model.ensureHelper(), replacement = model.snapshot.replacement
        let helpers = effects.helpers
        XCTAssertNil(router(model, open: {}).perform(.connectChatGPT))
        XCTAssertEqual(model.assistant.draft, "What about those filters?")
        XCTAssertEqual(model.assistant.snapshot.basis?.requestID, basis)
        XCTAssertEqual(model.currentSessionID, session); XCTAssertEqual(model.snapshot.replacement, replacement)
        XCTAssertTrue(model.assistantActive); XCTAssertNotNil(model.snapshot.card); XCTAssertFalse(helper.hasExited)
        XCTAssertEqual(effects.helpers, helpers); noAccountEffects(key, effects, directory)
    }
    func testOpeningAISettingsDoesNotBypassActualAccountMutationGuardDuringSyntheticAudio() async throws {
        let (model, key, effects, directory) = try rig(fixture: true)
        await model.start(); try await waitUntil { model.snapshot.card != nil }
        let session = model.currentSessionID, helpers = effects.helpers
        XCTAssertNil(router(model, open: {}).perform(.connectChatGPT))
        XCTAssertEqual(model.settingsSection, .ai); XCTAssertTrue(model.running)
        XCTAssertFalse(model.account.canMutate)
        await model.account.connect()
        XCTAssertEqual(model.currentSessionID, session); XCTAssertTrue(model.running); XCTAssertFalse(model.oauth)
        XCTAssertEqual(effects.helpers, helpers); noAccountEffects(key, effects, directory)
    }
    func testOnlyTheActualAIoffTerminalUsesTheSameConnectionRecoveryRoute() async throws {
        let (model, key, effects, directory) = try rig()
        model.assistant.draft = "Explain the JavaScript event loop and its microtask queue."
        model.assistant.submitDraft()
        try await waitUntil { model.snapshot.question != nil && model.snapshot.status != "Thinking" && !model.assistant.snapshot.isPreparing }
        XCTAssertEqual(model.snapshot.status, "AI requests are off"); XCTAssertNil(model.snapshot.card)
        let state = model.relayPresentation, helpers = effects.helpers
        let recovery = RelayEmptyAnswerPresentation(state: state, status: model.snapshot.status, hasQuestion: model.snapshot.question != nil)
        XCTAssertEqual(recovery.recoveryAction, .connectChatGPT)
        var opened = 0
        _ = router(model, open: { opened += 1 }).perform(try XCTUnwrap(recovery.recoveryAction))
        XCTAssertEqual(opened, 1); XCTAssertEqual(model.settingsSection, .ai)
        for status in ["Thinking", "No reliable answer available", "Background required", "Listening"] {
            XCTAssertNil(RelayEmptyAnswerPresentation(state: state, status: status, hasQuestion: true).recoveryAction)
        }
        XCTAssertNil(RelayEmptyAnswerPresentation(state: RelaySessionPresentation(paused: true), status: "AI requests are off", hasQuestion: true).recoveryAction)
        XCTAssertEqual(effects.helpers, helpers); noAccountEffects(key, effects, directory)
    }
}
