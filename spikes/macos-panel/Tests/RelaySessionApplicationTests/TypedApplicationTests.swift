import Foundation
import XCTest
import RelayControls
import RelaySessionPanel
@testable import RelayPanelSession

@MainActor final class TypedApplicationTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func waitUntil(_ predicate:()->Bool)async throws {
        for _ in 0..<1500{if predicate(){return};try await Task.sleep(for:.milliseconds(3))}
        throw NSError(domain:"Synthetic typed app timeout",code:1)
    }
    func testActualTypedSendHelpDraftBasisAndTranscriptLifecycle()async throws {
        let model=SessionApplicationModel(arguments:["Relay","--fixture-suite","coding","--repository",root.path])
        XCTAssertFalse(model.assistant.snapshot.canSend)
        XCTAssertTrue(model.assistant.transcript.snapshot.rows.isEmpty)
        await model.start()
        do {
            try await waitUntil{model.snapshot.card != nil}
            XCTAssertEqual(model.assistant.transcript.snapshot.rows.count,1)
            let original=try XCTUnwrap(model.snapshot.question)
            let typedQuestion="Write a Python function to get the first item or None when a list is empty."
            model.assistant.draft=typedQuestion
            XCTAssertEqual(model.assistant.snapshot.basis?.question,original)
            XCTAssertTrue(model.assistant.snapshot.canSend)
            model.assistant.sendDraftAsNewQuestion()
            XCTAssertTrue(model.assistant.draft.isEmpty)
            try await waitUntil{model.snapshot.question==typedQuestion && model.snapshot.card != nil}
            let before=model.snapshot.replacement
            try model.perform(.requestHelp)
            try await waitUntil{model.snapshot.replacement>before && model.snapshot.status != "Thinking"}
            XCTAssertEqual(model.snapshot.question,typedQuestion)
            XCTAssertNotNil(model.snapshot.card)
            XCTAssertTrue(model.running)
            XCTAssertNil(model.error)
            // A draft remains tied to the visible original until explicitly changed.
            model.assistant.draft="Explain queue scheduling."
            XCTAssertEqual(model.assistant.snapshot.basis?.question,typedQuestion)
            try model.perform(.pause)
            XCTAssertFalse(model.assistant.snapshot.canSend)
            XCTAssertEqual(model.assistant.transcript.snapshot.rows.count,1)
            XCTAssertEqual(model.assistant.transcript.snapshot.phase,.paused)
            try await waitUntil{!model.stopping}
            await model.start()
            try await waitUntil{model.snapshot.card != nil}
            XCTAssertEqual(model.assistant.snapshot.basisState,.unavailable)
            XCTAssertEqual(model.assistant.draft,"Explain queue scheduling.")
            model.assistant.sendDraftAsNewQuestion()
            try await waitUntil{model.snapshot.question=="Explain queue scheduling." && model.snapshot.status != "Thinking"}
            XCTAssertTrue(model.assistant.draft.isEmpty)
            await model.stop()
            XCTAssertTrue(model.assistant.transcript.snapshot.rows.isEmpty)
            XCTAssertFalse(model.assistant.snapshot.canSend)
        }catch{await model.stop();throw error}
    }
}
