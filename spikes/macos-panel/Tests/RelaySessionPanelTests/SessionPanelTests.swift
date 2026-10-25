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

extension SessionPanelTests {
    @MainActor func test_native_deadline_latches_without_helper_and_old_deadline_cannot_clear_new_card() throws {
        let authority=SessionPresentationAuthority();try authority.start()
        let panel=SessionPanelController(authority:authority);let old=try event(authority)
        panel.observe(old);panel.expire(requestID:old.requestID!)
        XCTAssertFalse(try panel.accept(result(old)))
        authority.invalidate();let next=try event(authority,sequence:9)
        panel.observe(next);XCTAssertTrue(try panel.accept(result(next)))
        panel.expire(requestID:old.requestID!);XCTAssertNotNil(panel.snapshot.card)
    }
}

extension SessionPanelTests {
    @MainActor func test_statement_terminal_clears_immediately_and_never_mints_a_turn() throws {
        let authority=SessionPresentationAuthority();try authority.start();let panel=SessionPanelController(authority:authority)
        let e=try event(authority);panel.observe(e)
        var value=try JSONSerialization.jsonObject(with:result(e,disposition:"abstain")) as! [String:Any]
        value["pythonToken"]=NSNull();value["displayID"]=NSNull();value["question"]="";value["reasonCode"]="no_question"
        XCTAssertTrue(try panel.accept(JSONSerialization.data(withJSONObject:value)))
        XCTAssertEqual(panel.snapshot.status,"Listening");XCTAssertNil(panel.snapshot.card)
        XCTAssertFalse(try panel.accept(result(e)))
        value["disposition"]="answer"
        XCTAssertThrowsError(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value)))
    }
    func test_reviewed_generated_provenance_controls_and_full_uint64() throws {
        let authority=SessionPresentationAuthority();try authority.start();let e=try event(authority,sequence:UInt64.max)
        let valid=try result(e);let decoded=try SessionAnswerDecision(data:valid)
        XCTAssertEqual(decoded.eventSequence,UInt64.max)
        var value=try JSONSerialization.jsonObject(with:valid) as! [String:Any]
        value["answerKind"]="reviewed_reference"
        XCTAssertThrowsError(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value)))
        value["answerKind"]="generated_suggestion";var card=value["card"] as! [String:Any];card["lead"]="safe\u{202e}evil";value["card"]=card
        XCTAssertThrowsError(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value)))
    }
}

extension HelperTransportTests {
    @MainActor func test_profile_preparation_uses_the_same_answer_helper_process() async throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let helper=HelperTransport(root:root,python:URL(fileURLWithPath:"/usr/bin/env"),pythonArguments:["python3"],mode:.fixture,onFrame:{ _ in },onFailure:{})
        try helper.start();defer { helper.stop() }
        let opened=try await helper.requestProfile(Data("{\"command\":\"new\"}".utf8))
        let state=try JSONSerialization.jsonObject(with:opened) as! [String:Any]
        XCTAssertEqual(state["ready"] as? Bool,true)
        _=try await helper.requestProfile(Data("{\"command\":\"lock\"}".utf8))
        let reopened=try await helper.requestProfile(Data("{\"command\":\"new\"}".utf8))
        XCTAssertEqual((try JSONSerialization.jsonObject(with:reopened) as? [String:Any])?["ready"] as? Bool,true)
    }
}

final class HelperFailureGateTests: XCTestCase {
    func test_old_child_failure_cannot_retire_new_session_authority() throws {
        let authority=SessionPresentationAuthority();let gate=HelperFailureGate();let old=UUID(),fresh=UUID()
        gate.activate(old);try authority.start();authority.stop();let current=try authority.start();gate.activate(fresh)
        XCTAssertFalse(gate.withCurrent(old) { authority.stop() })
        XCTAssertEqual(authority.snapshot(),current)
        XCTAssertTrue(gate.withCurrent(fresh) { authority.stop() });XCTAssertNil(authority.snapshot())
    }
}

extension SessionPanelTests {
    @MainActor func test_queued_old_session_stop_cannot_clear_a_restarted_answer() throws {
        let authority=SessionPresentationAuthority();try authority.start();let panel=SessionPanelController(authority:authority)
        let old=try event(authority);panel.observe(old);XCTAssertTrue(try panel.accept(result(old)))
        authority.stop();try authority.start();let fresh=try event(authority);panel.observe(fresh);XCTAssertTrue(try panel.accept(result(fresh)))
        let delayed=NativeSessionEvent(captureSessionID:old.captureSessionID,sessionEpoch:old.sessionEpoch,eventSequence:5,presentationGeneration:old.presentationGeneration,kind:.stopping,sourceCode:nil,streamGeneration:nil,emittedUptimeNanoseconds:5_000_000_000,payload:["reasonCode":.string("user_stop")])
        panel.observe(delayed)
        XCTAssertEqual(panel.snapshot.card?.lead,"Use FIFO ordering.")
    }
}

