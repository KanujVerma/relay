import Foundation
import RelayProfile
import XCTest
@testable import RelayAccount

private actor Gate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var entered = false
    func wait() async {
        entered = true
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { open = true; let pending = waiters; waiters.removeAll(); pending.forEach { $0.resume() } }
}
private final class ControllerKeys: ProfileKeyProvider, @unchecked Sendable {
    private let lock = NSLock(); private var reads = 0
    var count: Int { lock.withLock { reads } }
    func key(createIfMissing: Bool) throws -> Data { lock.withLock { reads += 1 }; return Data(repeating: 31, count: 32) }
}
private actor SyntheticAccountPort: AccountPort {
    let identity = UUID()
    var actions: [AccountAction] = []
    var closes = 0
    let connectGate: Gate?
    let plan: Bool
    init(connectGate: Gate? = nil, plan: Bool = true) { self.connectGate = connectGate; self.plan = plan }
    func perform(_ request: AccountRequest, authorization: @escaping @Sendable (AccountAuthorization) async -> Bool) async throws -> AccountResponse {
        actions.append(request.action)
        if request.action == .connect { await connectGate?.wait() }
        if request.action == .cancel { await connectGate?.wait() }
        let signedOut = request.action == .signOut
        let cancelled = request.action == .cancel
        let snapshot: [String: Any] = ["revision": 3, "activeRegistrationID": signedOut ? NSNull() : identity.uuidString.lowercased() as Any,
            "registrations": [["registrationID": identity.uuidString.lowercased(), "label": "Synthetic account", "email": "synthetic@example.test",
                "identityState": "validated_at_sign_in", "planUsageState": signedOut ? "unknown" : plan ? "granted" : "not_granted",
                "sessionState": signedOut ? "signed_out" : "available", "lastValidatedAt": 1, "planNoticeAcknowledged": request.action == .acknowledgePlanNotice]],
            "models": request.action == .status || !plan || signedOut ? [] : [["slug": "synthetic-first", "displayName": "First"], ["slug": "synthetic-second", "displayName": "Second"]],
            "catalogState": request.action == .status || !plan || signedOut ? "unloaded" : "current"]
        let status = cancelled ? "cancelled" : signedOut ? "signed_out" : plan ? "ready" : "plan_disabled"
        let reason = cancelled ? "authorization_cancelled" : signedOut ? "signed_out" : request.action == .status || request.action == .acknowledgePlanNotice ? "current_status" : request.action == .select ? "account_selected" : request.action == .models ? "catalog_updated" : plan ? "connected" : "plan_permission_missing"
        return try AccountResponse(data: JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "kind": "account_response",
            "requestID": request.id.uuidString.lowercased(), "action": request.action.rawValue, "resultRevision": 2, "status": status,
            "reasonCode": reason, "snapshot": snapshot]))
    }
    func close() async { closes += 1 }
}

