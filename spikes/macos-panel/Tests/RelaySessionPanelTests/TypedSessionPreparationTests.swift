import Combine
import Foundation
import XCTest
import RelayNativeSession
import RelayContextComposition
@testable import RelaySessionPanel

@MainActor private final class PreparationGate {
    var entered=false
    private var continuation:CheckedContinuation<Void,Never>?
    func wait()async{entered=true;await withCheckedContinuation{continuation=$0}}
    func release(){continuation?.resume();continuation=nil}
}

@MainActor private final class PreparationFixture {
    let native=NativeAssistantSessionController()
    let preparing=PreparationGate(),cleaning=PreparationGate()
    var holdPreparation=true,holdCleanup=false,failPreparation=false,failIssue=false
    var available=false,allowPreparation=true
    var prepareCount=0,retireCount=0,reads=0
    var current:PanelRequestBinding?
    var sent:[NativeUserQuestionRequest]=[]
    var originalCurrent:[@MainActor ()->Bool]=[]
    func open()throws->PresentationLease {
        let request=try native.begin(enqueue:{_ in});try native.completeOpen(request)
        available=true;return request.lease
    }
    func model()->TypedAssistantController {
        TypedAssistantController(session:{self.reads+=1;return self.available ? self.native.authority.snapshot():nil},
            currentRequest:{self.current},issue:{intent,text,basis in
                if self.failIssue{throw NativeSessionError.notAuthorized}
                let request=try self.native.issueUserQuestion(expectedLease:try XCTUnwrap(self.native.authority.snapshot()),
                    intent:intent,question:text,baseRequestID:basis,enqueue:{_ in})
                self.sent.append(request);self.current=PanelRequestBinding(lease:request.lease,
                    requestID:request.requestID,eventSequence:request.anchorEventSequence);return request
            },cancel:{_ in throw PanelBridgeError.closed},preparation:TypedSessionPreparationPorts(
                canPrepareSession:{self.allowPreparation},prepareSession:{_,isCurrent in
                    self.prepareCount+=1;self.originalCurrent.append(isCurrent)
                    if self.holdPreparation{await self.preparing.wait()}
                    if self.failPreparation{throw PanelBridgeError.closed}
                    // Deliberately ignores cancellation, like an in-flight
                    // helper open whose actual response must still be joined.
                    return try self.open()
                },retireUnusedSession:{_,lease in
                    self.retireCount+=1
                    if self.holdCleanup{await self.cleaning.wait()}
                    guard self.native.authority.snapshot()==lease else{return}
                    if let close=try? self.native.beginClose(enqueue:{_ in}){try? self.native.completeClose(close)}
                    self.available=false;self.current=nil
                }))
    }
}

