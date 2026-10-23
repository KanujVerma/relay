import XCTest
@testable import RelayProfile

private struct ControllerKey: ProfileKeyProvider {
    var byte: UInt8 = 5
    func key(createIfMissing: Bool) throws -> Data { Data(repeating: byte, count: 32) }
}

private final class FailingSaveKey: ProfileKeyProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    func key(createIfMissing: Bool) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        reads += 1
        if reads > 1 { throw ProfileError.unavailable }
        return Data(repeating: 8, count: 32)
    }
}

@MainActor final class ProfileControllerTests: XCTestCase {
    func testConstructionDoesNotLaunchImportAndActualReviewPersistsAcrossReopen() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let port = PipeProfilePort(python: try ProfileTestEnvironment.python(), repository: root)
        let vault = ProfileVault(directory: directory, keys: ControllerKey())
        var invalidated = 0
        let controller = ProfileController(client: ProfileClient(port: port), vault: vault,
                                            onInvalidate: { invalidated += 1 })
        XCTAssertFalse(controller.opened)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let running = await port.isRunning
        XCTAssertFalse(running)
        await controller.openProfile()
        XCTAssertTrue(controller.opened)
        await controller.stageEnteredText("I chose SQLite for Atlas because atomic updates mattered.",
                    purpose: "project", label: "Atlas notes", role: "developer", project: "Atlas")
        let card = try XCTUnwrap(controller.card)
        XCTAssertEqual(card.actorHint, "self")
        await controller.review(card, actor: "self", claimKey: "atlas.rationale", replaces: nil)
        XCTAssertNil(controller.card)
        XCTAssertNil(controller.errorStatus)
        XCTAssertGreaterThanOrEqual(invalidated, 2)
        await controller.close()
        let reopened = ProfileController(client: ProfileClient(port: PipeProfilePort(
            python: try ProfileTestEnvironment.python(), repository: root)), vault: vault)
        await reopened.openProfile()
        XCTAssertTrue(reopened.opened)
        XCTAssertNil(reopened.card)
        XCTAssertEqual(reopened.sources.count, 1)
        let source = try XCTUnwrap(reopened.sources.first)
        await reopened.revoke(source)
        XCTAssertTrue(reopened.sources.isEmpty)
        XCTAssertNil(try vault.load().range(of: Data("atomic updates mattered".utf8)))
        await reopened.close()
    }

    func testFailedPersistenceLocksProfileAndRetiresAdmission() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let port = PipeProfilePort(python: try ProfileTestEnvironment.python(), repository: root)
        var invalidated = 0
        let controller = ProfileController(client: ProfileClient(port: port),
            vault: ProfileVault(directory: directory, keys: FailingSaveKey()), onInvalidate: { invalidated += 1 })
        await controller.openProfile()
        XCTAssertTrue(controller.opened)
        await controller.stageEnteredText("I wrote Atlas SQL tests.", purpose: "project", label: "Atlas",
                                            role: "developer", project: "Atlas")
        XCTAssertFalse(controller.opened)
        XCTAssertNil(controller.card)
        XCTAssertNotNil(controller.errorStatus)
        XCTAssertGreaterThanOrEqual(invalidated, 2)
        let running = await port.isRunning
        XCTAssertFalse(running)
        let saved = try ProfileVault(directory: directory, keys: ControllerKey(byte: 8)).load()
        XCTAssertNil(saved.range(of: Data("I wrote Atlas SQL tests.".utf8)))
    }
}
