import Foundation
import XCTest
import RelaySessionPanel
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
}
