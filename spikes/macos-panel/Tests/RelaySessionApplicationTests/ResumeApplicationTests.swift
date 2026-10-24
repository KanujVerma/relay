import Foundation
import XCTest
import RelayProfile
@testable import RelayPanelSession

@MainActor private final class ResumeAppPreferences: SessionContextUsePreferences {
    var useInSessions = false
}
private struct ResumeAppKey: ProfileKeyProvider {
    func key(createIfMissing: Bool) throws -> Data { Data(repeating: 92, count: 32) }
}

@MainActor final class ResumeApplicationTests: XCTestCase {
    func testReviewedEntryContextRestoresThroughActualSharedHelperAndPersonalPanel() async throws {
        try await run(fileType: nil)
    }
    func testActualSelectedTXTReachesReviewedPersonalPanelAfterFreshRestore() async throws {
        try await run(fileType: "txt")
    }
    func testActualSelectedPDFReachesReviewedPersonalPanelAfterFreshRestore() async throws {
        guard ProcessInfo.processInfo.environment["RELAY_RESUME_DOCUMENT_INTEGRATION"] == "1" else {
            throw XCTSkip("Opt in with the pinned native document environment")
        }
        try await run(fileType: "pdf")
    }
    func testActualSelectedDOCXReachesReviewedPersonalPanelAfterFreshRestore() async throws {
        guard ProcessInfo.processInfo.environment["RELAY_RESUME_DOCUMENT_INTEGRATION"] == "1" else {
            throw XCTSkip("Opt in with the pinned native document environment")
        }
        try await run(fileType: "docx")
    }

    private func run(fileType: String?) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("relay-resume-app-"+UUID().uuidString)
        let preferences = ResumeAppPreferences()
        let python = try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])
        let model = SessionApplicationModel(arguments: ["relay","--repository",root.path,"--python",python,
            "--fixture-suite","personal-memory"], contextPreferences: preferences,
            profileVaultFactory: { ProfileVault(directory: directory, keys: ResumeAppKey()) })
        addTeardownBlock { await model.stop(); try? FileManager.default.removeItem(at: directory) }
        XCTAssertFalse(preferences.useInSessions)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        model.openMyContext(); await model.contextUse.waitForQuiescence()
        XCTAssertTrue(preferences.useInSessions)
        if let fileType {
            let url = root.appendingPathComponent("tests/fixtures/resume-coverage/fictional-linear."+fileType)
            await model.profile.stageSelectedFile(url, purpose: "resume", label: "Fictional résumé", role: model.role, project: nil)
        } else {
            await model.profile.stageEnteredText("Projects\nFictional Northstar | Expected 2027\n- I implemented validation tests using R.\n",
                purpose: "resume", label: "Fictional résumé", role: model.role, project: nil)
        }
        var approved = 0, foundContribution = false
        while let displayed = model.profile.card {
            XCTAssertEqual(displayed.schemaVersion, 2)
            if displayed.snippet == "I implemented validation tests using R." {
                foundContribution = true
                XCTAssertEqual(displayed.claimKind, "contribution")
                XCTAssertEqual(displayed.reviewContext?.fields.filter { $0.kind == "date" }.map(\.text), ["Expected 2027"])
            }
            let actor = displayed.actorHint == "unknown" ? "self" : displayed.actorHint
            await model.profile.review(displayed, actor: actor, claimKey: "fiction."+displayed.factID, replaces: nil)
            XCTAssertNil(model.profile.errorStatus)
            approved += 1
            guard approved <= 64, model.profile.errorStatus == nil else { throw NSError(domain: "Synthetic review failed", code: 2) }
        }
        XCTAssertTrue(foundContribution)
        XCTAssertGreaterThanOrEqual(approved, 2)
        XCTAssertEqual(model.profile.memoryCount, approved)
        let oldProfile = model.profile, oldHelper = try model.ensureHelper()
        let ciphertext = try Data(contentsOf: directory.appendingPathComponent("profile.relayvault"))
        XCTAssertNil(ciphertext.range(of: Data("Expected 2027".utf8)))
        await model.stop(); XCTAssertTrue(preferences.useInSessions)
        await model.start()
        try await waitUntil { model.snapshot.card != nil }
        XCTAssertTrue(model.running)
        XCTAssertFalse(model.profile === oldProfile)
        XCTAssertFalse(try model.ensureHelper() === oldHelper)
        XCTAssertEqual(model.snapshot.question, "What did you personally do on your Fictional Northstar project?")
        XCTAssertEqual(model.snapshot.card?.points, ["Your contribution: I implemented validation tests using R.; Fictional Northstar; Expected 2027"])
        model.lockMyContext()
        XCTAssertNil(model.snapshot.card); XCTAssertFalse(preferences.useInSessions)
        await model.contextUse.waitForQuiescence(); await model.stop(); await model.start()
        try await waitUntil { model.snapshot.question != nil && model.snapshot.status != "Thinking" }
        XCTAssertNil(model.snapshot.card)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<2000 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw NSError(domain: "Synthetic résumé app did not reach its actual receipt", code: 1)
    }
}
