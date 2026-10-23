import XCTest
@testable import RelayProfile

private final class LifecycleKey: ProfileKeyProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var failing = false
    func setFailing(_ value: Bool) { lock.lock(); defer { lock.unlock() }; failing = value }
    func key(createIfMissing: Bool) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        if failing { throw ProfileError.unavailable }
        return Data(repeating: 4, count: 32)
    }
}

/// Real child below the injected delay/failure: cached responses may arrive
/// late, but approval, profile readiness and process retirement are real.
private actor ControlledProfilePort: ProfilePort {
    let helper: PipeProfilePort
    private var rejectLock = false
    private var invalidLockAck = false
    private var heldCommand: String?
    private var heldResponse: CheckedContinuation<Data, Error>?
    private var response: Data?
    private var stopped = false
    init(helper: PipeProfilePort) { self.helper = helper }
    func failLocks() { rejectLock = true }
    func omitLockAcknowledgement() { invalidLockAck = true }
    func holdNext(_ command: String) { heldCommand = command }
    func waitUntilHeld() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if heldResponse != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ProfileError.transport
    }
    func release() {
        guard let continuation = heldResponse, let response else { return }
        self.heldResponse = nil; self.response = nil
        continuation.resume(returning: response)
    }
    func request(_ data: Data) async throws -> Data {
        guard !stopped else { throw ProfileError.unavailable }
        let message = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let command = message?["command"] as? String
        if command == "lock", rejectLock { throw ProfileError.transport }
        if command == "lock", invalidLockAck { return Data("{\"ok\":true}".utf8) }
        let response = try await helper.request(data)
        if command == heldCommand {
            heldCommand = nil
            return try await withCheckedThrowingContinuation { continuation in
                self.response = response; heldResponse = continuation
            }
        }
        return response
    }
    func close() async {} // Ordinary shared conversation port stays alive.
    func emergencyShutdown() async {
        stopped = true
        await helper.emergencyShutdown()
    }
}

@MainActor final class ProfileLifecycleTests: XCTestCase {
    private var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func helper() throws -> PipeProfilePort {
        PipeProfilePort(python: try ProfileTestEnvironment.python(), repository: repo)
    }

    func testRejectedLockStopsRealSharedHelperWithApprovedFacts() async throws {
        let helper = try helper(), port = ControlledProfilePort(helper: helper)
        let client = ProfileClient(port: port)
        _ = try await client.command(["command": "new"])
        let state = try await client.select(Data("I implemented Atlas SQL tests.".utf8), fileType: "txt",
                         purpose: "project", label: "Atlas", role: "developer", project: "Atlas")
        let card = try XCTUnwrap(state["card"] as? [String: Any])
        _ = try await client.command(["command": "decide", "fact_id": card["fact_id"]!,
            "fingerprint": card["card_fingerprint"]!, "decision": "approve", "actor": "self", "claim_key": "atlas.tests"])
        let approved = try await client.command(["command": "current_claim", "claim_key": "atlas.tests"])
        XCTAssertNotNil(approved["fact"] as? [String: Any])
        await port.failLocks()
        let outcome = await client.close()
        XCTAssertEqual(outcome, .helperStopped)
        let running = await helper.isRunning
        XCTAssertFalse(running, "Missing lock acknowledgement left the approved provider alive")
        do {
            _ = try await client.command(["command": "state"])
            XCTFail("Emergency-retired client could still retrieve an active profile")
        } catch {}
        await helper.close()
    }

    func testGenericSuccessDoesNotAcknowledgeAProfileLockOrPermitRestart() async throws {
        let helper = try helper(), port = ControlledProfilePort(helper: helper)
        let client = ProfileClient(port: port)
        _ = try await client.command(["command": "new"])
        await port.omitLockAcknowledgement()
        let outcome = await client.close()
        XCTAssertEqual(outcome, .helperStopped)
        do {
            _ = try await helper.request(Data("{\"command\":\"new\"}".utf8))
            XCTFail("Emergency-stopped helper accepted another start")
        } catch {}
        let running = await helper.isRunning
        XCTAssertFalse(running)
    }

