import CryptoKit
import Foundation
import XCTest
@testable import RelayProfile

private struct ResumeReviewKey: ProfileKeyProvider {
    func key(createIfMissing: Bool) throws -> Data { Data(repeating: 37, count: 32) }
}

private actor ResumeRecordingPort: ProfilePort {
    let port: PipeProfilePort
    var decision: Data?
    init(_ port: PipeProfilePort) { self.port = port }
    func request(_ data: Data) async throws -> Data {
        let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if (value?["command"] as? String)?.hasPrefix("decide") == true { decision = data }
        return try await port.request(data)
    }
    func decisionData() -> Data? { decision }
    func close() async { await port.close() }
    func emergencyShutdown() async { await port.emergencyShutdown() }
}

final class ProfileResumeReviewTests: XCTestCase {
    private func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func payload() -> [String: Any] {
        let field = "e\u{301}🧪", snippet = "BSc Computing"
        return ["schema_version": 2, "fact_id": "fact", "source_id": "source", "snippet": snippet,
            "snippet_sha256": hash(snippet), "source_sha256": String(repeating: "1", count: 64),
            "span_start": 20, "span_end": 20+snippet.unicodeScalars.count, "review_revision": 1,
            "actor_hint": "unknown", "card_fingerprint": String(repeating: "2", count: 64),
            "locator": "text:line:2", "claim_kind": "education", "context_sha256": String(repeating: "3", count: 64),
            "review_context": ["section": "education", "entry_id": String(repeating: "a", count: 32),
                "fields": [["kind": "institution", "text": field, "sha256": hash(field),
                            "span_start": 0, "span_end": field.unicodeScalars.count, "locator": "text:line:1"]]]]
    }
    private func decode(_ value: [String: Any]) throws -> ProfileReviewCard {
        try JSONDecoder().decode(ProfileReviewCard.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func field(_ mutate: (inout [String: Any]) -> Void) -> [String: Any] {
        var value = payload(), context = value["review_context"] as! [String: Any]
        var fields = context["fields"] as! [[String: Any]]
        mutate(&fields[0]); context["fields"] = fields; value["review_context"] = context
        return value
    }

    func testUnicodeSourceOffsetsUseCodePointsRatherThanGraphemesOrUTF16() throws {
        let valid = try decode(payload())
        XCTAssertEqual(valid.spanEnd-valid.spanStart, valid.snippet.unicodeScalars.count)
        for count in ["e\u{301}🧪".count, "e\u{301}🧪".utf16.count] {
            XCTAssertThrowsError(try decode(field { $0["span_end"] = count }))
        }
    }

    func testUnknownVersionMissingContextAndUnknownFieldsFailClosed() throws {
        var unknown = payload(); unknown["schema_version"] = 3
        XCTAssertThrowsError(try decode(unknown))
        var missing = payload(); missing.removeValue(forKey: "review_context")
        XCTAssertThrowsError(try decode(missing))
        var extra = payload(); extra["authorized"] = true
        XCTAssertThrowsError(try decode(extra))
        XCTAssertThrowsError(try decode(field { $0["authorized"] = true }))
    }

    func testBadDigestsBoundsDuplicateKindsAndControlTextFailClosed() throws {
        XCTAssertThrowsError(try decode(field { $0["sha256"] = String(repeating: "0", count: 64) }))
        XCTAssertThrowsError(try decode(field { $0["span_start"] = 30_000; $0["span_end"] = 30_003 }))
        XCTAssertThrowsError(try decode(field { $0["span_end"] = true }))
        XCTAssertThrowsError(try decode(field { $0["text"] = "a\n" }))
        var duplicate = payload(), context = duplicate["review_context"] as! [String: Any]
        let fields = context["fields"] as! [[String: Any]]; context["fields"] = fields+fields
        duplicate["review_context"] = context
        XCTAssertThrowsError(try decode(duplicate))
    }

    func testSourceCoverageIsBoundedParserStatusRatherThanApproval() throws {
        let valid: [String: Any] = ["source_id":"source", "label":"Fictional résumé", "purpose":"resume",
            "resume_coverage":["version":2,"unclassified_lines":1,"codes":["ambiguous_entry"]]]
        func source(_ value: [String: Any]) throws -> ProfileSourceSummary {
            try JSONDecoder().decode(ProfileSourceSummary.self, from: JSONSerialization.data(withJSONObject: value))
        }
        XCTAssertEqual(try source(valid).resumeCoverage?.unclassifiedLines, 1)
        for coverage in [["version":true,"unclassified_lines":1,"codes":["line_budget"]],
                         ["version":2,"unclassified_lines":30_001,"codes":[]],
                         ["version":2,"unclassified_lines":1,"codes":["verified"]]] as [[String: Any]] {
            var value = valid; value["resume_coverage"] = coverage
            XCTAssertThrowsError(try source(value))
        }
    }

    @MainActor func testActualControllerSaveSendsDisplayedV2ContextAndProtectedReopenKeepsIt() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pipe = PipeProfilePort(python: try ProfileTestEnvironment.python(), repository: root)
        let port = ResumeRecordingPort(pipe)
        let vault = ProfileVault(directory: directory, keys: ResumeReviewKey())
        let client = ProfileClient(port: port)
        let controller = ProfileController(client: client, vault: vault)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        await controller.openProfile()
        await controller.stageEnteredText("Education\nCe\u{301}dar University | BSc Computing | Expected 2027 | GPA: 3.8/4.0\nCertifications\nFictional Certificate | Fictional Institute | In progress\n",
            purpose: "resume", label: "Fictional résumé", role: "developer", project: nil)
        let displayed = try XCTUnwrap(controller.card)
        let state = try await client.command(["command":"state"])
        var forged = try XCTUnwrap(state["card"] as? [String: Any])
        var context = forged["review_context"] as! [String: Any], fields = context["fields"] as! [[String: Any]]
        fields[fields.count-1]["text"] = "GPA: 4.0/4.0"
        fields[fields.count-1]["sha256"] = hash("GPA: 4.0/4.0")
        context["fields"] = fields; forged["review_context"] = context
        let copied = try decode(forged)
        await controller.review(copied, actor: "self", claimKey: "fiction.education", replaces: nil)
        let noDecision = await port.decisionData()
        XCTAssertNil(noDecision)
        XCTAssertEqual(controller.memoryCount, 0)
        await controller.review(displayed, actor: "self", claimKey: "fiction.education", replaces: nil)
        XCTAssertNil(controller.errorStatus)
        XCTAssertEqual(controller.memoryCount, 1)
        let decisionData = await port.decisionData()
        let decision = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(decisionData)) as? [String: Any])
        XCTAssertEqual(decision["command"] as? String, "decide_v2")
        XCTAssertEqual(decision["card_version"] as? Int, 2)
        XCTAssertNotNil(decision["context_sha256"] as? String)
        XCTAssertEqual(Set(decision.keys), ["command","fact_id","fingerprint","decision","actor","claim_key","replaces_fact_id","card_version","context_sha256"])
        let skipped = try XCTUnwrap(controller.card)
        await controller.reject(skipped)
        XCTAssertNil(controller.errorStatus)
        XCTAssertNil(controller.card)
        let rejectedData = await port.decisionData()
        let rejected = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(rejectedData)) as? [String: Any])
        XCTAssertEqual(rejected["command"] as? String, "decide_v2")
        XCTAssertEqual(rejected["decision"] as? String, "reject")
        XCTAssertTrue(rejected["actor"] is NSNull)
        XCTAssertTrue(rejected["claim_key"] is NSNull)
        XCTAssertTrue(rejected["replaces_fact_id"] is NSNull)
        await controller.close()
        let reopened = ProfileController(client: ProfileClient(port: PipeProfilePort(
            python: try ProfileTestEnvironment.python(), repository: root)), vault: vault)
        _ = await reopened.openExistingProfile()
        XCTAssertEqual(reopened.memories.first?.claimText, "BSc Computing")
        XCTAssertEqual(reopened.memoryCount, 1)
        await reopened.close()
    }
}
