import Foundation
import XCTest
import RelayContextComposition
@testable import RelaySessionPanel

@MainActor private final class LearningFixtureControls:LearningControlPreferences {
    var value=LearningControlReceipt(revision:nil,enabled:false,pending:nil)
    var failDeny=false,failCommit=false
    func read()->LearningControlReceipt{value}
    func deny(_ pending:LearningPendingControl)throws->LearningControlReceipt{
        if failDeny{throw HistoryError.unavailable}
        value=LearningControlReceipt(revision:pending.revision,enabled:false,pending:pending);return value
    }
    func commit(_ control:LearningControlRecord)throws->LearningControlReceipt{
        if failCommit{throw HistoryError.unavailable}
        value=LearningControlReceipt(revision:control.revision,enabled:control.enabled,pending:nil);return value
    }
}
/// An intentionally uncooperative async source port tests ownership/cancel.
/// It is not evidence of encrypted persistence or actual process durability.
@MainActor private final class LearningFixturePersistence {
    var scope:LearningPersistenceScope?=LearningPersistenceScope(workspaceEpoch:UUID(),recordID:nil,expiresAt:nil)
    var archive=LearningArchive(),reads=0,writes=0,holdRead=false,holdWrite=false,failWrite=false
    var held=false
    private var release:CheckedContinuation<Void,Never>?
    func resume(){let old=release;release=nil;held=false;holdRead=false;holdWrite=false;old?.resume()}
    var ports:LearningPersistencePorts{LearningPersistencePorts(scope:{[self] in scope},load:{[self] in
        guard let original=scope else{throw HistoryError.closed};reads+=1
        if holdRead{held=true;await withCheckedContinuation{release=$0}}
        return LearningArchiveReceipt(workspaceEpoch:original.workspaceEpoch,archive:archive)
    },mutate:{[self] mutation in
        guard let original=scope else{throw HistoryError.closed};writes+=1
        if holdWrite{held=true;await withCheckedContinuation{release=$0}}
        if failWrite{throw HistoryError.unavailable}
        switch mutation{
        case .control(let pending):archive=try pending.applying(to:archive)
        case .save(let episode):
            let episodes=archive.episodes+[episode]
            archive=LearningArchive(episodes:episodes,rules:try LearningDerivation.rebuild(episodes,suppressed:[]),control:archive.control)
        case .suppress,.reset:throw HistoryError.invalid
        }
        return LearningArchiveReceipt(workspaceEpoch:original.workspaceEpoch,archive:archive)
    })}
}

