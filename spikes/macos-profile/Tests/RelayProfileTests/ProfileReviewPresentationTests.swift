import Foundation
import XCTest
@testable import RelayProfile

private struct ReviewPresentationKey: ProfileKeyProvider {
    func key(createIfMissing: Bool) throws -> Data { Data(repeating: 21, count: 32) }
}

final class ProfileReviewPresentationTests: XCTestCase {
    func testDefaultTopicIsBoundedAndSeparatesSourceAndFactIdentity() {
        let inputs = [("source", "fact"), ("source", "other"), ("other", "fact"),
                      ("a.b", "c"), ("a", "b.c"), (String(repeating: "履歴", count: 200), "fact")]
        let keys = inputs.map { ProfileReviewPresentation.claimKey(sourceID: $0.0, factID: $0.1, topic: "") }
        XCTAssertEqual(Set(keys).count, inputs.count)
        for key in keys {
            XCTAssertFalse(key.isEmpty)
            XCTAssertLessThanOrEqual(key.utf8.count, 160)
            XCTAssertNotNil(key.range(of: "^[a-z0-9.]+$", options: .regularExpression))
        }
        XCTAssertEqual(keys[0], ProfileReviewPresentation.claimKey(sourceID: "source", factID: "fact", topic: "  "))
    }

    func testExplicitCorrectionTopicKeepsExistingNormalization() {
        let key = ProfileReviewPresentation.claimKey(sourceID: "source", factID: "fact", topic: "  Átlas / Storage choice! ")
        XCTAssertEqual(key, "atlas.storage.choice")
        XCTAssertEqual(key, ProfileReviewPresentation.claimKey(sourceID: "new-source", factID: "new-fact", topic: "ATLAS storage choice"))
    }

    func testApprovalStillRequiresExplicitKnownOwnershipAndConflictDecision() {
        for actor in ["", "unknown", "self ", "model-says-self"] {
            XCTAssertFalse(ProfileReviewPresentation.canApprove(actor: actor, claimKey: "reviewed.fact", hasExisting: false, replacesExisting: false))
        }
        for actor in ["self", "team", "teammate"] {
            XCTAssertTrue(ProfileReviewPresentation.canApprove(actor: actor, claimKey: "reviewed.fact", hasExisting: false, replacesExisting: false))
        }
        XCTAssertFalse(ProfileReviewPresentation.canApprove(actor: "self", claimKey: "", hasExisting: false, replacesExisting: false))
        XCTAssertFalse(ProfileReviewPresentation.canApprove(actor: "self", claimKey: String(repeating: "a", count: 161), hasExisting: false, replacesExisting: false))
        XCTAssertFalse(ProfileReviewPresentation.canApprove(actor: "self", claimKey: "reviewed.fact", hasExisting: true, replacesExisting: false))
        XCTAssertTrue(ProfileReviewPresentation.canApprove(actor: "self", claimKey: "reviewed.fact", hasExisting: true, replacesExisting: true))
    }

    @MainActor func testReviewWithoutATypedTopicPersistsThroughTheActualHelper() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let port = PipeProfilePort(python: try ProfileTestEnvironment.python(), repository: root)
        let client = ProfileClient(port: port)
        let controller = ProfileController(client: client, vault: ProfileVault(directory: directory, keys: ReviewPresentationKey()))
        await controller.openProfile()
        await controller.stageEnteredText("I chose SQLite for Atlas because atomic updates mattered.",
                                          purpose: "project", label: "Atlas notes", role: "developer", project: "Atlas")
        let card = try XCTUnwrap(controller.card)
        XCTAssertEqual(controller.memoryCount, 0)
        XCTAssertTrue(controller.memories.isEmpty)
        let key = ProfileReviewPresentation.claimKey(sourceID: card.sourceID, factID: card.factID, topic: "")
        await controller.review(card, actor: "self", claimKey: key, replaces: nil)
        XCTAssertNil(controller.errorStatus)
        XCTAssertNil(controller.card)
        XCTAssertEqual(controller.memoryCount, 1)
        XCTAssertEqual(controller.memories.first?.claimText, card.snippet)
        await controller.close()
        XCTAssertTrue(controller.memories.isEmpty)
        XCTAssertEqual(controller.memoryCount, 0)
        await controller.openProfile()
        let response = try await client.command(["command": "current_claim", "claim_key": key])
        let saved = try XCTUnwrap(response["fact"] as? [String: Any])
        XCTAssertEqual(saved["claim_text"] as? String, card.snippet)
        XCTAssertEqual(saved["actor"] as? String, "self")
        await controller.close()
    }
    @MainActor func testSavedMemoryPagingRefreshesAfterSourceRemoval() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let port = PipeProfilePort(python: try ProfileTestEnvironment.python(), repository: root)
        let controller = ProfileController(client: ProfileClient(port: port),
                                           vault: ProfileVault(directory: directory, keys: ReviewPresentationKey()))
        await controller.openProfile()
        for index in 0..<10 {
            await controller.stageEnteredText("I implemented Atlas component \(index).", purpose: "project",
                                              label: "Atlas \(index)", role: "developer", project: "Atlas")
            let card = try XCTUnwrap(controller.card)
            let key = ProfileReviewPresentation.claimKey(sourceID: card.sourceID, factID: card.factID, topic: "")
            await controller.review(card, actor: "self", claimKey: key, replaces: nil)
        }
        XCTAssertEqual(controller.memoryCount, 10)
        XCTAssertEqual(controller.memories.count, 8)
        XCTAssertTrue(controller.canLoadMoreMemories)
        await controller.loadMoreMemories()
        XCTAssertEqual(controller.memories.count, 10)
        XCTAssertEqual(Set(controller.memories.map(\.factID)).count, 10)
        XCTAssertFalse(controller.canLoadMoreMemories)
        let removed = try XCTUnwrap(controller.sources.first)
        await controller.revoke(removed)
        XCTAssertEqual(controller.memoryCount, 9)
        XCTAssertFalse(controller.memories.contains { $0.sourceID == removed.sourceID })
        await controller.close()
    }

    func testMemoryPagesRejectBadOwnershipOrderAndCursorMetadata() throws {
        let fact: [String: Any] = ["fact_id": "fact_a", "claim_key": "atlas.tests", "claim_text": "I wrote Atlas tests.",
                                   "actor": "self", "source_id": "source_a", "source_label": "Atlas"]
        func page(_ facts: [[String: Any]], count: Int, next: Any = NSNull()) throws -> ProfileMemoryPage {
            try JSONDecoder().decode(ProfileMemoryPage.self, from: JSONSerialization.data(withJSONObject:
                ["memories": facts, "total_count": count, "next_after": next]))
        }
        try page([fact], count: 1).validate(after: nil)
        XCTAssertThrowsError(try page([fact, fact], count: 2).validate(after: nil))
        XCTAssertThrowsError(try page([fact], count: 0).validate(after: nil))
        XCTAssertThrowsError(try page([fact], count: 2, next: "fact_other").validate(after: nil))
        XCTAssertThrowsError(try page([fact], count: 1).validate(after: "fact_a"))
        XCTAssertThrowsError(try page([], count: 1).validate(after: nil))
        var unknown = fact; unknown["actor"] = "unknown"
        XCTAssertThrowsError(try page([unknown], count: 1).validate(after: nil))
        var later = fact; later["fact_id"] = "fact_z"
        XCTAssertThrowsError(try page([later, fact], count: 2).validate(after: nil))
        var empty = fact; empty["claim_text"] = ""
        XCTAssertThrowsError(try page([empty], count: 1).validate(after: nil))
    }

}
