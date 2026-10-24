import Foundation
import XCTest
import RelayNativeSession
import RelayContextComposition
@testable import RelaySessionPanel

private actor DraftQuietVAD:SpeechActivityDetector {
    nonisolated let chunkSamples=512
    func accept(_ samples:[Float])async throws->[SpeechBoundary]{[]}
}
private actor DraftQuietRecognizer:ActivityRecognizer {
    func recognize(_ samples:[Float])async throws->String{"Explain queues."}
}
@MainActor private final class DraftPortState {
    var current:PanelRequestBinding?
    var sent:[NativeUserQuestionRequest]=[]
    var reads=0
}
@MainActor private final class DraftCancelGate {
    var entered=false;private var continuation:CheckedContinuation<Void,Never>?
    func wait()async{entered=true;await withCheckedContinuation{continuation=$0}}
    func release(){continuation?.resume();continuation=nil}
}
@MainActor final class TypedAssistantTests:XCTestCase {
    private func native()throws->NativeSessionController {
        let native=NativeSessionController(onEvent:{_ in})
        try native.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,
            components:[2:SourceComponents(vad:DraftQuietVAD(),recognizer:DraftQuietRecognizer())])
        return native
    }
    private func binding(_ value:NativeUserQuestionRequest)->PanelRequestBinding {
        PanelRequestBinding(lease:value.lease,requestID:value.requestID,eventSequence:value.anchorEventSequence)
    }
    private func model(_ native:NativeSessionController,_ port:DraftPortState,
                       cancel:@escaping(PanelRequestBinding)async throws->AnswerCancellationResponse = {_ in throw PanelBridgeError.closed})->TypedAssistantController {
        TypedAssistantController(session:{port.reads+=1;return native.authority.snapshot()},currentRequest:{port.current},
            issue:{intent,text,basis in
                let request=try native.issueUserQuestion(expectedLease:try XCTUnwrap(native.authority.snapshot()),intent:intent,
                    question:text,baseRequestID:basis,enqueue:{_ in})
                port.sent.append(request);port.current=self.binding(request);return request
            },cancel:cancel)
    }
    func testDraftKeepsOriginalReadOnlyBasisAcrossNewCurrentNativeLeases()async throws {
        let native=try native(),port=DraftPortState(),model=model(native,port)
        XCTAssertEqual(port.reads,0);XCTAssertTrue(port.sent.isEmpty)
        let first=try native.issueUserQuestion(expectedLease:try XCTUnwrap(native.authority.snapshot()),intent:.ask,
            question:"Explain queues.",baseRequestID:nil,enqueue:{_ in})
        port.current=binding(first);model.recordQuestion(binding(first),question:"Explain queues.")
        model.draft="Why that choice?"
        let newer=try native.issueUserQuestion(expectedLease:try XCTUnwrap(native.authority.snapshot()),intent:.ask,
            question:"Explain caches.",baseRequestID:nil,enqueue:{_ in})
        port.current=binding(newer);model.recordQuestion(binding(newer),question:"Explain caches.");model.refresh()
        XCTAssertEqual(model.snapshot.basis?.requestID,first.requestID)
        XCTAssertEqual(model.snapshot.basisState,.retained)
        model.submitDraft()
        XCTAssertEqual(port.sent.last?.baseRequestID,first.requestID)
        XCTAssertGreaterThan(try XCTUnwrap(port.sent.last).lease.presentationGeneration,newer.lease.presentationGeneration)
        XCTAssertEqual(port.sent.last?.question,"Why that choice?");XCTAssertTrue(model.draft.isEmpty)
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
    }
    func testEvictedBasisPreservesDraftUntilExplicitSendAsNew()async throws {
        let native=try native(),port=DraftPortState(),model=model(native,port)
        for index in 0..<10 {
            let request=try native.issueUserQuestion(expectedLease:try XCTUnwrap(native.authority.snapshot()),intent:.ask,
                question:"Explain item \(index).",baseRequestID:nil,enqueue:{_ in})
            port.current=binding(request);model.recordQuestion(binding(request),question:"Explain item \(index).")
            if index==0{model.draft="Why?"}
        }
        model.refresh();XCTAssertEqual(model.snapshot.basisState,.unavailable)
        model.submitDraft();XCTAssertEqual(model.draft,"Why?");XCTAssertTrue(port.sent.isEmpty)
        model.sendDraftAsNewQuestion()
        XCTAssertEqual(port.sent.count,1);XCTAssertNil(port.sent[0].baseRequestID)
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
    }
    func testLastSourceLossDisablesSendAsNewAndPreservesItsDraftBasis()async throws {
        let native=NativeSessionController(onEvent:{_ in}),port=DraftPortState()
        try native.start(selectedBundleID:nil,microphoneEnabled:true,
            components:[1:SourceComponents(vad:DraftQuietVAD(),recognizer:DraftQuietRecognizer())])
        let model=TypedAssistantController(session:{native.isSourceActive(.microphone) ? native.authority.snapshot():nil},currentRequest:{port.current},
            issue:{_,_,_ in XCTFail("An unavailable source must not issue");throw NativeSessionError.notAuthorized},cancel:{_ in throw PanelBridgeError.closed})
        let first=try native.issueUserQuestion(expectedLease:try XCTUnwrap(native.authority.snapshot()),intent:.ask,
            question:"Explain queues.",baseRequestID:nil,enqueue:{_ in})
        port.current=binding(first);model.recordQuestion(binding(first),question:"Explain queues.")
        model.draft="Why?"
        XCTAssertTrue(model.snapshot.canSendAsNew)
        native.sourceUnavailable(source:.microphone,generation:1,reason:.asrUnavailable)
        model.refresh()
        XCTAssertFalse(model.snapshot.canSendAsNew)
        XCTAssertFalse(model.snapshot.canHelpCurrent)
        model.sendDraftAsNewQuestion()
        XCTAssertEqual(model.draft,"Why?")
        XCTAssertEqual(model.snapshot.basis?.requestID,first.requestID)
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
    }
    func testLateContextFailureDoesNotOverwriteNewerDraftRevision()async throws {
        let native=try native(),port=DraftPortState(),model=model(native,port)
        model.draft="Explain queues.";model.submitDraft()
        let request=try XCTUnwrap(port.sent.last)
        model.draft="Newer unsent question."
        let response:[String:Any]=["schemaVersion":1,"captureSessionID":request.lease.captureSessionID.uuidString,
            "sessionEpoch":request.lease.sessionEpoch,"presentationGeneration":request.lease.presentationGeneration,
            "requestID":request.requestID.uuidString,"eventSequence":request.anchorEventSequence,"resultRevision":2,
            "disposition":"abstain","reasonCode":"user_request_context_unavailable","pythonToken":NSNull(),
            "displayID":NSNull(),"question":"","answerID":NSNull(),"answerKind":NSNull(),"card":NSNull(),"provenance":NSNull()]
        model.observeDecision(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:response)))
        XCTAssertEqual(model.draft,"Newer unsent question.")
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
    }
    func testCrossSessionBasisPreservesDraftUntilExplicitSendAsNew()async throws {
        let native=try native(),port=DraftPortState(),model=model(native,port)
        let first=try native.issueUserQuestion(expectedLease:try XCTUnwrap(native.authority.snapshot()),intent:.ask,
            question:"Explain queues.",baseRequestID:nil,enqueue:{_ in})
        port.current=binding(first);model.recordQuestion(binding(first),question:"Explain queues.")
        model.draft="Why?"
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
        try native.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,
            components:[2:SourceComponents(vad:DraftQuietVAD(),recognizer:DraftQuietRecognizer())])
        port.current=nil;model.refresh()
        XCTAssertEqual(model.snapshot.basisState,.unavailable);XCTAssertEqual(model.draft,"Why?")
        model.submitDraft();XCTAssertTrue(port.sent.isEmpty)
        model.sendDraftAsNewQuestion();XCTAssertNil(port.sent.last?.baseRequestID)
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
    }
    func testMissingLatestQuestionCannotSilentlyDropTheChosenBasis()async throws {
        let native=try native(),port=DraftPortState(),model=model(native,port)
        let original=try native.issueUserQuestion(expectedLease:try XCTUnwrap(native.authority.snapshot()),intent:.ask,
            question:"Explain queues.",baseRequestID:nil,enqueue:{_ in})
        port.current=binding(original);model.recordQuestion(binding(original),question:"Explain queues.")
        model.draft="Why?";port.current=nil
        model.useLatestQuestionForDraft()
        XCTAssertEqual(model.snapshot.basis?.requestID,original.requestID)
        XCTAssertEqual(model.draft,"Why?")
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
    }
    func testUnavailableBasisRestoresUntouchedSubmittedDraftAndOriginalBasis()async throws {
        let native=try native(),port=DraftPortState(),model=model(native,port)
        let first=try native.issueUserQuestion(expectedLease:try XCTUnwrap(native.authority.snapshot()),intent:.ask,
            question:"Explain queues.",baseRequestID:nil,enqueue:{_ in})
        port.current=binding(first);model.recordQuestion(binding(first),question:"Explain queues.")
        model.draft="Why?";model.submitDraft()
        let request=try XCTUnwrap(port.sent.last);XCTAssertTrue(model.draft.isEmpty)
        let fields:[String:Any]=["schemaVersion":1,"captureSessionID":request.lease.captureSessionID.uuidString,
            "sessionEpoch":request.lease.sessionEpoch,"presentationGeneration":request.lease.presentationGeneration,
            "requestID":request.requestID.uuidString,"eventSequence":request.anchorEventSequence,"resultRevision":2,
            "disposition":"abstain","reasonCode":"user_request_context_unavailable","pythonToken":NSNull(),
            "displayID":NSNull(),"question":"","answerID":NSNull(),"answerKind":NSNull(),"card":NSNull(),"provenance":NSNull()]
        model.observeDecision(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:fields)))
        XCTAssertEqual(model.draft,"Why?");XCTAssertEqual(model.snapshot.basis?.requestID,first.requestID)
        XCTAssertEqual(model.snapshot.basisState,.unavailable);XCTAssertFalse(model.snapshot.canSend)
        model.sendDraftAsNewQuestion();XCTAssertNil(port.sent.last?.baseRequestID)
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
    }
    func testOwnedLateContextFailureAfterNewCurrentQuestionRecoversUntouchedDraft()async throws {
        let native=try native(),port=DraftPortState(),model=model(native,port)
        let basis=try native.issueUserQuestion(expectedLease:try XCTUnwrap(native.authority.snapshot()),intent:.ask,
            question:"Explain queues.",baseRequestID:nil,enqueue:{_ in})
        port.current=binding(basis);model.recordQuestion(binding(basis),question:"Explain queues.")
        model.draft="Why?";model.submitDraft()
        let submitted=try XCTUnwrap(port.sent.last)
        let newer=try native.issueUserQuestion(expectedLease:submitted.lease,intent:.ask,
            question:"Explain caches.",baseRequestID:nil,enqueue:{_ in})
        port.current=binding(newer);model.recordQuestion(binding(newer),question:"Explain caches.");model.observeRequest(binding(newer))
        let fields:[String:Any]=["schemaVersion":1,"captureSessionID":submitted.lease.captureSessionID.uuidString,
            "sessionEpoch":submitted.lease.sessionEpoch,"presentationGeneration":submitted.lease.presentationGeneration,
            "requestID":submitted.requestID.uuidString,"eventSequence":submitted.anchorEventSequence,"resultRevision":2,
            "disposition":"abstain","reasonCode":"user_request_context_unavailable","pythonToken":NSNull(),
            "displayID":NSNull(),"question":"","answerID":NSNull(),"answerKind":NSNull(),"card":NSNull(),"provenance":NSNull()]
        var wrong=fields;wrong["eventSequence"]=submitted.anchorEventSequence+1
        model.observeDecision(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:wrong)))
        XCTAssertTrue(model.draft.isEmpty)
        model.observeDecision(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:fields)))
        XCTAssertEqual(model.draft,"Why?");XCTAssertEqual(model.snapshot.basis?.requestID,basis.requestID)
        XCTAssertEqual(model.snapshot.basisState,.unavailable);XCTAssertEqual(port.current?.requestID,newer.requestID)
        XCTAssertTrue(model.snapshot.canStop)
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
    }
    func testLateCancellationReceiptCannotClearAReplacementRequest()async throws {
        let native=try native(),port=DraftPortState(),gate=DraftCancelGate()
        let model=model(native,port,cancel:{target in
            let request=try native.issueAnswerCancellation(expectedLease:target.lease,targetRequestID:target.requestID,enqueue:{_ in})
            port.current=nil;await gate.wait()
            return try AnswerCancellationResponse(data:JSONSerialization.data(withJSONObject:[
                "schemaVersion":1,"kind":"answer_cancel_response","requestID":request.requestID.uuidString,
                "targetRequestID":request.targetRequestID.uuidString,"captureSessionID":request.lease.captureSessionID.uuidString,
                "sessionEpoch":request.lease.sessionEpoch,"presentationGeneration":request.lease.presentationGeneration,
                "resultRevision":2,"reasonCode":"request_cancelled","quiesced":true]))
        })
        model.draft="Explain queues.";model.submitDraft()
        XCTAssertTrue(model.snapshot.canStop)
        let cancelling=Task{await model.cancelCurrentResponse()}
        for _ in 0..<30 where !gate.entered{await Task.yield()}
        XCTAssertTrue(gate.entered)
        model.draft="Explain caches.";model.submitDraft()
        gate.release();await cancelling.value
        XCTAssertEqual(model.snapshot.status,"Thinking");XCTAssertTrue(model.snapshot.canStop)
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
    }
}