@MainActor final class LearningMemoryCoordinatorTests:XCTestCase {
    private func learner(_ controls:LearningFixtureControls,_ storage:LearningFixturePersistence,canEnable:Bool=true)->LearningMemoryCoordinator{
        LearningMemoryCoordinator(preferences:controls,persistence:storage.ports,canEnable:{canEnable},clock:{Date(timeIntervalSince1970:1_800_000_000)})
    }
    private func until(_ condition:()->Bool)async throws{
        let deadline=ContinuousClock.now+Duration.seconds(5)
        while !condition(){guard ContinuousClock.now<deadline else{throw HistoryError.unavailable};try await Task.sleep(for:.milliseconds(2))}
    }
    private func populate(_ storage:LearningFixturePersistence)throws{
        let records=[UUID(),UUID()];var episodes:[LearningEpisode]=[]
        for n in 0..<3{
            let memory=LearningSessionMemory(),transcript=SessionTranscriptStore();transcript.onHistoryObservation=memory.observe
            var e=LearningTestEvents();e.start(transcript);e.final(1,text:"How should bounded queues handle overload?",into:transcript)
            memory.available(binding:PanelRequestBinding(lease:e.lease,requestID:UUID(),eventSequence:e.sequence),replacement:1,
                lead:"Explain bounded queues, then make overload explicit.",points:["Keep every request inside a fixed capacity and discuss a rejection policy."],guideRevision:nil,visible:true,at:250_000_000)
            e.final(3,text:"Keep bounded queues and make overload explicit.",source:1,into:transcript);e.final(4,text:"Continue.",into:transcript)
            episodes.append(try XCTUnwrap(memory.episodes.first).retained(recordID:records[n%2],expiresAt:1_900_000_000))
        }
        storage.archive=LearningArchive(episodes:episodes,rules:try LearningDerivation.rebuild(episodes,suppressed:[]),
            control:LearningControlRecord(revision:UUID(),enabled:true,suppressedRuleIDs:[]))
    }
    func testDefaultOffAndDisallowedEnablePerformNoHistoryReadsOrWrites()async throws{
        let controls=LearningFixtureControls(),storage=LearningFixturePersistence(),memory=learner(controls,storage,canEnable:false)
        try await memory.restore();XCTAssertEqual(storage.reads,0);XCTAssertEqual(storage.writes,0)
        do{try await memory.enable();XCTFail("Idle/explicit enable gate is required")}catch{}
        XCTAssertEqual(storage.reads,0);XCTAssertEqual(storage.writes,0);XCTAssertNil(memory.capture(question:"bounded queues"))
    }
    func testRetiredOriginalLoadReceiptCannotInstallOrClearReplacementWorkspace()async throws{
        let controls=LearningFixtureControls(),storage=LearningFixturePersistence(),memory=learner(controls,storage)
        addTeardownBlock{await storage.resume();await memory.waitForQuiescence()}
        let old=try XCTUnwrap(storage.scope).workspaceEpoch;storage.holdRead=true
        let opening=Task{try await memory.enable()};try await until{storage.held}
        memory.retire(.workspace(workspaceEpoch:old));storage.scope=nil;storage.resume()
        do{try await opening.value;XCTFail("Retired original receipt cannot enable")}catch{}
        XCTAssertNotEqual(memory.snapshot.phase,.ready);XCTAssertEqual(storage.writes,0)
        storage.holdRead=false;storage.scope=LearningPersistenceScope(workspaceEpoch:UUID(),recordID:nil,expiresAt:nil)
        try await memory.enable();XCTAssertEqual(memory.snapshot.phase,.ready)
        memory.retire(.workspace(workspaceEpoch:old));XCTAssertEqual(memory.snapshot.phase,.ready)
    }
    func testFailedControlDenialIsNotAcknowledgedAsDurableEnable()async throws{
        let controls=LearningFixtureControls(),storage=LearningFixturePersistence(),memory=learner(controls,storage)
        controls.failDeny=true
        do{try await memory.enable();XCTFail("A failed control write cannot be success")}catch{}
        XCTAssertEqual(storage.writes,0);XCTAssertNotEqual(memory.snapshot.phase,.ready);XCTAssertNil(memory.capture(question:"bounded queues"))
    }
    func testUndoRetiresCurrentProjectionBeforeHeldMutationAndPendingIntentBlocksRestartFallback()async throws{
        let controls=LearningFixtureControls(),storage=LearningFixturePersistence();try populate(storage)
        _=try controls.commit(XCTUnwrap(storage.archive.control))
        let memory=learner(controls,storage);try await memory.restore()
        addTeardownBlock{await storage.resume();await memory.waitForQuiescence()}
        let original=try XCTUnwrap(memory.capture(question:"bounded queues"));XCTAssertTrue(memory.owns(original))
        storage.holdWrite=true;storage.failWrite=true
        let undo=memory.undo("technical:concise_lead")
        XCTAssertFalse(memory.owns(original));try await until{storage.held}
        XCTAssertNotNil(controls.read().pending);storage.resume()
        do{try await undo.value;XCTFail("Failed suppression must remain unavailable")}catch{}
        XCTAssertNil(memory.capture(question:"bounded queues"))
        storage.holdWrite=false
        let restarted=learner(controls,storage)
        do{try await restarted.restore();XCTFail("Pending failed intent cannot restore old style")}catch{}
        XCTAssertNil(restarted.capture(question:"bounded queues"))
        storage.failWrite=false;try await restarted.restore()
        XCTAssertTrue(restarted.capture(question:"bounded queues")?.payload.adjustments.isEmpty ?? true)
        XCTAssertNil(controls.read().pending)
    }
}
