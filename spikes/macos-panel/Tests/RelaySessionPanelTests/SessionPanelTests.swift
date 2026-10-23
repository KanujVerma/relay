import XCTest
import Foundation
import RelayNativeSession
@testable import RelaySessionPanel

final class SessionPanelTests: XCTestCase {
    func event(_ authority: SessionPresentationAuthority, sequence: UInt64 = 4, request: UUID = UUID()) throws -> NativeSessionEvent {
        let lease = try XCTUnwrap(authority.snapshot())
        return NativeSessionEvent(captureSessionID: lease.captureSessionID, sessionEpoch: lease.sessionEpoch,
            eventSequence: sequence, presentationGeneration: lease.presentationGeneration, kind: .eou,
            sourceCode: 2, streamGeneration: 1, emittedUptimeNanoseconds: 4_000_000_000, payload: [:], requestID: request)
    }
    func result(_ event: NativeSessionEvent, disposition: String = "answer", revision: Int = 2) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "captureSessionID": event.captureSessionID.uuidString.lowercased(), "sessionEpoch": event.sessionEpoch,
            "eventSequence": event.eventSequence, "presentationGeneration": event.presentationGeneration,
            "requestID": event.requestID!.uuidString.lowercased(), "resultRevision": revision,
            "disposition": disposition, "reasonCode": disposition == "answer" ? "format_checked" : "answer_timeout",
            "pythonToken": ["turnID":"remote:1:activity-2-1-1","version":1,"generation":5],
            "displayID":"opaque-id", "question":"Explain queues.", "answerID": disposition == "answer" ? "answer-id" : NSNull(),
            "answerKind": disposition == "answer" ? "generated_suggestion" : NSNull(),
            "card": disposition == "answer" ? ["lead":"Use FIFO ordering.","points":[],"detail":["kind":"code","language":"python","text":"def first(items):\n    return items[0]\n"]] : NSNull(),
            "provenance": disposition == "answer" ? ["model":"fixture","checks":["format_checked","python_syntax_checked"],"independentlyReviewed":false] : NSNull()
        ] as [String:Any], options: [.sortedKeys])
    }
    @MainActor func test_actual_commit_rechecks_retired_native_lease() throws {
        let authority=SessionPresentationAuthority();try authority.start()
        let panel=SessionPanelController(authority:authority);let e=try event(authority)
        panel.observe(e);let delayed=try result(e)
        authority.invalidate()
        XCTAssertFalse(try panel.accept(delayed));XCTAssertNil(panel.snapshot.card)
    }
    @MainActor func test_terminal_error_seals_and_old_error_cannot_clear_new_answer() throws {
        let authority=SessionPresentationAuthority();try authority.start()
        let panel=SessionPanelController(authority:authority);let old=try event(authority)
        panel.observe(old);XCTAssertTrue(try panel.accept(result(old,disposition:"error")))
        XCTAssertFalse(try panel.accept(result(old)))
        authority.invalidate();let fresh=try event(authority,sequence:8)
        panel.observe(fresh);XCTAssertTrue(try panel.accept(result(fresh)))
        XCTAssertFalse(try panel.accept(result(old,disposition:"error")))
        XCTAssertEqual(panel.snapshot.card?.lead,"Use FIFO ordering.")
        XCTAssertEqual(panel.snapshot.card?.detail?.text,"def first(items):\n    return items[0]\n")
    }
    func test_duplicate_json_and_oversize_code_rejected() throws {
        XCTAssertThrowsError(try StrictJSON.decode(Data("{\"x\":1,\"x\":2}".utf8)))
        XCTAssertThrowsError(try StrictJSON.decode(Data(repeating:32,count:16385)))
        let decoder=AnswerFrameDecoder()
        XCTAssertThrowsError(try decoder.feed(Data([0,0,64,1])))
    }
}

final class HelperTransportTests: XCTestCase {
    func test_real_python_child_delivers_an_actual_reviewed_card() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let answered=expectation(description:"actual helper reviewed answer")
        let helper=HelperTransport(root:root,python:URL(fileURLWithPath:"/usr/bin/env"),pythonArguments:["python3"],mode:.fixture,onFrame:{ data in
            if let d=try? SessionAnswerDecision(data:data),d.disposition=="answer",d.answerKind=="reviewed_reference" { answered.fulfill() }
        },onFailure:{})
        try helper.start()
        let session=UUID().uuidString.lowercased();let request=UUID().uuidString.lowercased()
        let tb:[String:Any]=["hostTicksAtAnchor":0,"uptimeNsAtAnchor":0,"nsNumer":1,"nsDenom":1]
        func send(_ kind:String,_ seq:Int,_ source:Any=NSNull(),_ payload:[String:Any],requestID:Any=NSNull()) throws {
            let value:[String:Any]=["schemaVersion":1,"captureSessionID":session,"sessionEpoch":1,"eventSequence":seq,"presentationGeneration":kind=="session_started" ? 1:2,"kind":kind,"sourceCode":source,"streamGeneration":source is NSNull ? NSNull():1,"emittedUptimeNanoseconds":seq*1_000_000_000,"payload":payload,"requestID":requestID]
            try helper.sendJSON(JSONSerialization.data(withJSONObject:value))
        }
        try send("session_started",1,NSNull(),["selectedBundleID":"synthetic.fixture","microphoneEnabled":false])
        try send("speech_started",2,2,["activityID":1,"startHostTime":2_000_000_000,"detectedUptimeNanoseconds":2_000_000_000,"timebase":tb])
        try send("speech_ended",3,2,["activityID":1,"endHostTime":3_000_000_000,"lastSpeechInputSequence":3,"timebase":tb])
        let inner:[String:Any]=["version":1,"status":"final","sourceCode":2,"streamGeneration":1,"segmentID":4,"revision":1,"startHostTime":2_000_000_000,"endHostTime":3_000_000_000,"finalizedUptimeNanoseconds":4_000_000_000,"receivedUptimeNanoseconds":4_000_000_000,"text":"What is the difference between WHERE and HAVING?","confidence":NSNull(),"timebase":tb]
        try send("eou",4,2,["event":inner,"activityID":1,"firstInputSequence":2,"lastInputSequence":3,"activityClosed":true,"lastSpeechInputSequence":3],requestID:request)
        wait(for:[answered],timeout:4);helper.stop()
    }
}
