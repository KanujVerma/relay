import Foundation
import XCTest
import RelayProfile
import RelayContextComposition
@testable import RelaySessionPanel

@MainActor private final class ActualLearningHistoryPreferences:HistorySavingPreferences{var savingEnabled=false}
@MainActor private final class ActualLearningControls:LearningControlPreferences {
    var receipt=LearningControlReceipt(revision:nil,enabled:false,pending:nil)
    func read()->LearningControlReceipt{receipt}
    func deny(_ pending:LearningPendingControl)->LearningControlReceipt{receipt=LearningControlReceipt(revision:pending.revision,enabled:false,pending:pending);return receipt}
    func commit(_ control:LearningControlRecord)->LearningControlReceipt{receipt=LearningControlReceipt(revision:control.revision,enabled:control.enabled,pending:nil);return receipt}
}
private final class ActualLearningKey:ProfileKeyProvider,@unchecked Sendable {
    private let lock=NSLock();private var calls=0
    var count:Int{lock.withLock{calls}}
    func key(createIfMissing:Bool)throws->Data{lock.withLock{calls+=1};return Data(repeating:127,count:32)}
}
@MainActor final class LearningHistoryCoordinatorTests:XCTestCase {
    private func fixture()throws->(SessionHistoryCoordinator,LearningMemoryCoordinator,URL,ActualLearningKey,ActualLearningControls,ActualLearningHistoryPreferences,HistoryVaultStorage){
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("relay-learning-history-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let key=ActualLearningKey(),preferences=ActualLearningHistoryPreferences(),controls=ActualLearningControls()
        let storage=HistoryVaultStorage(directory:root.appendingPathComponent("Relay/History"),keys:key)
        let history=SessionHistoryCoordinator(storageFactory:{storage},preferences:preferences,canEnable:{true})
        let memory=history.makeLearningCoordinator(preferences:controls,canEnable:{true})
        history.onSourceDenial={[weak memory] in memory?.handleHistorySourceDenial($0)}
        addTeardownBlock{await memory.waitForQuiescence();await history.closeForOwnerRetirement();try? FileManager.default.removeItem(at:root)}
        return(history,memory,root,key,controls,preferences,storage)
    }
    private func episode(_ history:SessionHistoryCoordinator,_ memory:LearningMemoryCoordinator)async throws->(HistorySessionPermit,SessionTranscriptStore,LearningTestEvents){
        let issued=try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{true}),permit=try XCTUnwrap(issued)
        let transcript=SessionTranscriptStore();transcript.onHistoryObservation={history.observe($0);memory.session.observe($0)}
        var e=LearningTestEvents();e.start(transcript);e.final(1,text:"How should bounded queues handle overload?",into:transcript)
        memory.session.available(binding:PanelRequestBinding(lease:e.lease,requestID:UUID(),eventSequence:e.sequence),replacement:1,
            lead:"Explain bounded queues, then make overload explicit.",points:["Keep each request inside a fixed capacity and discuss the rejection policy."],guideRevision:nil,visible:true,at:250_000_000)
        e.final(3,text:"Keep bounded queues and make overload explicit.",source:1,into:transcript);e.final(4,text:"What about null items?",into:transcript)
        return(permit,transcript,e)
    }
    private func end(_ history:SessionHistoryCoordinator,_ memory:LearningMemoryCoordinator,_ permit:HistorySessionPermit,_ transcript:SessionTranscriptStore,_ initial:LearningTestEvents)async throws{
        var e=initial
        transcript.observe(e.event(.stopping,payload:["reasonCode":.string("user_stop")]))
        transcript.observe(e.event(.stopped,payload:["reasonCode":.string("user_stop"),"quiesced":.bool(true)]))
        memory.endSession();_=history.retireCurrentSession()
        try await history.finishSession(permit,paused:false);await memory.waitForQuiescence();await history.waitForQuiescence()
    }
    func testFactoryAndDefaultOffRestoreCannotCreateHistoryOrReadAKey()async throws{
        let(history,memory,root,key,_,_,_)=try fixture()
        try await memory.restore();XCTAssertEqual(key.count,0)
        do{try await memory.enable();XCTFail("An unopened private History owner cannot enable Learning")}catch{}
        XCTAssertEqual(key.count,0);XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("Relay").path))
        XCTAssertEqual(history.snapshot.phase,.locked)
    }
    func testActualEndJoinsOriginalWritesAndLearningThenLaterSessionUsesThreeStoredExamples()async throws{
        let(history,memory,_,_,_,_,_)=try fixture();try await history.enableSaving();try await memory.enable()
        for _ in 0..<3{
            let(permit,transcript,e)=try await episode(history,memory)
            try await end(history,memory,permit,transcript,e)
        }
        XCTAssertEqual(memory.retainedEpisodes.count,3);XCTAssertTrue(history.snapshot.records.allSatisfy{$0.state == .completed})
        let later=try XCTUnwrap(memory.capture(question:"bounded queues null items"))
        XCTAssertEqual(later.payload.adjustments,[.conciseLead]);XCTAssertEqual(later.payload.supportIDs.count,3)
        XCTAssertFalse(later.payload.examples.isEmpty);XCTAssertTrue(memory.owns(later))
        let manual=try XCTUnwrap(history.snapshot.records.first)
        try await history.openRecord(manual.id)
        _=try await history.saveNotes(manual.id,expectedRevision:manual.revision,title:"Keep manual metadata",note:"This does not delete original spoken evidence.")
        XCTAssertEqual(memory.retainedEpisodes.count,3);XCTAssertTrue(memory.owns(later),"Metadata-only Notes source denial must not invalidate original-row support")
    }
    func testActualPrivateSourceDeleteClearsOffRetentionSemanticContextBeforeWriteJoin()async throws{
        let(history,memory,_,_,_,_,_)=try fixture();try await history.enableSaving()
        let issued=try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{true}),permit=try XCTUnwrap(issued)
        let transcript=SessionTranscriptStore();transcript.onHistoryObservation={history.observe($0);memory.session.observe($0)}
        var e=LearningTestEvents();e.start(transcript);e.final(1,text:"We decided retention must be seven days.",source:1,into:transcript)
        await history.waitForQuiescence();let original=try XCTUnwrap(memory.capture(question:"retention"))
        let record=try XCTUnwrap(history.snapshot.records.first),capture=e.session.uuidString.lowercased()+":1"
        let deleting=history.deleteSource(permit.recordID,expectedRevision:record.revision,captureID:capture,source:.microphone)
        XCTAssertFalse(memory.owns(original));XCTAssertFalse(memory.capture(question:"retention")?.payload.continuity.contains{$0.text.contains("seven days")} ?? false)
        try await deleting.value
        e.final(2,text:"We decided fresh retention needs a new review.",source:1,into:transcript)
        XCTAssertTrue(memory.capture(question:"fresh retention review")?.payload.continuity.contains{$0.text.contains("new review")} ?? false)
        XCTAssertEqual(transcript.snapshot.phase,.listening)
        memory.endSession();_=history.retireCurrentSession();try await history.finishSession(permit,paused:false)
    }
}
