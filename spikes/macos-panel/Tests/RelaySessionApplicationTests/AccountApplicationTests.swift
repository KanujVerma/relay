import Foundation
import XCTest
import RelayAccount
import RelayControls
import RelayProfile
import RelaySessionPanel
@testable import RelayPanelSession

@MainActor private final class AppPlanPreferences: ChatGPTPlanPreferences { var enabled = false }
@MainActor private final class AppProfilePreferences: SessionContextUsePreferences { var useInSessions = false }
private struct AppAccountKey: ProfileKeyProvider {
    let value: UInt8
    func key(createIfMissing: Bool) throws -> Data { Data(repeating: value, count: 32) }
}
private final class HeldAppAccountKey: ProfileKeyProvider, @unchecked Sendable {
    private let condition = NSCondition()
    private var hold = false, entered = false
    var waiting: Bool { condition.lock(); defer { condition.unlock() }; return entered }
    func beginHold() { condition.lock(); hold = true; entered = false; condition.unlock() }
    func release() { condition.lock(); hold = false; condition.broadcast(); condition.unlock() }
    func key(createIfMissing: Bool) throws -> Data {
        condition.lock(); defer { condition.unlock() }
        while hold { entered = true; condition.wait() }
        return Data(repeating: 43, count: 32)
    }
}
@MainActor private final class HeldAppProfileResponse {
    private var pending: CheckedContinuation<Void, Never>?
    var waiting: Bool { pending != nil }
    func observe(_ data: Data) async {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["command"] as? String == "select_commit" else { return }
        await withCheckedContinuation { pending = $0 }
    }
    func release() { pending?.resume(); pending = nil }
}
@MainActor private final class AccountRigState {
    var controls = 0, browsers = 0
    var sessionLogs: [URL] = []
    var sessionModes: [HelperMode] = []
    var expectedOldHelper: HelperTransport?
    var oldExitAtNextControl: [Bool] = []
}
@MainActor final class AccountApplicationTests: XCTestCase {
    private var root: URL { var value = URL(fileURLWithPath: #filePath); for _ in 0..<5 { value.deleteLastPathComponent() }; return value }
    private func waitUntil(line: UInt = #line, _ predicate: () -> Bool) async throws {
        for _ in 0..<4000 { if predicate() { return }; try await Task.sleep(for: .milliseconds(2)) }
        throw NSError(domain: "Synthetic account application boundary timeout at test line \(line)", code: 1)
    }
    private func metadata(_ path: URL) -> [[String: String]] {
        guard let data = try? Data(contentsOf: path), let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: String] }
    }
    private func model(directory: URL, preferences: AppPlanPreferences, state: AccountRigState,
                       context: AppProfilePreferences = AppProfilePreferences(), holdRefresh: URL? = nil,
                       key: any ProfileKeyProvider = AppAccountKey(value: 43), response: HeldAppProfileResponse? = nil,
                       holdAuthorization: URL? = nil) throws -> SessionApplicationModel {
        let interpreter = try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"]), repository = root
        let relay = directory.appendingPathComponent("Relay")
        let ports = AccountApplicationPorts(storage: AccountStorage(sharedDirectory: relay, keys: key), preferences: preferences,
            control: { runtime, bootstrap in
                if let old = state.expectedOldHelper { state.oldExitAtNextControl.append(old.hasExited); state.expectedOldHelper = nil }
                let log = directory.appendingPathComponent("control-\(state.controls).jsonl"); state.controls += 1
                var arguments = [repository.appendingPathComponent("tests/support/account_backend_helper.py").path, "--synthetic-account-test", "--log", log.path]
                if let holdAuthorization { arguments += ["--hold-callback", holdAuthorization.path] }
                return PipeAccountPort(python: runtime.executable, repository: runtime.resourceRoot, bootstrap: bootstrap, pythonArguments: arguments)
            }, openBrowser: { url in state.browsers += 1; return url.host == "auth.openai.com" }, sessionArguments: { runtime, mode in
                state.sessionModes.append(mode)
                guard mode == .protectedOAuth else { return runtime.arguments }
                let log = directory.appendingPathComponent("session-\(state.sessionLogs.count).jsonl"); state.sessionLogs.append(log)
                var prefix = [repository.appendingPathComponent("tests/support/account_product_helper.py").path, "--synthetic-product-account-test", "--log", log.path]
                if let holdRefresh { prefix += ["--hold-refresh", holdRefresh.path] }; return prefix
            })
        let model = SessionApplicationModel(arguments: ["Relay", "--fixture-suite", "reviewed", "--repository", repository.path, "--python", interpreter],
            contextPreferences: context, profileVaultFactory: { ProfileVault(directory: relay, keys: AppAccountKey(value: 81)) },
            profileResponseObserved: { data in await response?.observe(data) }, accountPorts: ports)
        addTeardownBlock { await model.shutdown() }
        return model
    }
    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }; return directory
    }
    private func ask(_ text: String, model: SessionApplicationModel) async throws {
        let previous = model.snapshot.replacement
        model.assistant.draft = text; model.assistant.sendDraftAsNewQuestion()
        do { try await waitUntil { model.snapshot.question == text && model.snapshot.card != nil && model.snapshot.replacement > previous } }
        catch { XCTFail("Synthetic typed result: status=\(model.snapshot.status), modelError=\(model.error ?? "none"), card=\(model.snapshot.card != nil), questionMatches=\(model.snapshot.question == text)"); throw error }
    }
    func testActualStartRestoresSavedAccountWithoutBrowserAndRealModelStreamRotatesProtectedBearer() async throws {
        let directory = try directory(), preferences = AppPlanPreferences(), state = AccountRigState()
        let first = try model(directory: directory, preferences: preferences, state: state)
        XCTAssertFalse(preferences.enabled); XCTAssertEqual(state.controls, 0)
        await first.account.connect(); XCTAssertTrue(preferences.enabled)
        let original = try XCTUnwrap(first.account.inferenceSelection); await first.shutdown()
        let restored = try model(directory: directory, preferences: preferences, state: state)
        await restored.start(); XCTAssertNil(restored.error); XCTAssertTrue(restored.running)
        try await waitUntil { restored.snapshot.card != nil }
        XCTAssertTrue(restored.running); XCTAssertEqual(state.browsers, 1)
        XCTAssertNotEqual(restored.account.inferenceSelection?.generation, original.generation)
        let log = try XCTUnwrap(state.sessionLogs.last)
        XCTAssertTrue(metadata(log).isEmpty, "Reviewed reference must not make a model request")
        try await ask("Explain event loops.", model: restored)
        try await ask("Explain callback scheduling.", model: restored)
        XCTAssertEqual(metadata(log).filter { $0["kind"] == "model" }.map { $0["credential"]! }, ["original", "rotated"])
        XCTAssertEqual(metadata(log).filter { $0["kind"] == "refresh" }.count, 1)
        XCTAssertNil(restored.error)
        await restored.shutdown()
    }
    func testPausedHeldRefreshIsActuallyReapedBeforeSignoutOrModeDisableAndSavedContextChoiceSurvives() async throws {
      for signOut in [true, false] {
        let directory = try directory(), preferences = AppPlanPreferences(), state = AccountRigState(), context = AppProfilePreferences()
        let gate = directory.appendingPathComponent("release-refresh")
        let model = try model(directory: directory, preferences: preferences, state: state, context: context, holdRefresh: gate)
        await model.account.connect(); let identity = try XCTUnwrap(model.account.snapshot?.activeRegistrationID)
        model.openMyContext(); await model.contextUse.waitForQuiescence()
        XCTAssertTrue(context.useInSessions)
        await model.profile.stageEnteredText("I implemented queue validation for Fictional Northstar.", purpose: "project", label: "Fictional notes", role: model.role, project: "Fictional Northstar")
        let card = try XCTUnwrap(model.profile.card)
        await model.profile.review(card, actor: "self", claimKey: "fictional.queue.validation", replaces: nil)
        let vault = directory.appendingPathComponent("Relay/profile.relayvault"), before = try Data(contentsOf: vault)
        await model.start(); try await waitUntil { model.snapshot.card != nil }
        try await ask("Explain event loops.", model: model)
        let log = try XCTUnwrap(state.sessionLogs.last), helper = try model.ensureHelper()
        model.assistant.draft = "Explain callback scheduling."; model.assistant.sendDraftAsNewQuestion()
        try await waitUntil { metadata(log).contains { $0["kind"] == "refresh_waiting" } }
        try model.perform(.pause); try await waitUntil { !model.stopping }
        XCTAssertFalse(helper.hasExited, "The token thread must still be held before account retirement")
        state.expectedOldHelper = helper
        if signOut { await model.account.signOut(identity) }
        else { await model.setAIEnabled(false) }
        XCTAssertEqual(state.oldExitAtNextControl, signOut ? [true] : []); XCTAssertTrue(helper.hasExited)
        if signOut { XCTAssertEqual(model.account.status, .signedOut) }
        XCTAssertFalse(preferences.enabled); XCTAssertFalse(model.oauth)
        XCTAssertEqual(metadata(log).filter { $0["kind"] == "model" }.count, 1)
        XCTAssertTrue(context.useInSessions); XCTAssertEqual(try Data(contentsOf: vault), before)
        XCTAssertNil(model.account.inferenceSelection)
        await model.shutdown()
      }
    }
    func testOriginalStartCallerCancellationChangedSourceAndEndJoinHeldReadinessWithoutStartingNativeOrHelper() async throws {
        for retirement in ["caller_cancel", "source_changed", "end"] {
            let directory = try directory(), preferences = AppPlanPreferences(), state = AccountRigState(), key = HeldAppAccountKey()
            let first = try model(directory: directory, preferences: preferences, state: state, key: key)
            await first.account.connect(); XCTAssertNotNil(first.account.inferenceSelection); await first.shutdown()
            let restored = try model(directory: directory, preferences: preferences, state: state, key: key)
            key.beginHold(); defer { key.release() }
            var started = false
            let start = Task { await restored.start(); started = true }
            try await waitUntil { key.waiting }
            XCTAssertTrue(restored.accountPreparationActive); XCTAssertFalse(restored.running)
            var stop: Task<Void, Never>?
            if retirement == "caller_cancel" { start.cancel() }
            else if retirement == "source_changed" { restored.microphoneEnabled.toggle() }
            else { stop = Task { await restored.stop() } }
            for _ in 0..<10 { await Task.yield() }
            XCTAssertFalse(started, "Original Start must join the actual held native key operation")
            XCTAssertTrue(state.sessionLogs.isEmpty); XCTAssertNil(restored.currentSessionID)
            key.release(); await start.value; await stop?.value
            XCTAssertTrue(started); XCTAssertFalse(restored.running); XCTAssertFalse(restored.accountPreparationActive)
            XCTAssertTrue(state.sessionLogs.isEmpty); XCTAssertNil(restored.currentSessionID)
            XCTAssertNil(restored.account.inferenceSelection); XCTAssertEqual(state.browsers, 1)
            await restored.shutdown()
        }
    }
    func testHelperOnlyAccountRetirementJoinsOriginalNativeProfileCallbackAfterActualChildExit() async throws {
        let directory = try directory(), preferences = AppPlanPreferences(), state = AccountRigState(), response = HeldAppProfileResponse()
        let model = try model(directory: directory, preferences: preferences, state: state, response: response)
        addTeardownBlock { await response.release() }
        model.openMyContext(); await model.contextUse.waitForQuiescence()
        let profile = model.profile, old = try model.ensureHelper()
        let request = Task { await profile.stageEnteredText("I implemented queue validation for Fictional Northstar.", purpose: "project", label: "Fictional notes", role: model.role, project: "Fictional Northstar") }
        try await waitUntil { response.waiting }
        var retired = false
        let retirement = Task { try await model.retireSessionHelperForAccountChange(); retired = true }
        try await waitUntil { old.hasExited }
        XCTAssertFalse(retired, "Actual child exit does not join the original native response observer")
        XCTAssertFalse(profile.opened); XCTAssertNil(profile.card)
        response.release(); await request.value; try await retirement.value
        XCTAssertTrue(retired); XCTAssertNil(profile.card); XCTAssertFalse(profile.busy)
        XCTAssertTrue(state.sessionLogs.isEmpty); await model.shutdown()
    }
    func testAccountMutationCannotLaunchAReplacementProfileHelperOrAcceptSourcePreparation() async throws {
        let directory = try directory(), preferences = AppPlanPreferences(), state = AccountRigState(), context = AppProfilePreferences()
        let gate = directory.appendingPathComponent("release-authorization")
        let model = try model(directory: directory, preferences: preferences, state: state, context: context, holdAuthorization: gate)
        addTeardownBlock { try? Data().write(to: gate) }
        let connection = Task { await model.account.connect() }
        try await waitUntil { state.browsers == 1 }
        XCTAssertTrue(model.account.busy); XCTAssertFalse(model.canStartSession)
        model.openMyContext(); for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(context.useInSessions, "An account mutation already owns old helper retirement")
        XCTAssertThrowsError(try model.ensureHelper(referenceOnly: true))
        XCTAssertTrue(state.sessionModes.isEmpty, "No replacement helper may launch before account mutation finishes")
        try Data().write(to: gate); await connection.value
        XCTAssertNotNil(model.account.inferenceSelection); XCTAssertTrue(state.sessionModes.isEmpty)
        model.openMyContext(); await model.contextUse.waitForQuiescence()
        XCTAssertTrue(context.useInSessions); XCTAssertTrue(model.profile.opened)
        XCTAssertEqual(state.sessionModes, [.protectedOAuth]); await model.shutdown()
    }
    func testConnectedAndRestoredAccountCanAskWithoutAudioThenReuseProtectedHelperForCaptureAndEndSignout() async throws {
        for restore in [false, true] {
            let directory = try directory(), preferences = AppPlanPreferences(), state = AccountRigState()
            let connected = try model(directory: directory, preferences: preferences, state: state)
            await connected.account.connect(); XCTAssertNotNil(connected.account.inferenceSelection)
            let target: SessionApplicationModel
            if restore { await connected.shutdown(); target = try model(directory: directory, preferences: preferences, state: state) }
            else { target = connected }
            try await ask("Explain event loops.", model: target)
            XCTAssertTrue(target.assistantActive); XCTAssertFalse(target.running)
            XCTAssertEqual(target.assistant.transcript.snapshot.rows.count, 0)
            let assistantID = try XCTUnwrap(target.currentSessionID), helper = try target.ensureHelper()
            try await ask("Explain callback scheduling.", model: target)
            let log = try XCTUnwrap(state.sessionLogs.last)
            XCTAssertEqual(metadata(log).filter { $0["kind"] == "model" }.map { $0["credential"]! }, ["original", "rotated"])
            XCTAssertEqual(state.browsers, 1)
            await target.start(); try await waitUntil { target.running && target.snapshot.card != nil }
            XCTAssertFalse(target.assistantActive); XCTAssertNotEqual(target.currentSessionID, assistantID)
            XCTAssertTrue(try target.ensureHelper() === helper)
            XCTAssertEqual(target.snapshot.question, "What is the difference between WHERE and HAVING?")
            let identity = try XCTUnwrap(target.account.snapshot?.activeRegistrationID)
            await target.stop(); XCTAssertTrue(helper.hasExited)
            await target.account.signOut(identity)
            XCTAssertEqual(target.account.status, .signedOut); XCTAssertFalse(preferences.enabled)
            await target.shutdown()
        }
    }
    func testIdleDraftEditAndEndJoinHeldAccountReadinessWithoutOpeningScopeOrLosingDraft() async throws {
        for end in [false, true] {
            let directory = try directory(), preferences = AppPlanPreferences(), state = AccountRigState(), key = HeldAppAccountKey()
            let first = try model(directory: directory, preferences: preferences, state: state, key: key)
            await first.account.connect(); await first.shutdown()
            let target = try model(directory: directory, preferences: preferences, state: state, key: key)
            key.beginHold(); defer { key.release() }
            target.assistant.draft = "Explain event loops."; target.assistant.sendDraftAsNewQuestion()
            try await waitUntil { key.waiting }
            XCTAssertTrue(target.assistant.snapshot.isPreparing); XCTAssertTrue(target.accountPreparationActive)
            var stopped = false
            let stop: Task<Void, Never>?
            if end { stop = Task { await target.stop(); stopped = true } }
            else { target.assistant.draft = "Explain callback scheduling."; stop = nil }
            for _ in 0..<10 { await Task.yield() }
            XCTAssertTrue(target.assistant.snapshot.isPreparing); XCTAssertFalse(stopped)
            XCTAssertNil(target.currentSessionID); XCTAssertTrue(state.sessionLogs.isEmpty)
            key.release(); await stop?.value; await target.assistant.waitForPreparationQuiescence()
            XCTAssertFalse(target.assistant.snapshot.isPreparing); XCTAssertFalse(target.accountPreparationActive)
            XCTAssertNil(target.currentSessionID); XCTAssertTrue(state.sessionLogs.isEmpty)
            XCTAssertEqual(target.assistant.draft, end ? "Explain event loops." : "Explain callback scheduling.")
            try await ask(target.assistant.draft, model: target)
            XCTAssertTrue(target.assistantActive); XCTAssertEqual(state.sessionModes, [.protectedOAuth])
            await target.shutdown()
        }
    }
    func testIdleHeldTokenIsReapedAndOriginalOwnerRetiredBeforeSignoutOrAIDisableThenNewScopeSurvivesOldEOF() async throws {
        for signOut in [true, false] {
            let directory = try directory(), preferences = AppPlanPreferences(), state = AccountRigState()
            let target = try model(directory: directory, preferences: preferences, state: state, holdRefresh: directory.appendingPathComponent("release-refresh"))
            await target.account.connect(); let identity = try XCTUnwrap(target.account.snapshot?.activeRegistrationID)
            try await ask("Explain event loops.", model: target)
            let old = try target.ensureHelper(), log = try XCTUnwrap(state.sessionLogs.last)
            target.assistant.draft = "Explain callback scheduling."; target.assistant.sendDraftAsNewQuestion()
            try await waitUntil { metadata(log).contains { $0["kind"] == "refresh_waiting" } }
            state.expectedOldHelper = old
            if signOut { await target.account.signOut(identity) } else { await target.setAIEnabled(false) }
            XCTAssertTrue(old.hasExited); XCTAssertFalse(target.assistantActive)
            XCTAssertNil(target.currentSessionID); XCTAssertNil(target.snapshot.card); XCTAssertFalse(target.oauth)
            XCTAssertEqual(metadata(log).filter { $0["kind"] == "model" }.count, 1)
            XCTAssertEqual(state.oldExitAtNextControl, signOut ? [true] : [])
            try await ask("Explain a callback queue.", model: target)
            let replacement = try target.ensureHelper()
            XCTAssertFalse(replacement === old); XCTAssertTrue(target.assistantActive)
            for _ in 0..<20 { await Task.yield() }
            XCTAssertNotNil(target.snapshot.card); XCTAssertFalse(replacement.hasExited)
            await target.shutdown()
        }
    }
    func testAccountRetirementKeepsDraftAndVisibleOriginalBasisUntilExplicitNewRequestIssuance() async throws {
        let directory = try directory(), preferences = AppPlanPreferences(), state = AccountRigState()
        let target = try model(directory: directory, preferences: preferences, state: state)
        await target.account.connect(); try await ask("Explain event loops.", model: target)
        target.assistant.draft = "Explain callback scheduling."
        let originalBasis = try XCTUnwrap(target.assistant.snapshot.basis?.requestID)
        await target.setAIEnabled(false)
        XCTAssertEqual(target.assistant.draft, "Explain callback scheduling.")
        XCTAssertEqual(target.assistant.snapshot.basis?.requestID, originalBasis)
        XCTAssertEqual(target.assistant.snapshot.basisState, .unavailable)
        let helpers = state.sessionModes.count
        target.assistant.submitDraft(); XCTAssertEqual(state.sessionModes.count, helpers)
        XCTAssertEqual(target.assistant.snapshot.basis?.requestID, originalBasis)
        target.assistant.sendDraftAsNewQuestion()
        XCTAssertTrue(target.assistant.snapshot.isPreparing)
        XCTAssertEqual(target.assistant.snapshot.basis?.requestID, originalBasis)
        try await waitUntil { target.snapshot.question == "Explain callback scheduling." && target.snapshot.card != nil }
        XCTAssertTrue(target.assistant.draft.isEmpty); XCTAssertNil(target.assistant.snapshot.basis)
        XCTAssertTrue(target.assistantActive); await target.shutdown()
    }
    func testExplicitContextLockDuringIdleAccountReadinessRetiresPreparationAndConsentWithoutOpeningAHelper() async throws {
        let directory = try directory(), preferences = AppPlanPreferences(), state = AccountRigState(), key = HeldAppAccountKey(), context = AppProfilePreferences()
        let first = try model(directory: directory, preferences: preferences, state: state, context: context, key: key)
        await first.account.connect(); first.openMyContext(); await first.contextUse.waitForQuiescence()
        XCTAssertTrue(first.profile.opened); XCTAssertTrue(context.useInSessions)
        let vault = directory.appendingPathComponent("Relay/profile.relayvault"), cipher = try Data(contentsOf: vault)
        await first.shutdown()
        let target = try model(directory: directory, preferences: preferences, state: state, context: context, key: key)
        let previousHelpers = state.sessionModes.count
        key.beginHold(); defer { key.release() }
        target.assistant.draft = "Explain event loops."; target.assistant.submitDraft()
        try await waitUntil { key.waiting }
        target.lockMyContext(); XCTAssertFalse(context.useInSessions)
        XCTAssertTrue(target.assistant.snapshot.isPreparing); XCTAssertEqual(state.sessionModes.count, previousHelpers)
        key.release(); await target.assistant.waitForPreparationQuiescence(); await target.contextUse.waitForQuiescence()
        XCTAssertNil(target.currentSessionID); XCTAssertFalse(target.assistantActive)
        XCTAssertEqual(target.assistant.draft, "Explain event loops.")
        XCTAssertEqual(state.sessionModes.count, previousHelpers); XCTAssertEqual(try Data(contentsOf: vault), cipher)
        await target.shutdown()
    }
}
