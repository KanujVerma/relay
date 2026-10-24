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
        // A public preference cannot authorize AI without a real connection.
        await model.setAIEnabled(true)
        XCTAssertFalse(model.oauth);XCTAssertFalse(model.running)
        XCTAssertNil(model.account.inferenceSelection)
        XCTAssertEqual(model.account.message,"Connect ChatGPT to use your plan in Relay.")
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

    func testEndCompletesAfterMalformedOrClosedQuiescenceChild() async throws {
        for mode in ["wrong_session","wrong_epoch","closed"] {
            let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-control-response-"+UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            defer { try? FileManager.default.removeItem(at:directory) }
            let launcher=directory.appendingPathComponent("synthetic-helper")
            let script="""
            #!/usr/bin/env python3
            import json,struct,sys,uuid
            mode='\(mode)'
            while True:
                header=sys.stdin.buffer.read(4)
                if not header:break
                request=json.loads(sys.stdin.buffer.read(struct.unpack('>I',header)[0]))
                if request.get('kind')!='session_quiescence_request':continue
                if mode=='closed':break
                reply={**request,'kind':'session_quiescence_response','quiesced':True}
                if mode=='wrong_session':reply['captureSessionID']=str(uuid.uuid4())
                else:reply['sessionEpoch']+=1
                body=json.dumps(reply,separators=(',',':')).encode()
                sys.stdout.buffer.write(struct.pack('>I',len(body))+body)
                sys.stdout.buffer.flush()
            """
            try Data(script.utf8).write(to:launcher)
            try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:launcher.path)
            let model=SessionApplicationModel(arguments:["relay","--fixture-suite","coding","--repository",root.path,"--python",launcher.path])
            await model.start();try await waitUntil{model.snapshot.status=="Thinking"}
            let ended=expectation(description:"actual app End barrier resolves after \(mode)")
            Task { @MainActor in await model.stop();ended.fulfill() }
            await fulfillment(of:[ended],timeout:3)
            XCTAssertFalse(model.running);XCTAssertFalse(model.stopping);XCTAssertFalse(model.canResume)
            XCTAssertNil(model.snapshot.card)
        }
    }

}
