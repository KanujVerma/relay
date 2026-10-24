import Foundation
import XCTest
import RelayNativeSession
@testable import RelaySessionPanel

extension SessionPanelTests {
    @MainActor func test_response_preferences_provenance_requires_one_exact_optional_uuid()async throws {
        let authority=SessionPresentationAuthority();try authority.start()
        let native=try event(authority),revision=UUID()
        var value=try XCTUnwrap(JSONSerialization.jsonObject(with:result(native)) as? [String:Any])
        XCTAssertNil(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value)).responsePreferencesRevision)
        var provenance=try XCTUnwrap(value["provenance"] as? [String:Any])
        provenance["responsePreferencesRevision"]=revision.uuidString.lowercased();value["provenance"]=provenance
        XCTAssertEqual(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value)).responsePreferencesRevision,revision)
        for invalid in [NSNull(),true,7,"not-a-uuid",revision.uuidString+"x"] as [Any]{
            var bad=provenance;bad["responsePreferencesRevision"]=invalid;value["provenance"]=bad
            XCTAssertThrowsError(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value)))
        }
        provenance["preferenceAuthority"]=true;value["provenance"]=provenance
        XCTAssertThrowsError(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value)))
    }
    @MainActor func test_response_preferences_use_can_coexist_with_original_ocr_image_metadata()async throws {
        let authority=SessionPresentationAuthority();try authority.start()
        let native=try event(authority),revision=UUID()
        var value=try XCTUnwrap(JSONSerialization.jsonObject(with:result(native)) as? [String:Any])
        var provenance=try XCTUnwrap(value["provenance"] as? [String:Any])
        provenance["responsePreferencesRevision"]=revision.uuidString.lowercased()
        provenance["taskContext"]=["provenance":"local_ocr","source":"Synthetic selected editor","capturedUptimeNanoseconds":1,"imageDigest":String(repeating:"a",count:64)] as [String:Any]
        value["provenance"]=provenance
        let parsed=try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value))
        XCTAssertEqual(parsed.responsePreferencesRevision,revision)
        XCTAssertEqual(parsed.taskContext?.imageDigest,String(repeating:"a",count:64))
        value["answerKind"]="reviewed_reference"
        value["provenance"]=["referenceID":"reviewed-fixture","sourceRef":"public-fixture","responsePreferencesRevision":revision.uuidString.lowercased()]
        XCTAssertThrowsError(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value)))
        value["answerKind"]="generated_suggestion"
        value["provenance"]=["personal":true,"contextRevision":"revision","facts":[["factID":"f","sourceID":"s","actor":"self","revision":1]],"checks":["host_exact_approved_facts"],"responsePreferencesRevision":revision.uuidString.lowercased()] as [String:Any]
        XCTAssertThrowsError(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value)))
    }
}

private final class PreferenceWireReplies:@unchecked Sendable {
    private let lock=NSLock();private var values:[SessionAnswerDecision]=[]
    func receive(_ data:Data)throws{let value=try SessionAnswerDecision(data:data);lock.withLock{values.append(value)}}
    func terminal(_ id:UUID)->SessionAnswerDecision?{lock.withLock{values.last{$0.requestID==id && $0.disposition != "pending"}}}
}
extension SessionPanelTests {
    @MainActor func test_response_preferences_actual_private_native_request_round_trips_one_helper()async throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let replies=PreferenceWireReplies(),revision=UUID(),controller=NativeAssistantSessionController()
        let helper=HelperTransport(root:root,python:URL(fileURLWithPath:try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])),mode:.fixture,role:"developer",onFrame:replies.receive,onFailure:{})
        try helper.start();addTeardownBlock{controller.authority.stop();await helper.shutdownAndWait()}
        let opening=try controller.begin(enqueue:{request in
            _=try helper.registerAssistantScope(request);try helper.sendJSON(request.encodedJSON())
        })
        let opened=try await helper.registerAssistantScope(opening).value();XCTAssertEqual(opened.status,.ready)
        try controller.completeOpen(opening)
        let issued=try controller.issueUserQuestion(expectedLease:try XCTUnwrap(controller.authority.snapshot()),intent:.ask,
            question:"Explain event loops.",baseRequestID:nil,enqueue:{request in
                let staged:[String:Any] = ["schemaVersion":1,"kind":"response_preferences",
                    "captureSessionID":request.lease.captureSessionID.uuidString.lowercased(),"sessionEpoch":request.lease.sessionEpoch,
                    "presentationGeneration":request.lease.presentationGeneration,"requestID":request.requestID.uuidString.lowercased(),
                    "eventSequence":request.anchorEventSequence,"preferencesRevision":revision.uuidString.lowercased(),
                    "focus":"coding","guidance":"Prefer concise invariants."]
                try helper.sendJSON(JSONSerialization.data(withJSONObject:staged));try helper.sendJSON(request.encodedJSON())
            })
        for _ in 0..<2000{if replies.terminal(issued.requestID) != nil{break};try await Task.sleep(for:.milliseconds(2))}
        let answer=try XCTUnwrap(replies.terminal(issued.requestID))
        XCTAssertEqual(answer.disposition,"answer");XCTAssertEqual(answer.responsePreferencesRevision,revision)
        XCTAssertEqual(answer.sessionID,issued.lease.captureSessionID);XCTAssertEqual(answer.epoch,issued.lease.sessionEpoch)
        XCTAssertEqual(answer.generation,issued.lease.presentationGeneration);XCTAssertEqual(answer.eventSequence,issued.anchorEventSequence)
        XCTAssertEqual(issued.anchorEventSequence,1);XCTAssertEqual(issued.lease.presentationGeneration,2)
        let closing=try XCTUnwrap(controller.beginClose(enqueue:{request in
            _=try helper.registerAssistantScope(request);try helper.sendJSON(request.encodedJSON())
        }))
        let closed=try await helper.registerAssistantScope(closing).value();XCTAssertEqual(closed.quiesced,true)
        try controller.completeClose(closing)
        await helper.shutdownAndWait()
    }
}
