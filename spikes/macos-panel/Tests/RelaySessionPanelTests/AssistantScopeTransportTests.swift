import Foundation
import XCTest
import RelayNativeSession
import RelayContextComposition
@testable import RelaySessionPanel

private final class ScopeFailureFlag:@unchecked Sendable {
    private let lock=NSLock();private var value=false
    func mark(){lock.withLock{value=true}}
    var failed:Bool{lock.withLock{value}}
}
private final class ScopeReplies:@unchecked Sendable {
    private let lock=NSLock();private var values:[SessionAnswerDecision]=[]
    func receive(_ data:Data)throws{let value=try SessionAnswerDecision(data:data);lock.withLock{values.append(value)}}
    func terminal(_ id:UUID)->SessionAnswerDecision?{lock.withLock{values.last{$0.requestID==id && $0.disposition != "pending"}}}
}

@MainActor final class AssistantScopeTransportTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func python()throws->URL{URL(fileURLWithPath:try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"]))}
    private func fields(action:String="open")->[String:Any]{
        var value:[String:Any] = ["schemaVersion":1,"kind":"assistant_scope_response","action":action,
            "requestID":"00000000-0000-0000-0000-000000000001","assistantSessionID":"00000000-0000-0000-0000-000000000002",
            "sessionEpoch":1,"presentationGeneration":action=="open" ? 1:2,"controlSequence":action=="open" ? 1:2,
            "status":action=="open" ? "ready":"closed"]
        if action=="close"{value["quiesced"]=true};return value
    }
    func testResponseRequiresExactActionShapeCountersAndGenuineClose()throws {
        let opened=try AssistantScopeResponse(data:JSONSerialization.data(withJSONObject:fields()))
        XCTAssertEqual(opened.action,.open);XCTAssertEqual(opened.status,.ready);XCTAssertNil(opened.quiesced)
        let closed=try AssistantScopeResponse(data:JSONSerialization.data(withJSONObject:fields(action:"close")))
        XCTAssertEqual(closed.status,.closed);XCTAssertEqual(closed.quiesced,true)
        for changes:[String:Any] in [["schemaVersion":true],["action":"capture"],["requestID":"bad"],
            ["sessionEpoch":0],["sessionEpoch":true],["presentationGeneration":1.5],["controlSequence":2],
            ["status":"closed"],["quiesced":true],["authority":true]] {
            var bad=fields();bad.merge(changes){_,new in new}
            XCTAssertThrowsError(try AssistantScopeResponse(data:JSONSerialization.data(withJSONObject:bad)))
        }
        for changes:[String:Any] in [["quiesced":false],["quiesced":1],["status":"ready"],["controlSequence":1]] {
            var bad=fields(action:"close");bad.merge(changes){_,new in new}
            XCTAssertThrowsError(try AssistantScopeResponse(data:JSONSerialization.data(withJSONObject:bad)))
        }
    }
    func testActualReplyBeforeAwaitAndExactReplayKeepOneOwnedResponse()async throws {
        let failed=ScopeFailureFlag()
        let helper=HelperTransport(root:root,python:try python(),mode:.noInference,
            onFrame:{_ in throw PanelBridgeError.malformed},onFailure:failed.mark)
        try helper.start();addTeardownBlock{await helper.shutdownAndWait()}
        let controller=NativeAssistantSessionController()
        let opening=try controller.begin(enqueue:{request in _=try helper.registerAssistantScope(request)})
        let pending=try helper.registerAssistantScope(opening)
        XCTAssertTrue(pending === (try helper.registerAssistantScope(opening)))
        try helper.sendJSON(opening.encodedJSON())
        // The real helper emits these in order. Its later status receipt proves
        // the earlier scope reply was consumed before value() is first awaited.
        _=try await helper.requestVisualInput(.status,onUpdate:{_ in})
        let ready=try await pending.value();XCTAssertEqual(ready.status,.ready)
        try controller.completeOpen(opening)
        let closing=try XCTUnwrap(controller.beginClose(enqueue:{request in _=try helper.registerAssistantScope(request)}))
        let closeResponse=try helper.registerAssistantScope(closing)
        try helper.sendJSON(closing.encodedJSON())
        let closed=try await closeResponse.value();XCTAssertEqual(closed.quiesced,true)
        try controller.completeClose(closing)
        try helper.sendJSON(closing.encodedJSON())
        let again=try controller.begin(enqueue:{request in _=try helper.registerAssistantScope(request)})
        try helper.sendJSON(again.encodedJSON())
        let reopened=try await helper.registerAssistantScope(again).value()
        XCTAssertEqual(reopened.status,.ready);XCTAssertNotEqual(reopened.assistantSessionID,ready.assistantSessionID)
        XCTAssertFalse(failed.failed)
    }
    func testMalformedOrWrongOwnedReplyResolvesOriginalWaiterBeforeRemoval()async throws {
        let script="""
        import json,struct,sys,uuid
        header=sys.stdin.buffer.read(4)
        request=json.loads(sys.stdin.buffer.read(struct.unpack('>I',header)[0]))
        reply={key:request[key] for key in ('schemaVersion','action','requestID','assistantSessionID','sessionEpoch','presentationGeneration','controlSequence')}
        reply.update(kind='assistant_scope_response',status='ready')
        field=sys.argv[1]
        if field in ('requestID','assistantSessionID'):reply[field]=str(uuid.uuid4())
        elif field=='action':reply.update(action='close',status='closed',controlSequence=2,quiesced=True)
        elif field=='scalar':reply=False
        elif field=='schemaVersion':reply[field]=True
        else:reply[field]+=1
        data=json.dumps(reply).encode()
        sys.stdout.buffer.write(struct.pack('>I',len(data))+data);sys.stdout.buffer.flush()
        sys.stdin.buffer.read()
        """
        for field in ["requestID","assistantSessionID","sessionEpoch","presentationGeneration","controlSequence","action","schemaVersion","scalar"] {
            let failed=ScopeFailureFlag()
            let helper=HelperTransport(root:root,python:try python(),pythonArguments:["-u","-c",script,field],mode:.noInference,onFrame:{_ in},onFailure:failed.mark)
            try helper.start()
            let controller=NativeAssistantSessionController()
            let opening=try controller.begin(enqueue:{request in _=try helper.registerAssistantScope(request)})
            let pending=try helper.registerAssistantScope(opening);try helper.sendJSON(opening.encodedJSON())
            let completed=expectation(description:"original waiter rejects \(field)")
            Task{@MainActor in
                defer{completed.fulfill()}
                do{_=try await pending.value();XCTFail("wrong \(field) succeeded")}catch{}
            }
            await fulfillment(of:[completed],timeout:2)
            XCTAssertTrue(failed.failed);XCTAssertThrowsError(try helper.sendJSON(Data("{}".utf8)))
            await helper.shutdownAndWait()
        }
    }
    func testEOFAndOwnedDeadlineFailAndJoinTheirActualChild()async throws {
        let script="""
        import struct,sys
        header=sys.stdin.buffer.read(4)
        sys.stdin.buffer.read(struct.unpack('>I',header)[0])
        if sys.argv[1]=='stall':sys.stdin.buffer.read()
        """
        for mode in ["eof","stall"] {
            let failed=ScopeFailureFlag()
            let helper=HelperTransport(root:root,python:try python(),pythonArguments:["-u","-c",script,mode],mode:.noInference,onFrame:{_ in},onFailure:failed.mark)
            try helper.start()
            let controller=NativeAssistantSessionController(),deadline=DispatchTime.now().uptimeNanoseconds+100_000_000
            let opening=try controller.begin(enqueue:{request in _=try helper.registerAssistantScope(request,deadline:deadline)})
            let pending=try helper.registerAssistantScope(opening);try helper.sendJSON(opening.encodedJSON())
            do{_=try await pending.value();XCTFail("\(mode) falsely acknowledged readiness")}catch{}
            XCTAssertTrue(failed.failed);await helper.shutdownAndWait()
        }
    }
    func testPendingRegistrationBoundAndStopResolveEveryOriginalWaiter()async throws {
        let script="import sys;sys.stdin.buffer.read()"
        let helper=HelperTransport(root:root,python:try python(),pythonArguments:["-u","-c",script],mode:.noInference,onFrame:{_ in},onFailure:{})
        try helper.start()
        var pending:[PendingAssistantScopeResponse]=[]
        for _ in 0..<8 {
            let native=NativeAssistantSessionController()
            let request=try native.begin(enqueue:{request in _=try helper.registerAssistantScope(request)})
            pending.append(try helper.registerAssistantScope(request))
        }
        let ninth=try NativeAssistantSessionController().begin(enqueue:{_ in})
        XCTAssertThrowsError(try helper.registerAssistantScope(ninth))
        helper.stop()
        for response in pending{do{_=try await response.value();XCTFail("Stop lost an owned waiter")}catch{}}
        await helper.shutdownAndWait()
    }
    func testCancelledAwaitStillJoinsActualCloseAndEvictedReplyCannotReregister()async throws {
        let helper=HelperTransport(root:root,python:try python(),mode:.noInference,onFrame:{_ in},onFailure:{})
        try helper.start();addTeardownBlock{await helper.shutdownAndWait()}
        let native=NativeAssistantSessionController()
        var first:NativeAssistantScopeRequest?
        for _ in 0..<6 {
            let opening=try native.begin(enqueue:{request in _=try helper.registerAssistantScope(request)})
            if first==nil{first=opening}
            try helper.sendJSON(opening.encodedJSON())
            _=try await helper.registerAssistantScope(opening).value();try native.completeOpen(opening)
            let closing=try XCTUnwrap(native.beginClose(enqueue:{request in _=try helper.registerAssistantScope(request)}))
            let pending=try helper.registerAssistantScope(closing)
            let waiting=Task{try await pending.value()};waiting.cancel()
            try helper.sendJSON(closing.encodedJSON())
            let closed=try await waiting.value
            XCTAssertTrue(closed.quiesced == true);try native.completeClose(closing)
        }
        XCTAssertThrowsError(try helper.registerAssistantScope(try XCTUnwrap(first)))
    }
    func testActualNoncaptureAskHelpCancellationAndCloseUseOnlyOriginalNativeControls()async throws {
        let replies=ScopeReplies(),failed=ScopeFailureFlag()
        let helper=HelperTransport(root:root,python:try python(),mode:.noInference,onFrame:replies.receive,onFailure:failed.mark)
        try helper.start();addTeardownBlock{await helper.shutdownAndWait()}
        let native=NativeAssistantSessionController()
        let opening=try native.begin(enqueue:{request in _=try helper.registerAssistantScope(request)})
        try helper.sendJSON(opening.encodedJSON())
        _=try await helper.registerAssistantScope(opening).value();try native.completeOpen(opening)
        var current:NativeUserQuestionRequest?
        for (text,reason) in [("What did you personally do on your Atlas project?","personal_context_missing"),
                              ("What is the difference between WHERE and HAVING?","reviewed_full_question")] {
            let request=try native.issueUserQuestion(expectedLease:try XCTUnwrap(native.authority.snapshot()),
                intent:.ask,question:text,baseRequestID:nil,enqueue:{_ in})
            try helper.sendJSON(request.encodedJSON())
            for _ in 0..<2000 where replies.terminal(request.requestID)==nil{try await Task.sleep(for:.milliseconds(1))}
            XCTAssertEqual(replies.terminal(request.requestID)?.reason,reason)
            XCTAssertEqual(request.anchorEventSequence,1);current=request
        }
        let original=try XCTUnwrap(current)
        let binding=PanelRequestBinding(lease:original.lease,requestID:original.requestID,eventSequence:original.anchorEventSequence)
        let help=try native.issueUserQuestion(expectedLease:original.lease,intent:.helpCurrent,question:nil,
            baseRequestID:original.requestID,enqueue:{_ in})
        try helper.sendJSON(binding.retirementJSON());try helper.sendJSON(help.encodedJSON())
        for _ in 0..<2000 where replies.terminal(help.requestID)==nil{try await Task.sleep(for:.milliseconds(1))}
        XCTAssertEqual(replies.terminal(help.requestID)?.disposition,"answer")
        let cancellation=try native.issueAnswerCancellation(expectedLease:help.lease,targetRequestID:help.requestID,
            enqueue:{request in _=try helper.registerAnswerCancellation(request)})
        try helper.sendJSON(cancellation.encodedJSON())
        let cancelled=try await helper.registerAnswerCancellation(cancellation).value();XCTAssertTrue(cancelled.quiesced)
        let closing=try XCTUnwrap(native.beginClose(enqueue:{request in _=try helper.registerAssistantScope(request)}))
        try helper.sendJSON(closing.encodedJSON())
        let closed=try await helper.registerAssistantScope(closing).value();XCTAssertEqual(closed.quiesced,true)
        try native.completeClose(closing);XCTAssertFalse(failed.failed)
    }
}
