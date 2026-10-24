import Foundation
import RelayProfile
import XCTest
@testable import RelayAccount

private struct PortSyntheticKeys: ProfileKeyProvider {
    func key(createIfMissing: Bool) throws -> Data { Data(repeating: 29, count: 32) }
}
private actor AuthorizationCounter {
    var count = 0
    func open(_ value: AccountAuthorization) -> Bool {
        count += 1
        return value.authorizationURL.host == "auth.openai.com"
    }
}

final class AccountPortTests: XCTestCase, @unchecked Sendable {
    private func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(value, file: file, line: line) }
    private func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertFalse(value, file: file, line: line) }
    private var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
    private func python() throws -> URL {
        guard let value = ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"] else { throw XCTSkip("Set RELAY_TEST_PYTHON to the existing product test interpreter with crypto/HTTPX/PyJWT.") }
        return URL(fileURLWithPath: value)
    }
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    func testActualProtectedChildStatusAndProcessExitWithNoSyntheticAuthOrNetwork() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let bootstrap = try AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: PortSyntheticKeys()).controlBootstrap(generation: UUID(), createKey: true)
        let port = PipeAccountPort(python: try python(), repository: root, bootstrap: bootstrap)
        expectFalse(await port.isRunning)
        let response = try await port.perform(AccountRequest(action: .status))
        XCTAssertEqual(response.status, .signedOut); XCTAssertTrue(response.snapshot.registrations.isEmpty)
        expectTrue(await port.isRunning)
        await port.close()
        expectFalse(await port.isRunning); expectTrue(await port.exitConfirmed)
    }
    func testRealBridgeGeneratedOIDCConnectCatalogReplayAndSignoutOverActualNativePipe() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("metadata.jsonl")
        let bootstrap = try AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: PortSyntheticKeys()).controlBootstrap(generation: UUID(), createKey: true)
        let fixture = root.appendingPathComponent("tests/support/account_backend_helper.py")
        let port = PipeAccountPort(python: try python(), repository: root, bootstrap: bootstrap,
            pythonArguments: [fixture.path, "--synthetic-account-test", "--log", log.path])
        let counter = AuthorizationCounter(), request = try AccountRequest(action: .connect)
        let response = try await port.perform(request, authorization: { await counter.open($0) })
        XCTAssertEqual(response.status, .ready)
        XCTAssertEqual(response.snapshot.models.map(\.slug), ["gpt-synthetic-first", "gpt-synthetic-second"])
        let opened = await counter.count; XCTAssertEqual(opened, 1)
        let before = try Data(contentsOf: log)
        let status = try await port.perform(AccountRequest(action: .status))
        XCTAssertEqual(status.snapshot, response.snapshot)
        XCTAssertEqual(try Data(contentsOf: log), before)
        let replay = try await port.perform(request, authorization: { _ in XCTFail("Replay reopened browser"); return false })
        XCTAssertEqual(replay, response); XCTAssertEqual(try Data(contentsOf: log), before)
        let identity = try XCTUnwrap(response.snapshot.activeRegistrationID)
        let signedOut = try await port.perform(AccountRequest(action: .signOut, registrationID: identity))
        XCTAssertEqual(signedOut.status, .signedOut); XCTAssertNil(signedOut.snapshot.activeRegistrationID)
        await port.close(); expectTrue(await port.exitConfirmed)
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        for line in lines {
            let value = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: String]
            XCTAssertEqual(Set(value.keys), ["kind"])
            XCTAssertTrue(["token", "catalog", "revocation", "identity_metadata"].contains(value["kind"]!))
        }
    }
    func testUnresponsiveChildFailureWaitsForActualExitInsteadOfInventingQuiescence() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let bootstrap = try AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: PortSyntheticKeys()).controlBootstrap(generation: UUID(), createKey: true)
        let script = "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(30)"
        let port = PipeAccountPort(python: try python(), repository: root, bootstrap: bootstrap,
            pythonArguments: ["-u", "-c", script], operationTimeout: 0.1)
        do { _ = try await port.perform(AccountRequest(action: .status)); XCTFail("Missing response was accepted") }
        catch { expectTrue(await port.exitConfirmed); expectFalse(await port.isRunning) }
    }

    @MainActor func testActualControllerRestoresSavedGrantWithFreshGenerationAndNoSecondBrowserFlow() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let interpreter = try python(), repository = root
        let storage = AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: PortSyntheticKeys())
        var ports: [PipeAccountPort] = [], generations: [UUID] = [], browserCount = 0, retireCount = 0, preferences: [Bool] = []
        let controller = AccountController(storage: storage, portFactory: { bootstrap in
            let log = directory.appendingPathComponent("metadata-\(ports.count).jsonl")
            let port = PipeAccountPort(python: interpreter, repository: repository, bootstrap: bootstrap,
                pythonArguments: [repository.appendingPathComponent("tests/support/account_backend_helper.py").path, "--synthetic-account-test", "--log", log.path])
            generations.append(bootstrap.generation); ports.append(port); return port
        }, retireInference: { retireCount += 1 }, openBrowser: { url in
            browserCount += 1; return url.host == "auth.openai.com"
        }, persistAIEnabled: { preferences.append($0) })
        await controller.connect()
        let first = try XCTUnwrap(controller.inferenceSelection)
        XCTAssertTrue(controller.owns(first)); XCTAssertEqual(first.model, "gpt-synthetic-first")
        XCTAssertEqual(browserCount, 1)
        await controller.setAIEnabled(false)
        XCTAssertFalse(controller.owns(first)); XCTAssertNil(controller.inferenceSelection)
        expectTrue(await ports[0].exitConfirmed)
        await controller.setAIEnabled(true)
        let restored = try XCTUnwrap(controller.inferenceSelection)
        XCTAssertNotEqual(first.generation, restored.generation); XCTAssertEqual(first.registrationID, restored.registrationID)
        XCTAssertEqual(browserCount, 1); XCTAssertEqual(generations.count, 2); XCTAssertEqual(preferences, [true, false, true])
        let frame = try XCTUnwrap(controller.sessionBootstrap()).frame()
        let value = try JSONSerialization.jsonObject(with: frame.dropFirst(4)) as! [String: Any]
        XCTAssertEqual(value["registrationID"] as? String, restored.registrationID.uuidString.lowercased())
        XCTAssertEqual(value["accountGeneration"] as? String, restored.generation.uuidString.lowercased())
        await controller.signOut(restored.registrationID)
        XCTAssertFalse(controller.aiEnabled); XCTAssertNil(controller.inferenceSelection)
        XCTAssertEqual(controller.status, .signedOut); XCTAssertEqual(controller.snapshot?.registrations.count, 1)
        XCTAssertGreaterThanOrEqual(retireCount, 4)
        await controller.close()
        for port in ports { expectTrue(await port.exitConfirmed) }
    }

    func testFailedBrowserOpenCannotReturnReadyBeforeTheActualChildStops() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let bootstrap = try AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: PortSyntheticKeys()).controlBootstrap(generation: UUID(), createKey: true)
        let port = PipeAccountPort(python: try python(), repository: root, bootstrap: bootstrap,
            pythonArguments: [root.appendingPathComponent("tests/support/account_backend_helper.py").path, "--synthetic-account-test", "--log", directory.appendingPathComponent("metadata.jsonl").path])
        do { _ = try await port.perform(AccountRequest(action: .connect), authorization: { _ in false }); XCTFail("Failed browser open returned an active connection") }
        catch { expectTrue(await port.exitConfirmed); expectFalse(await port.isRunning) }
    }

    func testActualCancelJoinsOriginalHeldAuthorizationAndKeepsStatusResponsiveWithZeroTokenIO() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("metadata.jsonl"), gate = directory.appendingPathComponent("release-callback")
        let bootstrap = try AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: PortSyntheticKeys()).controlBootstrap(generation: UUID(), createKey: true)
        let port = PipeAccountPort(python: try python(), repository: root, bootstrap: bootstrap,
            pythonArguments: [root.appendingPathComponent("tests/support/account_backend_helper.py").path, "--synthetic-account-test", "--log", log.path, "--hold-callback", gate.path])
        let counter = AuthorizationCounter(), request = try AccountRequest(action: .connect)
        let original = Task { try await port.perform(request, authorization: { await counter.open($0) }) }
        for _ in 0..<2000 {
            if await counter.count == 1 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let count = await counter.count; XCTAssertEqual(count, 1)
        let status = try await port.perform(AccountRequest(action: .status))
        XCTAssertEqual(status.status, .busy)
        let cancellation = try await port.perform(AccountRequest(action: .cancel, targetRequestID: request.id))
        let response = try await original.value
        XCTAssertEqual(response.requestID, request.id); XCTAssertEqual(response.status, .cancelled)
        XCTAssertEqual(cancellation.status, .cancelled)
        XCTAssertEqual(try Data(contentsOf: log), Data())
        await port.close(); expectTrue(await port.exitConfirmed)
    }
}