@MainActor final class AccountControllerTests: XCTestCase {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    private func entered(_ gate: Gate) async throws {
        for _ in 0..<1000 { if await gate.entered { return }; try await Task.sleep(for: .milliseconds(1)) }
        XCTFail("Synthetic barrier was never reached")
    }
    func testConstructorInertAndConnectWaitsActualRetirementBeforeKeyPortOrPrivateSelection() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let keys = ControllerKeys(), gate = Gate(), port = SyntheticAccountPort()
        var bootstraps: [AccountSecretBootstrap] = [], preferences: [Bool] = []
        let controller = AccountController(storage: AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: keys),
            portFactory: { bootstraps.append($0); return port }, retireInference: { await gate.wait() },
            openBrowser: { _ in XCTFail("Synthetic port must not open a browser"); return false }, persistAIEnabled: { preferences.append($0) })
        XCTAssertEqual(keys.count, 0); XCTAssertTrue(bootstraps.isEmpty); XCTAssertNil(controller.inferenceSelection)
        let operation = Task { await controller.connect() }; try await entered(gate)
        XCTAssertTrue(controller.busy); XCTAssertEqual(keys.count, 0); XCTAssertTrue(bootstraps.isEmpty)
        await gate.release(); await operation.value
        XCTAssertEqual(controller.status, .ready); XCTAssertEqual(controller.inferenceSelection?.model, "synthetic-first")
        XCTAssertEqual(preferences, [true]); XCTAssertTrue(controller.aiEnabled)
        let frame = try XCTUnwrap(controller.sessionBootstrap()).frame()
        let payload = try JSONSerialization.jsonObject(with: frame.dropFirst(4)) as! [String: Any]
        XCTAssertEqual(payload["purpose"] as? String, "oauth_session")
        XCTAssertEqual(payload["accountGeneration"] as? String, bootstraps.first?.generation.uuidString.lowercased())
        await controller.close()
    }
    func testRestoreReselectsSavedGrantAndCurrentCatalogWithoutAnyBrowserReconnect() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let port = SyntheticAccountPort(); var retired = 0, persisted: [Bool] = []
        let controller = AccountController(storage: AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: ControllerKeys()),
            portFactory: { _ in port }, retireInference: { retired += 1 }, openBrowser: { _ in XCTFail("Restore opened browser"); return false },
            aiEnabled: true, persistAIEnabled: { persisted.append($0) })
        await controller.restore()
        let actions = await port.actions
        XCTAssertEqual(actions, [.status, .select]); XCTAssertEqual(retired, 1)
        XCTAssertEqual(controller.inferenceSelection?.model, "synthetic-first"); XCTAssertTrue(persisted.isEmpty)
        await controller.close()
    }
    func testIdentityOnlyConnectDoesNotInventPlanPermissionOrRetryConsent() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let port = SyntheticAccountPort(plan: false); var persisted: [Bool] = []
        let controller = AccountController(storage: AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: ControllerKeys()),
            portFactory: { _ in port }, retireInference: {}, openBrowser: { _ in false }, persistAIEnabled: { persisted.append($0) })
        await controller.connect()
        XCTAssertEqual(controller.status, .planDisabled); XCTAssertNil(controller.inferenceSelection)
        XCTAssertTrue(persisted.isEmpty); XCTAssertFalse(controller.aiEnabled)
        let actions = await port.actions; XCTAssertEqual(actions, [.connect])
        await controller.close()
    }
    func testCancelDuringRetirementCannotCreateAChildOrAcknowledgeEarly() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let gate = Gate(), keys = ControllerKeys(); var factories = 0, cancelFinished = false
        let controller = AccountController(storage: AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: keys),
            portFactory: { _ in factories += 1; return SyntheticAccountPort() }, retireInference: { await gate.wait() }, openBrowser: { _ in false })
        let operation = Task { await controller.connect() }; try await entered(gate)
        let cancelled = Task { await controller.cancel(); cancelFinished = true }
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertFalse(cancelFinished); XCTAssertTrue(controller.busy); XCTAssertEqual(keys.count, 0)
        await gate.release(); await cancelled.value; await operation.value
        XCTAssertEqual(factories, 0); XCTAssertEqual(controller.status, .cancelled); XCTAssertFalse(controller.busy)
        XCTAssertNil(controller.inferenceSelection)
    }
    func testCancelledUncooperativeReplyCannotIssueSelectionAndProfileVaultIsUntouched() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("Relay"), gate = Gate(), port = SyntheticAccountPort(connectGate: gate)
        let profile = ProfileVault(directory: root, keys: ControllerKeys()), content = Data("synthetic confirmed memory".utf8)
        try profile.save(content, createKey: true)
        let before = try Data(contentsOf: root.appendingPathComponent("profile.relayvault"))
        let controller = AccountController(storage: AccountStorage(sharedDirectory: root, keys: ControllerKeys()),
            portFactory: { _ in port }, retireInference: {}, openBrowser: { _ in false })
        let operation = Task { await controller.connect() }; try await entered(gate)
        let cancel = Task { await controller.cancel() }
        try await Task.sleep(for: .milliseconds(10)); XCTAssertTrue(controller.busy)
        await gate.release(); await cancel.value; await operation.value
        XCTAssertNil(controller.inferenceSelection); XCTAssertFalse(controller.aiEnabled)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("profile.relayvault")), before)
        XCTAssertEqual(try profile.load(), content)
    }
    func testFailedRetirementOrNewCapturePreventsAllKeyPortAndAccountMutation() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let keys = ControllerKeys(); var factories = 0
        let failed = AccountController(storage: AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: keys),
            portFactory: { _ in factories += 1; return SyntheticAccountPort() }, retireInference: { throw AccountError.closed }, openBrowser: { _ in false })
        await failed.connect(); XCTAssertEqual(keys.count, 0); XCTAssertEqual(factories, 0); XCTAssertNil(failed.inferenceSelection)
        let gate = Gate(); var idle = true
        let changed = AccountController(storage: AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: keys),
            portFactory: { _ in factories += 1; return SyntheticAccountPort() }, retireInference: { await gate.wait() }, openBrowser: { _ in false }, isIdle: { idle })
        let operation = Task { await changed.connect() }; try await entered(gate); idle = false
        await gate.release(); await operation.value
        XCTAssertEqual(keys.count, 0); XCTAssertEqual(factories, 0); XCTAssertNil(changed.inferenceSelection)
        XCTAssertFalse(changed.busy)
    }
    func testSelectedAccountMismatchCannotBecomePrivateInferenceAuthority() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let port = SyntheticAccountPort()
        let controller = AccountController(storage: AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: ControllerKeys()),
            portFactory: { _ in port }, retireInference: {}, openBrowser: { _ in false })
        await controller.connect(); XCTAssertNotNil(controller.inferenceSelection)
        await controller.select(UUID())
        XCTAssertNil(controller.inferenceSelection); XCTAssertEqual(controller.status, .error)
        await controller.close()
    }

    func testExplicitReadinessIsInertWithAIOffAndCoalescesOnlyTheOriginalCurrentCaller() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let keys = ControllerKeys(), gate = Gate(); var factories = 0, current = true
        var readiness: AccountPreparationController?
        let controller = AccountController(storage: AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: keys),
            portFactory: { _ in factories += 1; return SyntheticAccountPort() }, retireInference: { await gate.wait() }, openBrowser: { _ in false },
            aiEnabled: true, isIdle: { readiness?.hasCurrentCaller ?? true })
        let prepared = AccountPreparationController(account: controller); readiness = prepared
        XCTAssertFalse(prepared.isPreparing); XCTAssertEqual(keys.count, 0)
        let identity = UUID()
        let first = Task { try await prepared.prepare(intentID: identity, isCurrent: { current }) }
        try await entered(gate)
        let duplicate = Task { try await prepared.prepare(intentID: identity, isCurrent: { true }) }
        await Task.yield(); current = false; await gate.release()
        for task in [first, duplicate] {
            do { try await task.value; XCTFail("A different duplicate callback replaced the original caller") } catch { }
        }
        XCTAssertEqual(keys.count, 0); XCTAssertEqual(factories, 0); XCTAssertFalse(prepared.isPreparing)
        let off = AccountController(storage: AccountStorage(sharedDirectory: directory.appendingPathComponent("OtherRelay"), keys: keys),
            portFactory: { _ in factories += 1; return SyntheticAccountPort() }, retireInference: { XCTFail("AI-off action retired a helper") }, openBrowser: { _ in false })
        try await AccountPreparationController(account: off).prepare(intentID: UUID(), isCurrent: { true })
        XCTAssertEqual(keys.count, 0); XCTAssertEqual(factories, 0)
    }

    func testExplicitReadinessCancelJoinsItsActualAccountTaskAndWrongIntentCannotRetireIt() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let gate = Gate(), keys = ControllerKeys(); var finished = false, factories = 0
        let controller = AccountController(storage: AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: keys),
            portFactory: { _ in factories += 1; return SyntheticAccountPort() }, retireInference: { await gate.wait() }, openBrowser: { _ in false }, aiEnabled: true)
        let preparation = AccountPreparationController(account: controller), identity = UUID()
        let owner = Task { try await preparation.prepare(intentID: identity, isCurrent: { true }) }; try await entered(gate)
        await preparation.cancel(intentID: UUID()); XCTAssertTrue(preparation.isPreparing); XCTAssertFalse(preparation.isCancelling)
        let cancellation = Task { await preparation.cancel(intentID: identity); finished = true }
        try await Task.sleep(for: .milliseconds(10)); XCTAssertFalse(finished); XCTAssertTrue(preparation.isCancelling)
        await gate.release(); await cancellation.value
        do { try await owner.value; XCTFail("Cancelled explicit action was marked ready") } catch { }
        XCTAssertEqual(factories, 0); XCTAssertEqual(keys.count, 0); XCTAssertFalse(preparation.isPreparing)
    }
    func testExplicitReadinessSuccessfulCoalescedWaitersObserveOneActualRestore() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let gate = Gate(), port = SyntheticAccountPort(); var factories = 0
        let controller = AccountController(storage: AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: ControllerKeys()),
            portFactory: { _ in factories += 1; return port }, retireInference: { await gate.wait() }, openBrowser: { _ in false }, aiEnabled: true)
        let preparation = AccountPreparationController(account: controller), identity = UUID()
        let first = Task { try await preparation.prepare(intentID: identity, isCurrent: { true }) }; try await entered(gate)
        let duplicate = Task { try await preparation.prepare(intentID: identity, isCurrent: { true }) }
        await Task.yield()
        do { try await preparation.prepare(intentID: UUID(), isCurrent: { true }); XCTFail("Competing action bypassed the owned preparation") } catch { }
        await gate.release(); try await first.value; try await duplicate.value
        XCTAssertEqual(factories, 1); XCTAssertFalse(preparation.isPreparing)
        let actions = await port.actions; XCTAssertEqual(actions, [.status, .select])
        await controller.close()
    }
}