    func testFailedSaveWithApprovedFactsAndMissingLockAcknowledgementStopsHelper() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = LifecycleKey(), helper = try helper(), port = ControlledProfilePort(helper: helper)
        let controller = ProfileController(client: ProfileClient(port: port),
                                           vault: ProfileVault(directory: directory, keys: key))
        await controller.openProfile()
        await controller.stageEnteredText("I implemented Atlas SQL tests.", purpose: "project", label: "Atlas",
                                            role: "developer", project: "Atlas")
        let card = try XCTUnwrap(controller.card)
        await controller.review(card, actor: "self", claimKey: "atlas.tests", replaces: nil)
        XCTAssertNil(controller.card)
        key.setFailing(true)
        await port.failLocks()
        await controller.stageEnteredText("I chose SQLite for Atlas.", purpose: "project", label: "Atlas notes",
                                            role: "developer", project: "Atlas")
        XCTAssertFalse(controller.opened)
        XCTAssertTrue(controller.sources.isEmpty)
        XCTAssertNotNil(controller.errorStatus)
        XCTAssertEqual(controller.closeOutcome, .helperStopped)
        let running = await helper.isRunning
        XCTAssertFalse(running, "Unsaved mutation left approved evidence active after failed lock")
        key.setFailing(false)
        let saved = try ProfileVault(directory: directory, keys: key).load()
        XCTAssertNotNil(saved.range(of: Data("I implemented Atlas SQL tests.".utf8)))
        XCTAssertNil(saved.range(of: Data("I chose SQLite for Atlas.".utf8)))
        await helper.close()
    }

    func testDelayedOpenListsCannotRestoreClosedState() async throws {
        for command in ["sources", "memories"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let key = LifecycleKey(), vault = ProfileVault(directory: directory, keys: key)
            let helper = try helper(), port = ControlledProfilePort(helper: helper)
            let controller = ProfileController(client: ProfileClient(port: port), vault: vault)
            // Establish a source so the stale response also carries a private label.
            await controller.openProfile()
            await controller.stageEnteredText("I wrote Atlas tests.", purpose: "project", label: "Atlas notes",
                                                role: "developer", project: "Atlas")
            let card = try XCTUnwrap(controller.card)
            await controller.review(card, actor: "self", claimKey: "atlas.tests", replaces: nil)
            await controller.close()
            XCTAssertEqual(controller.closeOutcome, .locked)
            await port.holdNext(command)
            let opening = Task { await controller.openProfile() }
            try await port.waitUntilHeld()
            await controller.close()
            let closedError = controller.errorStatus
            XCTAssertEqual(controller.closeOutcome, .helperStopped)
            let freshHelper = try self.helper()
            let fresh = ProfileController(client: ProfileClient(port: freshHelper), vault: vault)
            await fresh.openProfile()
            XCTAssertTrue(fresh.opened)
            await port.release()
            await opening.value
            XCTAssertFalse(controller.opened)
            XCTAssertTrue(controller.sources.isEmpty)
            XCTAssertTrue(controller.memories.isEmpty)
            XCTAssertEqual(controller.memoryCount, 0)
            XCTAssertNil(controller.card)
            XCTAssertEqual(controller.errorStatus, closedError)
            XCTAssertFalse(controller.busy)
            XCTAssertEqual(fresh.sources.count, 1)
            XCTAssertEqual(fresh.memoryCount, 1)
            await fresh.close()
            await helper.close()
        }
    }

    func testDelayedSelectionAndReviewCannotPersistAfterCloseOrReopen() async throws {
        for command in ["transfer_chunk", "select_commit", "decide", "sources", "memories"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let key = LifecycleKey(), vault = ProfileVault(directory: directory, keys: key)
            let helper = try self.helper(), port = ControlledProfilePort(helper: helper)
            let controller = ProfileController(client: ProfileClient(port: port), vault: vault)
            await controller.openProfile()
            if command == "decide" {
                await controller.stageEnteredText("I wrote Atlas tests.", purpose: "project", label: "Atlas notes",
                                                    role: "developer", project: "Atlas")
            }
            let before = try vault.load()
            await port.holdNext(command)
            let displayed = controller.card
            let mutation = Task {
                if command == "decide", let displayed {
                    await controller.review(displayed, actor: "self", claimKey: "atlas.tests", replaces: nil)
                } else {
                    await controller.stageEnteredText("I wrote Atlas tests.\n" + String(repeating: " ", count: 5000),
                        purpose: "project", label: "Atlas notes", role: "developer", project: "Atlas")
                }
            }
            try await port.waitUntilHeld()
            await controller.close()
            let closedError = controller.errorStatus
            XCTAssertEqual(controller.closeOutcome, .helperStopped, command)
            let freshHelper = try self.helper()
            let fresh = ProfileController(client: ProfileClient(port: freshHelper), vault: vault)
            await fresh.openProfile()
            XCTAssertTrue(fresh.opened, command)
            let savedAtReopen = try vault.load()
            await port.release()
            await mutation.value
            XCTAssertFalse(controller.opened, command)
            XCTAssertTrue(controller.sources.isEmpty, command)
            XCTAssertNil(controller.card, command)
            XCTAssertFalse(controller.busy, command)
            XCTAssertEqual(controller.errorStatus, closedError, command)
            XCTAssertEqual(try vault.load(), savedAtReopen, command)
            if !["sources", "memories"].contains(command) {
                XCTAssertEqual(savedAtReopen, before, "An uncommitted delayed operation reached the vault: " + command)
            } else {
                XCTAssertEqual(fresh.sources.count, 1)
            }
            await fresh.close()
            let running = await helper.isRunning
            XCTAssertFalse(running, command)
        }
    }

    func testDelayedLookupCannotRepublishEvidenceOrOverwriteReopenedState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = ProfileVault(directory: directory, keys: LifecycleKey())
        let helper = try helper(), port = ControlledProfilePort(helper: helper)
        let controller = ProfileController(client: ProfileClient(port: port), vault: vault)
        await controller.openProfile()
        await controller.stageEnteredText("I wrote Atlas tests.", purpose: "project", label: "Atlas notes",
                                            role: "developer", project: "Atlas")
        let card = try XCTUnwrap(controller.card)
        await controller.review(card, actor: "self", claimKey: "atlas.tests", replaces: nil)
        await port.holdNext("current_claim")
        let lookup = Task { await controller.lookupExisting(claimKey: "atlas.tests") }
        try await port.waitUntilHeld()
        await controller.close()
        let closedError = controller.errorStatus
        let freshHelper = try self.helper()
        let fresh = ProfileController(client: ProfileClient(port: freshHelper), vault: vault)
        await fresh.openProfile()
        await fresh.lookupExisting(claimKey: "atlas.tests")
        XCTAssertNotNil(fresh.existingFact)
        await port.release()
        await lookup.value
        XCTAssertFalse(controller.opened)
        XCTAssertNil(controller.existingFact)
        XCTAssertNil(controller.existingClaimKey)
        XCTAssertTrue(controller.sources.isEmpty)
        XCTAssertEqual(controller.errorStatus, closedError)
        XCTAssertFalse(controller.busy)
        XCTAssertNotNil(fresh.existingFact)
        await fresh.close()
    }
}