final class MainDeliveryTests: XCTestCase {
    @MainActor func test_queued_main_actor_frames_have_count_and_byte_budgets() throws {
        let delivery=BoundedMainDelivery<Data>()
        for _ in 0..<16 { try delivery.enqueue(Data(),byteCount:16384) { _ in } }
        XCTAssertThrowsError(try delivery.enqueue(Data(),byteCount:1) { _ in })
        let counted=BoundedMainDelivery<Data>()
        for _ in 0..<32 { try counted.enqueue(Data(),byteCount:1) { _ in } }
        XCTAssertThrowsError(try counted.enqueue(Data(),byteCount:1) { _ in })
    }
}

final class SharedGoldenJSONTests: XCTestCase {
    func test_controller_goldens_preserve_nulls_and_unsigned_native_counters() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data=try Data(contentsOf:root.appendingPathComponent("contracts/session-v1-golden.json"))
        let document=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any]);let cases=try XCTUnwrap(document["cases"] as? [[String:Any]])
        for item in cases {
            for event in try XCTUnwrap(item["events"] as? [[String:Any]]) {
                let encoded=try JSONSerialization.data(withJSONObject:event)
                let fields=try StrictJSON.decode(encoded).object(["schemaVersion","captureSessionID","sessionEpoch","eventSequence","presentationGeneration","requestID","kind","sourceCode","streamGeneration","emittedUptimeNanoseconds","payload"])
                XCTAssertEqual(try fields["schemaVersion"]!.uint(),1)
                _=try fields["sessionEpoch"]!.uint();_=try fields["eventSequence"]!.uint();_=try fields["presentationGeneration"]!.uint()
                if try fields["kind"]!.string()=="eou" {
                    guard case .object(let payload)=fields["payload"]!,case .object(let inner)?=payload["event"] else { return XCTFail("missing exact inner EOU") }
                    XCTAssertEqual(inner.count,13);XCTAssertTrue(inner["confidence"]!.isNull)
                    if try fields["sourceCode"]!.uint()==1 { XCTAssertTrue(fields["requestID"]!.isNull) }
                }
            }
        }
    }
}

import RelayProfile
extension HelperTransportTests {
    @MainActor func test_required_profile_emergency_retires_and_awaits_shared_child() async throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // A real owned child consumes input but never acknowledges a profile command.
        let helper=HelperTransport(root:root,python:URL(fileURLWithPath:"/usr/bin/env"),pythonArguments:["python3","-c","import sys; sys.stdin.buffer.read()"],mode:.noInference,onFrame:{ _ in },onFailure:{})
        try helper.start();let authority=SessionPresentationAuthority();try authority.start()
        let entered=expectation(description:"request entered the shared transport")
        let port=ClosureProfilePort(request:{ data in entered.fulfill();return try await helper.requestProfile(data) },emergencyShutdown:{ authority.stop();await helper.shutdownAndWait() })
        let client=ProfileClient(port:port)
        let request=Task { @MainActor in do { _=try await client.command(["command":"state"]);return false } catch { return true } }
        await fulfillment(of:[entered],timeout:3)
        let outcome=await client.close()
        XCTAssertEqual(outcome,.helperStopped);XCTAssertNil(authority.snapshot())
        let rejected=await request.value;XCTAssertTrue(rejected)
        XCTAssertThrowsError(try helper.start())
        do { _=try await client.command(["command":"new"]);XCTFail("retired client restarted") } catch {}
    }
}

import Darwin
extension HelperTransportTests {
    @MainActor func test_exit_receipt_confirms_shared_child_was_reaped() async throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script="""
        import json,os,struct,sys
        n=struct.unpack('>I',sys.stdin.buffer.read(4))[0]
        request=json.loads(sys.stdin.buffer.read(n))
        body=json.dumps(dict(schemaVersion=1,kind='profile_response',requestID=request['requestID'],payload=dict(ok=True,pid=os.getpid()))).encode()
        sys.stdout.buffer.write(struct.pack('>I',len(body))+body);sys.stdout.buffer.flush()
        sys.stdin.buffer.read()
        """
        let helper=HelperTransport(root:root,python:URL(fileURLWithPath:"/usr/bin/env"),pythonArguments:["python3","-c",script],mode:.noInference,onFrame:{ _ in },onFailure:{})
        try helper.start()
        let response=try await helper.requestProfile(Data("{\"command\":\"state\"}".utf8))
        let fields=try XCTUnwrap(JSONSerialization.jsonObject(with:response) as? [String:Any])
        let pid=try XCTUnwrap(fields["pid"] as? Int32)
        await helper.shutdownAndWait()
        var status:Int32=0;errno=0
        XCTAssertEqual(waitpid(pid,&status,WNOHANG),-1);XCTAssertEqual(errno,ECHILD)
    }
}

extension SessionPanelTests {
    @MainActor func test_task_correction_clarification_has_task_specific_message() throws {
        let authority=SessionPresentationAuthority();try authority.start()
        let panel=SessionPanelController(authority:authority);let e=try event(authority);panel.observe(e)
        var value=try JSONSerialization.jsonObject(with:result(e,disposition:"clarify")) as! [String:Any]
        value["reasonCode"]="task_context_unresolved"
        XCTAssertTrue(try panel.accept(JSONSerialization.data(withJSONObject:value)))
        XCTAssertEqual(panel.snapshot.status,"Clarify the updated task constraint")
        XCTAssertFalse(panel.snapshot.status.contains("background"))
    }
}
