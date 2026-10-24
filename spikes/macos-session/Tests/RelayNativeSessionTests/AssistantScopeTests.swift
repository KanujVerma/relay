import Foundation
import XCTest
@testable import RelayNativeSession

private final class AssistantIngressProbe:@unchecked Sendable {
    private let lock=NSLock();private var entries:[String]=[]
    func control(_ value:NativeAssistantScopeRequest){lock.withLock{entries.append(value.action.rawValue+"-\(value.controlSequence)")}}
    func question(_ value:NativeUserQuestionRequest){lock.withLock{entries.append("ask-\(value.anchorEventSequence)")}}
    func cancellation(_ value:NativeAnswerCancelRequest){lock.withLock{entries.append("cancel-\(value.anchorEventSequence)")}}
    var values:[String]{lock.withLock{entries}}
}

final class AssistantScopeTests:XCTestCase {
    func testOpeningCannotIssueUntilItsOriginalOpenCompletes()throws {
        let controller=NativeAssistantSessionController(),probe=AssistantIngressProbe()
        XCTAssertNil(controller.authority.snapshot())
        let opening=try controller.begin(enqueue:probe.control)
        let lease=try XCTUnwrap(controller.authority.snapshot())
        XCTAssertThrowsError(try controller.issueUserQuestion(expectedLease:lease,intent:.ask,question:"Explain queues.",baseRequestID:nil,enqueue:probe.question))
        try controller.completeOpen(opening)
        let question=try controller.issueUserQuestion(expectedLease:lease,intent:.ask,question:"Explain queues.",baseRequestID:nil,enqueue:probe.question)
        XCTAssertEqual(question.anchorEventSequence,1)
        XCTAssertEqual(question.lease.presentationGeneration,2)
        XCTAssertEqual(probe.values,["open-1","ask-1"])
        let json=try JSONSerialization.jsonObject(with:opening.encodedJSON()) as! [String:Any]
        XCTAssertEqual(json.count,9);XCTAssertEqual(json["kind"] as? String,"assistant_scope_request")
        XCTAssertEqual(json["assistantSessionID"] as? String,lease.captureSessionID.uuidString.lowercased())
        XCTAssertNil(json["microphoneEnabled"]);XCTAssertNil(json["payload"])
    }
    func testQuestionAndCancellationUseOnlyTheirOwnCurrentLeaseAndAnchor()throws {
        let controller=NativeAssistantSessionController(),probe=AssistantIngressProbe()
        let opening=try controller.begin(enqueue:probe.control);try controller.completeOpen(opening)
        let lease=try XCTUnwrap(controller.authority.snapshot())
        let question=try controller.issueUserQuestion(expectedLease:lease,intent:.ask,question:"Why?",baseRequestID:nil,enqueue:probe.question)
        XCTAssertThrowsError(try controller.issueAnswerCancellation(expectedLease:question.lease,targetRequestID:UUID(),enqueue:probe.cancellation))
        XCTAssertEqual(controller.authority.snapshot(),question.lease)
        let cancel=try controller.issueAnswerCancellation(expectedLease:question.lease,targetRequestID:question.requestID,enqueue:probe.cancellation)
        XCTAssertEqual(cancel.targetLease,question.lease);XCTAssertEqual(cancel.lease.presentationGeneration,3)
        XCTAssertEqual(cancel.anchorEventSequence,1)
        XCTAssertEqual(probe.values,["open-1","ask-1","cancel-1"])
        XCTAssertThrowsError(try controller.issueAnswerCancellation(expectedLease:cancel.lease,targetRequestID:question.requestID,enqueue:probe.cancellation))
    }
    func testCloseWithdrawsOpeningAndOldTicketsCannotRetireAReplacement()throws {
        let controller=NativeAssistantSessionController(),probe=AssistantIngressProbe()
        let opening=try controller.begin(enqueue:probe.control)
        let close=try XCTUnwrap(controller.beginClose(enqueue:probe.control))
        XCTAssertNil(controller.authority.snapshot())
        XCTAssertThrowsError(try controller.completeOpen(opening))
        XCTAssertThrowsError(try controller.begin(enqueue:probe.control))
        let duplicate=try XCTUnwrap(controller.beginClose(enqueue:probe.control))
        XCTAssertEqual(duplicate,close);XCTAssertEqual(probe.values,["open-1","close-2"])
        try controller.completeClose(close)
        let replacement=try controller.begin(enqueue:probe.control)
        XCTAssertNotEqual(replacement.lease.captureSessionID,opening.lease.captureSessionID)
        XCTAssertThrowsError(try controller.completeClose(close))
        XCTAssertEqual(controller.authority.snapshot(),replacement.lease)
    }
    func testBadTextStaleLeaseAndEnqueueFailureCannotLeaveAuthority()throws {
        let controller=NativeAssistantSessionController()
        let opening=try controller.begin(enqueue:{_ in});try controller.completeOpen(opening)
        let lease=try XCTUnwrap(controller.authority.snapshot())
        for text in ["","two\nlines","hidden\u{200B}text",String(repeating:"🧠",count:126)] {
            XCTAssertThrowsError(try controller.issueUserQuestion(expectedLease:lease,intent:.ask,question:text,baseRequestID:nil,enqueue:{_ in XCTFail()}))
            XCTAssertEqual(controller.authority.snapshot(),lease)
        }
        XCTAssertThrowsError(try controller.issueUserQuestion(expectedLease:lease,intent:.helpCurrent,question:nil,baseRequestID:UUID(),enqueue:{_ in XCTFail()}))
        let question=try controller.issueUserQuestion(expectedLease:lease,intent:.ask,question:"Explain queues.",baseRequestID:nil,enqueue:{_ in})
        XCTAssertThrowsError(try controller.issueUserQuestion(expectedLease:lease,intent:.ask,question:"Stale?",baseRequestID:nil,enqueue:{_ in XCTFail()}))
        XCTAssertEqual(controller.authority.snapshot(),question.lease)
        XCTAssertThrowsError(try controller.issueUserQuestion(expectedLease:question.lease,intent:.ask,question:"Fresh?",baseRequestID:nil,enqueue:{_ in throw NativeSessionError.transportClosed}))
        XCTAssertNil(controller.authority.snapshot())
        XCTAssertThrowsError(try controller.begin(enqueue:{_ in XCTFail()}))
    }
    func testHelpRequiresTheActualLatestQuestionAndCreatesAFreshRequest()throws {
        let controller=NativeAssistantSessionController()
        let opening=try controller.begin(enqueue:{_ in});try controller.completeOpen(opening)
        let first=try controller.issueUserQuestion(expectedLease:try XCTUnwrap(controller.authority.snapshot()),
            intent:.ask,question:"Explain queues.",baseRequestID:nil,enqueue:{_ in})
        let help=try controller.issueUserQuestion(expectedLease:first.lease,intent:.helpCurrent,
            question:nil,baseRequestID:first.requestID,enqueue:{_ in})
        XCTAssertEqual(help.baseRequestID,first.requestID);XCTAssertNil(help.question)
        XCTAssertNotEqual(help.requestID,first.requestID);XCTAssertEqual(help.lease.presentationGeneration,3)
        XCTAssertThrowsError(try controller.issueUserQuestion(expectedLease:help.lease,intent:.helpCurrent,
            question:nil,baseRequestID:first.requestID,enqueue:{_ in XCTFail()}))
        XCTAssertEqual(controller.authority.snapshot(),help.lease)
    }
    func testFailedOpenAndCloseEnqueueWithdrawBeforeReturningTheError()throws {
        let failed=NativeAssistantSessionController()
        XCTAssertThrowsError(try failed.begin(enqueue:{_ in throw NativeSessionError.transportClosed}))
        XCTAssertNil(failed.authority.snapshot());XCTAssertThrowsError(try failed.begin(enqueue:{_ in XCTFail()}))
        let controller=NativeAssistantSessionController()
        let opening=try controller.begin(enqueue:{_ in});try controller.completeOpen(opening)
        XCTAssertThrowsError(try controller.beginClose(enqueue:{_ in
            XCTAssertNil(controller.authority.snapshot())
            throw NativeSessionError.transportClosed
        }))
        XCTAssertNil(controller.authority.snapshot());XCTAssertThrowsError(try controller.begin(enqueue:{_ in XCTFail()}))
    }
}
