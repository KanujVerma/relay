import Foundation
import XCTest
import RelaySessionPanel
import RelayControls
@testable import RelayPanelSession

@MainActor final class ProductRuntimeApplicationTests:XCTestCase {
    private var repository:URL {
        URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    func testBrokenAppCannotStartAHelperFromAnOtherwiseValidRepository()async throws {
        let app=FileManager.default.temporaryDirectory.appendingPathComponent("missing-relay-"+UUID().uuidString+".app")
        let model=SessionApplicationModel(arguments:["Relay","--fixture-suite","coding"],bundleURL:app,workingDirectory:repository)
        XCTAssertFalse(model.canStartSession)
        XCTAssertEqual(model.error,HelperRuntimeError.bundledRuntimeUnavailable.localizedDescription)
        XCTAssertThrowsError(try model.ensureHelper()) { error in
            XCTAssertEqual(error as? HelperRuntimeError,.bundledRuntimeUnavailable)
        }
        await model.start()
        XCTAssertFalse(model.running);XCTAssertNil(model.currentSessionID);XCTAssertNil(model.snapshot.card)
    }
    func testExplicitDeveloperOverrideStillRunsTheRealSyntheticHelperFromAnApp()async throws {
        let app=FileManager.default.temporaryDirectory.appendingPathComponent("missing-relay-"+UUID().uuidString+".app")
        let python=ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"] ?? "/usr/bin/python3"
        let model=SessionApplicationModel(arguments:["Relay","--fixture-suite","coding","--repository",repository.path,"--python",python],bundleURL:app,workingDirectory:URL(fileURLWithPath:"/"))
        XCTAssertTrue(model.canStartSession);XCTAssertNil(model.error)
        XCTAssertEqual(model.root,repository)
        await model.start()
        for _ in 0..<2000 {
            if model.snapshot.card != nil{break}
            try await Task.sleep(for:.milliseconds(2))
        }
        XCTAssertTrue(model.running);XCTAssertNotNil(model.snapshot.card)
        await model.stop()
        XCTAssertFalse(model.running);XCTAssertFalse(model.stopping)
    }
    func testOptInActualBundleRunsItsHelperWithoutDeveloperOverrides()async throws {
        guard let path=ProcessInfo.processInfo.environment["RELAY_BUNDLED_RUNTIME_APP"] else {
            throw XCTSkip("Explicit built-app default-runtime check; no repository/Python fallback or live capture.")
        }
        let app=URL(fileURLWithPath:path,isDirectory:true)
        let model=SessionApplicationModel(arguments:["Relay","--fixture-suite","coding"],bundleURL:app,workingDirectory:URL(fileURLWithPath:"/"))
        addTeardownBlock{await model.stop()}
        XCTAssertNil(model.error);XCTAssertTrue(model.canStartSession)
        guard model.canStartSession else{return}
        XCTAssertTrue(model.root.path.hasPrefix(app.path+"/"))
        await model.start()
        for _ in 0..<5000 {
            if model.snapshot.card != nil || !model.running{break}
            try await Task.sleep(for:.milliseconds(2))
        }
        XCTAssertTrue(model.running);XCTAssertNotNil(model.snapshot.question);XCTAssertNotNil(model.snapshot.card)
        let question="Write a Python function to get the first item or None when a list is empty."
        model.assistant.draft=question;model.assistant.submitDraft()
        for _ in 0..<5000{
            if model.snapshot.question==question,model.snapshot.card != nil{break}
            try await Task.sleep(for:.milliseconds(2))
        }
        XCTAssertEqual(model.snapshot.question,question);XCTAssertNotNil(model.snapshot.card)
        let replacement=model.snapshot.replacement
        try model.perform(.requestHelp)
        for _ in 0..<5000{
            if model.snapshot.replacement>replacement,model.snapshot.card != nil{break}
            try await Task.sleep(for:.milliseconds(2))
        }
        XCTAssertGreaterThan(model.snapshot.replacement,replacement)
        XCTAssertEqual(model.snapshot.question,question);XCTAssertNotNil(model.snapshot.card)
        for technical in ["How does Python implement lists?","How would our team design a feature for nurse handoffs?"]{
            model.assistant.draft=technical;model.assistant.sendDraftAsNewQuestion()
            for _ in 0..<5000{
                if model.snapshot.question==technical,model.snapshot.status != "Thinking"{break}
                try await Task.sleep(for:.milliseconds(2))
            }
            XCTAssertEqual(model.snapshot.question,technical)
            XCTAssertNotNil(model.snapshot.card,"ordinary technical and prospective case-study questions must not require a personal vault")
        }
        XCTAssertEqual(model.assistant.transcript.snapshot.rows.count,1,"typed questions must not become recognized speech")
        await model.stop()
        XCTAssertFalse(model.running);XCTAssertFalse(model.stopping);XCTAssertNil(model.snapshot.card)
    }
}