@MainActor final class TypedSessionPreparationTests:XCTestCase {
    private func eventually(_ predicate:()->Bool)async {
        for _ in 0..<1000{if predicate(){return};await Task.yield()}
        XCTAssertTrue(predicate())
    }
    func testIdleEditingHasNoPreparationAndSendWaitsForActualReadyBeforeIssuing()async throws {
        let fixture=PreparationFixture(),model=fixture.model()
        XCTAssertEqual(fixture.reads,0);XCTAssertEqual(fixture.prepareCount,0)
        model.draft="Explain queues."
        XCTAssertTrue(model.snapshot.canSend);XCTAssertEqual(fixture.prepareCount,0)
        model.submitDraft();model.submitDraft()
        await eventually{fixture.preparing.entered}
        XCTAssertTrue(model.snapshot.isPreparing);XCTAssertFalse(model.snapshot.canSend)
        XCTAssertEqual(model.draft,"Explain queues.");XCTAssertTrue(fixture.sent.isEmpty)
        XCTAssertEqual(fixture.prepareCount,1);XCTAssertNil(fixture.native.authority.snapshot())
        fixture.preparing.release();await model.waitForPreparationQuiescence()
        XCTAssertFalse(model.snapshot.isPreparing);XCTAssertEqual(fixture.sent.count,1)
        XCTAssertEqual(fixture.sent[0].question,"Explain queues.");XCTAssertTrue(model.draft.isEmpty)
        XCTAssertEqual(fixture.retireCount,0)
    }
    func testCancelledReadyResultJoinsUnusedScopeCleanupBeforeAvailability()async throws {
        let fixture=PreparationFixture(),model=fixture.model();fixture.holdCleanup=true
        model.draft="Explain queues.";model.submitDraft();await eventually{fixture.preparing.entered}
        model.cancelPreparation();XCTAssertFalse(fixture.originalCurrent[0]())
        fixture.preparing.release();await eventually{fixture.cleaning.entered}
        XCTAssertTrue(model.snapshot.isPreparing);XCTAssertFalse(model.snapshot.canSendAsNew)
        XCTAssertTrue(fixture.sent.isEmpty);XCTAssertEqual(model.draft,"Explain queues.")
        model.submitDraft();XCTAssertEqual(fixture.prepareCount,1)
        fixture.cleaning.release();await model.waitForPreparationQuiescence()
        XCTAssertFalse(model.snapshot.isPreparing);XCTAssertNil(fixture.native.authority.snapshot())
        XCTAssertEqual(fixture.retireCount,1);XCTAssertTrue(model.snapshot.canSend)
    }
    func testNewerEditSurvivesLateReadyAndDoesNotImplicitlySend()async throws {
        let fixture=PreparationFixture(),model=fixture.model()
        model.draft="Old question.";model.submitDraft();await eventually{fixture.preparing.entered}
        model.draft="New question."
        XCTAssertFalse(fixture.originalCurrent[0]())
        fixture.preparing.release();await model.waitForPreparationQuiescence()
        XCTAssertEqual(model.draft,"New question.");XCTAssertTrue(fixture.sent.isEmpty)
        XCTAssertEqual(fixture.retireCount,1);XCTAssertNil(fixture.native.authority.snapshot())
        fixture.holdPreparation=false
        model.submitDraft();await model.waitForPreparationQuiescence()
        XCTAssertEqual(fixture.sent.map(\.question),["New question."])
        XCTAssertFalse(fixture.originalCurrent[0]());XCTAssertFalse(model.snapshot.isPreparing)
    }
    func testFailedOrCancelledSendAsNewKeepsOriginalUnavailableBasis()async throws {
        for cancel in [false,true] {
            let fixture=PreparationFixture(),model=fixture.model()
            _=try fixture.open()
            model.draft="Explain queues.";model.submitDraft()
            let first=try XCTUnwrap(fixture.sent.last),binding=try XCTUnwrap(fixture.current)
            model.recordQuestion(binding,question:"Explain queues.");model.draft="Why?"
            let close=try XCTUnwrap(fixture.native.beginClose(enqueue:{_ in}));try fixture.native.completeClose(close)
            fixture.available=false;fixture.current=nil;model.refresh()
            XCTAssertEqual(model.snapshot.basisState,.unavailable)
            model.sendDraftAsNewQuestion();await eventually{fixture.preparing.entered}
            XCTAssertEqual(model.snapshot.basis?.requestID,first.requestID)
            if cancel{model.cancelPreparation()}else{fixture.failPreparation=true}
            fixture.preparing.release();await model.waitForPreparationQuiescence()
            XCTAssertEqual(model.draft,"Why?");XCTAssertEqual(model.snapshot.basis?.requestID,first.requestID)
            XCTAssertEqual(fixture.sent.count,1)
        }
    }
    func testActiveFailedSendAsNewAlsoKeepsOriginalBasis()throws {
        let fixture=PreparationFixture(),model=fixture.model();_=try fixture.open()
        model.draft="Explain queues.";model.submitDraft()
        let binding=try XCTUnwrap(fixture.current)
        model.recordQuestion(binding,question:"Explain queues.");model.draft="Why?"
        fixture.failIssue=true;model.sendDraftAsNewQuestion()
        XCTAssertEqual(model.draft,"Why?");XCTAssertEqual(model.snapshot.basis?.requestID,binding.requestID)
        XCTAssertEqual(fixture.sent.count,1)
    }
    func testCompletionObserverCanStartFreshPreparationWithoutOldCleanupClearingIt()async throws {
        let fixture=PreparationFixture(),model=fixture.model();fixture.failPreparation=true
        var replacement=false
        let observer=model.$snapshot.sink{snapshot in
            if snapshot.isPreparing || fixture.prepareCount != 1 || replacement{return}
            replacement=true;fixture.failPreparation=false;fixture.holdPreparation=true
            model.draft="Replacement question.";model.submitDraft()
        }
        model.draft="Old question.";model.submitDraft();await eventually{fixture.preparing.entered}
        fixture.preparing.release()
        await eventually{fixture.prepareCount==2}
        XCTAssertTrue(model.snapshot.isPreparing);XCTAssertEqual(model.draft,"Replacement question.")
        XCTAssertFalse(fixture.originalCurrent[0]());XCTAssertTrue(fixture.originalCurrent[1]())
        fixture.preparing.release();await model.waitForPreparationQuiescence()
        XCTAssertEqual(fixture.sent.map(\.question),["Replacement question."])
        withExtendedLifetime(observer){}
    }
}
