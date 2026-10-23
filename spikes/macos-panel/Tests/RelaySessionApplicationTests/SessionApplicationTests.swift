import Foundation
import XCTest
import RelayControls
import RelayNativeSession
import RelayContextComposition
@testable import RelayPanelSession

@MainActor final class SessionApplicationTests:XCTestCase {
    private var root:URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private func waitUntil(_ predicate:()->Bool) async throws {
        for _ in 0..<1000 { if predicate(){return};try await Task.sleep(for:.milliseconds(5)) }
        XCTFail("synthetic app flow did not complete")
    }
    func testDefaultModelIsIdleWithOptionalCaptureKeysAndAIRequestsOff() async {
        let model=SessionApplicationModel(arguments:["relay","--repository",root.path])
        XCTAssertFalse(model.running);XCTAssertFalse(model.starting);XCTAssertFalse(model.oauth)
        XCTAssertFalse(model.screen.isEnabled);XCTAssertFalse(model.selectedText.isEnabled)
        XCTAssertFalse(model.controls.isEnabled);XCTAssertTrue(model.controls.shortcuts.isEmpty)
        XCTAssertNil(model.snapshot.card)
        // Mode selection itself performs no sign-in, capture or inference.
        await model.setAIEnabled(true)
        XCTAssertTrue(model.oauth);XCTAssertFalse(model.running)
        await model.setAIEnabled(false)
        XCTAssertFalse(model.oauth)
    }
    func testActualSingleHelperFixturePauseResumeManualHelpAndEnd() async throws {
        let model=SessionApplicationModel(arguments:["relay","--fixture-suite","coding","--repository",root.path])
        await model.start();try await waitUntil{model.snapshot.card != nil}
        XCTAssertTrue(model.running);XCTAssertTrue(model.snapshot.card?.detail?.text.contains("return items[0]") == true)
        let oldSession=try XCTUnwrap(model.currentSessionID)
        try model.perform(.pause)
        // The synchronous control returns only after actual source and display
        // admission retirement. The actual helper ack/capture join follows.
        XCTAssertFalse(model.running);XCTAssertTrue(model.paused);XCTAssertNil(model.snapshot.card)
        XCTAssertFalse(model.canResume)
        try await waitUntil{!model.stopping}
        XCTAssertTrue(model.canResume)
        await model.start();try await waitUntil{model.snapshot.card != nil}
        XCTAssertTrue(model.running);XCTAssertFalse(model.paused)
        let newSession=try XCTUnwrap(model.currentSessionID);XCTAssertNotEqual(oldSession,newSession)
        let oldStop=NativeSessionEvent(captureSessionID:oldSession,sessionEpoch:1,eventSequence:99,presentationGeneration:99,kind:.stopped,sourceCode:nil,streamGeneration:nil,emittedUptimeNanoseconds:1,payload:["reasonCode":.string("user_stop"),"quiesced":.bool(true)])
        model.receive(.audio(oldStop))
        XCTAssertTrue(model.running);XCTAssertNotNil(model.snapshot.card)
        let before=model.snapshot.replacement
        try model.perform(.requestHelp)
        try await waitUntil{model.snapshot.replacement>before && model.snapshot.card != nil}
        XCTAssertTrue(model.running);XCTAssertNil(model.error)
        await model.stop()
        XCTAssertFalse(model.running);XCTAssertFalse(model.stopping);XCTAssertFalse(model.paused)
        XCTAssertFalse(model.canResume);XCTAssertNil(model.snapshot.card)
    }
    func testActualSyntheticSourceFaultEndsAndJoinsTheCurrentAppSession() async throws {
        let model=SessionApplicationModel(arguments:["relay","--fixture-suite","source-failure","--repository",root.path])
        await model.start()
        try await waitUntil{!model.running && !model.stopping}
        XCTAssertFalse(model.paused);XCTAssertFalse(model.canResume)
        XCTAssertNil(model.snapshot.card);XCTAssertNotNil(model.error)
        await model.stop()
    }

}
