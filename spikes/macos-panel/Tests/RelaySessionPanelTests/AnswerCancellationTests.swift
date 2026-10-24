import Foundation
import XCTest
import RelayNativeSession
import RelayContextComposition
@testable import RelaySessionPanel

final class AnswerCancellationTests:XCTestCase {
    @MainActor func testMismatchedOwnedReceiptResolvesTheOriginalWaiterWithError()async throws {
        let script="""
        import json,struct,sys,uuid
        size=struct.unpack('>I',sys.stdin.buffer.read(4))[0]
        request=json.loads(sys.stdin.buffer.read(size))
        reply={key:request[key] for key in ('captureSessionID','sessionEpoch','presentationGeneration','requestID','targetRequestID')}
        reply.update(schemaVersion=1,kind='answer_cancel_response',resultRevision=2,reasonCode='request_cancelled',quiesced=True)
        reply[sys.argv[1]]=str(uuid.uuid4())
        body=json.dumps(reply).encode()
        sys.stdout.buffer.write(struct.pack('>I',len(body))+body)
        sys.stdout.buffer.flush()
        sys.stdin.buffer.read()
        """
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let python=try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])
        for field in ["targetRequestID","captureSessionID"] {
            let helper=HelperTransport(root:root,python:URL(fileURLWithPath:python),
                pythonArguments:["-u","-c",script,field],mode:.noInference,onFrame:{_ in},onFailure:{})
            try helper.start()
            let native=NativeSessionController(onEvent:{_ in})
            try native.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,
                components:[2:SourceComponents(vad:CancelQuietVAD(),recognizer:CancelQuietRecognizer())])
            let request=try native.issueUserQuestion(expectedLease:try XCTUnwrap(native.authority.snapshot()),intent:.ask,
                question:"Explain event loops.",baseRequestID:nil,enqueue:{_ in})
            let cancellation=try native.issueAnswerCancellation(expectedLease:request.lease,targetRequestID:request.requestID,enqueue:{_ in})
            let pending=try helper.registerAnswerCancellation(cancellation)
            XCTAssertTrue(pending === (try helper.registerAnswerCancellation(cancellation)))
            try helper.sendJSON(cancellation.encodedJSON())
            let resolved=expectation(description:"owned waiter rejects wrong \(field)")
            Task{@MainActor in
                defer{resolved.fulfill()}
                do{_=try await pending.value();XCTFail("wrong identity succeeded")}
                catch{}
            }
            await fulfillment(of:[resolved],timeout:2)
            XCTAssertThrowsError(try helper.sendJSON(Data("{}".utf8)))
            native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
            await helper.shutdownAndWait()
        }
    }
    func testReceiptRequiresExactTargetIdentityAndActualQuiescence()throws {
        let value:[String:Any]=["schemaVersion":1,"kind":"answer_cancel_response",
            "captureSessionID":"00000000-0000-0000-0000-000000000001","sessionEpoch":1,
            "presentationGeneration":3,"requestID":"00000000-0000-0000-0000-000000000002",
            "targetRequestID":"00000000-0000-0000-0000-000000000003","resultRevision":2,
            "reasonCode":"request_cancelled","quiesced":true]
        let response=try AnswerCancellationResponse(data:JSONSerialization.data(withJSONObject:value))
        XCTAssertTrue(response.quiesced)
        for fields:[String:Any] in [["quiesced":false],["sessionEpoch":true],["resultRevision":1],
            ["reasonCode":"private provider prose"],["targetRequestID":"bad"],["authority":true]] {
            var bad=value;bad.merge(fields){_,new in new}
            XCTAssertThrowsError(try AnswerCancellationResponse(data:JSONSerialization.data(withJSONObject:bad)))
        }
    }
    @MainActor func testActualHelperDenialPrecedesHeldTypedRequestAndCancellationReceipt()async throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:directory)}
        let log=directory.appendingPathComponent("requests.jsonl")
        let python=try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])
        let helper=HelperTransport(root:root,python:URL(fileURLWithPath:python),
            pythonArguments:[root.appendingPathComponent("tests/support/visual_backend_helper.py").path,
                "--synthetic-visual-test","--log",log.path],mode:.oauth,
            onFrame:{_ in},onFailure:{})
        try helper.start()
        addTeardownBlock{await helper.shutdownAndWait()}
        _=try await helper.requestVisualInput(.status,onUpdate:{_ in})
        let native=NativeSessionController(onEvent:{try helper.send($0)})
        try native.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,
            components:[2:SourceComponents(vad:CancelQuietVAD(),recognizer:CancelQuietRecognizer())])
        let request=try native.issueUserQuestion(expectedLease:try XCTUnwrap(native.authority.snapshot()),intent:.ask,
            question:"Explain event loops.",baseRequestID:nil,enqueue:{_ in})
        let target=PanelRequestBinding(lease:request.lease,requestID:request.requestID,eventSequence:request.anchorEventSequence)
        let latch=CancellationCaptureLatch()
        let explicit=ExplicitContextForwardingPorts(shouldCapture:{_ in true},capture:{_ in await latch.capture()},
            retire:{try helper.sendJSON($0.retirementJSON())},sendQuestion:{value,_ in
                try helper.sendJSON(value.encodedJSON())
                // Force the child to process the released frame BEFORE Cancel
                // is enqueued. Without deny-before-release this produces a POST.
                Thread.sleep(forTimeInterval:0.15)
            },sendCancellation:{try helper.sendJSON($0.encodedJSON())})
        let pump=OrderedContextForwarder(shouldCapture:{_ in false},capture:{_ in []},send:{_,_ in},onFailure:{},explicit:explicit)
        try pump.enqueueUserQuestion(request)
        for _ in 0..<30 where !latch.entered{await Task.yield()}
        XCTAssertTrue(latch.entered)
        let cancellation=try native.issueAnswerCancellation(expectedLease:request.lease,targetRequestID:request.requestID,enqueue:{_ in})
        let pending=try helper.registerAnswerCancellation(cancellation)
        try pump.enqueueAnswerCancellation(cancellation,retiring:target)
        let response=try await pending.value()
        XCTAssertTrue(response.quiesced);XCTAssertEqual(response.targetRequestID,request.requestID)
        let content=(try? String(contentsOf:log,encoding:.utf8)) ?? ""
        XCTAssertFalse(content.contains("text_question"));XCTAssertFalse(content.contains("image_question"))
        latch.finish();native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
        await helper.shutdownAndWait()
    }
}

private actor CancelQuietVAD:SpeechActivityDetector {
    nonisolated let chunkSamples=512
    func accept(_ samples:[Float])async throws->[SpeechBoundary]{[]}
}
private actor CancelQuietRecognizer:ActivityRecognizer {
    func recognize(_ samples:[Float])async throws->String{"Explain queues."}
}
@MainActor private final class CancellationCaptureLatch {
    var entered=false;private var continuation:CheckedContinuation<[Data],Never>?
    func capture()async->[Data]{entered=true;return await withCheckedContinuation{continuation=$0}}
    func finish(){continuation?.resume(returning:[]);continuation=nil}
}
