import XCTest
@testable import RelayProfile

@MainActor final class ProfilePortTests: XCTestCase {
    func testActualPythonChildStartsOnlyOnRequestAndReopensSyntheticSnapshot() async throws {
        let file = URL(fileURLWithPath: #filePath)
        let repo = file.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let port = PipeProfilePort(python: URL(fileURLWithPath: "/opt/homebrew/bin/python3"), repository: repo)
        let before = await port.isRunning
        XCTAssertFalse(before)
        let client = ProfileClient(port: port)
        let state = try await client.command(["command": "new"])
        XCTAssertEqual(state["ready"] as? Bool, true)
        let text = Data("I implemented Atlas SQL tests.".utf8)
        let selected = try await client.select(text, fileType: "txt", purpose: "project",
                                               label: "Atlas notes", role: "developer", project: "Atlas")
        let card = try XCTUnwrap(selected["card"] as? [String: Any])
        _ = try await client.command(["command": "decide", "fact_id": card["fact_id"]!,
            "fingerprint": card["card_fingerprint"]!, "decision": "approve", "actor": "self", "claim_key": "atlas.tests"])
        let snapshot = try await client.snapshot()
        XCTAssertTrue(snapshot.starts(with: Data("SQLite format 3".utf8)))
        _ = try await client.command(["command": "lock"])
        let loaded = try await client.load(snapshot)
        XCTAssertNil(loaded["card"] as? [String: Any])
        let sourceID = try XCTUnwrap(card["source_id"] as? String)
        _ = try await client.command(["command": "revoke", "source_id": sourceID])
        let redacted = try await client.snapshot()
        XCTAssertNil(redacted.range(of: Data("I implemented Atlas SQL tests.".utf8)))
        await port.close()
        let after = await port.isRunning
        XCTAssertFalse(after)
    }

    func testOversizedFrameIsRejectedBeforeChildLaunch() async throws {
        let port = PipeProfilePort(python: URL(fileURLWithPath: "/missing/python"), repository: URL(fileURLWithPath: "/private/tmp"))
        do {
            _ = try await port.request(Data(repeating: 65, count: 16*1024+1))
            XCTFail("Oversized frame accepted")
        } catch {}
        let running = await port.isRunning
        XCTAssertFalse(running)
    }

    func testSharedPortCloseLocksProfileWithoutStoppingConversationHelper() async throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let helper = PipeProfilePort(python: URL(fileURLWithPath: "/opt/homebrew/bin/python3"), repository: repo)
        let shared = ClosureProfilePort(request: { try await helper.request($0) }, close: {})
        let client = ProfileClient(port: shared)
        _ = try await client.command(["command": "new"])
        let snapshot = try await client.snapshot()
        await client.close()
        let running = await helper.isRunning
        XCTAssertTrue(running)
        do {
            _ = try await client.command(["command": "state"])
            XCTFail("Locked context remained readable")
        } catch ProfileError.rejected {}
        let reopened = try await client.load(snapshot)
        XCTAssertEqual(reopened["ready"] as? Bool, true)
        await helper.close()
    }
}
