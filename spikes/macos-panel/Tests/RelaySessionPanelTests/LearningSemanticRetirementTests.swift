import Foundation
import XCTest
@testable import RelaySessionPanel

@MainActor private final class SemanticControlFixture:LearningControlPreferences {
    let control:LearningControlRecord
    let enabled:Bool
    init(enabled:Bool){self.enabled=enabled;control=LearningControlRecord(revision:UUID(),enabled:enabled,suppressedRuleIDs:[])}
    func read()->LearningControlReceipt{LearningControlReceipt(revision:enabled ? control.revision:nil,enabled:enabled,pending:nil)}
    func deny(_ pending:LearningPendingControl)throws->LearningControlReceipt{throw HistoryError.unavailable}
    func commit(_ control:LearningControlRecord)throws->LearningControlReceipt{throw HistoryError.unavailable}
}
@MainActor private final class SemanticSourceFixture {
    let workspace=UUID(),record=UUID()
    var scope:LearningPersistenceScope?
    let controls:SemanticControlFixture
    init(enabled:Bool){controls=SemanticControlFixture(enabled:enabled);scope=LearningPersistenceScope(workspaceEpoch:workspace,recordID:record,expiresAt:1_900_000_000)}
    var ports:LearningPersistencePorts{LearningPersistencePorts(scope:{[self] in scope},load:{[self] in
        LearningArchiveReceipt(workspaceEpoch:workspace,archive:LearningArchive(control:controls.control))
    },mutate:{_ in throw HistoryError.unavailable})}
}

/// Actual original finals, but synthetic History scope/control ports. Actual
/// encrypted-store/Model deletion is a separate required acceptance gate.
@MainActor final class LearningSemanticRetirementTests:XCTestCase {
    private func rig(enabled:Bool)async throws->(LearningMemoryCoordinator,SemanticSourceFixture,SessionTranscriptStore,LearningTestEvents){
        let source=SemanticSourceFixture(enabled:enabled)
        let memory=LearningMemoryCoordinator(preferences:source.controls,persistence:source.ports,canEnable:{false},clock:{Date(timeIntervalSince1970:1_800_000_000)})
        if enabled{try await memory.restore()}
        let transcript=SessionTranscriptStore();transcript.onHistoryObservation=memory.session.observe
        var events=LearningTestEvents();events.start(transcript)
        events.final(1,text:"We decided retention must be seven days.",source:1,into:transcript)
        return(memory,source,transcript,events)
    }
    func testRecordDeletionClearsAffiliatedSemanticTextAfterPrivateScopeIsAlreadyNil()async throws{
        let(memory,source,transcript,initial)=try await rig(enabled:true);var events=initial
        let original=try XCTUnwrap(memory.capture(question:"retention"))
        XCTAssertTrue(original.payload.continuity.contains{$0.text.contains("seven days")})
        source.scope=nil
        memory.retire(.record(workspaceEpoch:source.workspace,recordID:source.record))
        XCTAssertFalse(memory.capture(question:"retention")?.payload.continuity.contains{$0.text.contains("seven days")} ?? false)
        XCTAssertFalse(memory.owns(original))
        events.final(2,text:"We decided new retention needs a new review.",source:1,into:transcript)
        XCTAssertTrue(memory.capture(question:"new retention review")?.payload.continuity.contains{$0.text.contains("new review")} ?? false)
        memory.retire(.record(workspaceEpoch:source.workspace,recordID:source.record))
        XCTAssertTrue(memory.capture(question:"new retention review")?.payload.continuity.contains{$0.text.contains("new review")} ?? false)
    }
    func testSourceDeletionWithRetentionOffStillClearsOriginalSemanticAndOldProjection()async throws{
        let(memory,source,_,events)=try await rig(enabled:false)
        let original=try XCTUnwrap(memory.capture(question:"retention"));source.scope=nil
        memory.retire(.source(workspaceEpoch:source.workspace,recordID:source.record,captureID:events.session.uuidString.lowercased()+":1",source:.microphone))
        XCTAssertFalse(memory.capture(question:"retention")?.payload.continuity.contains{$0.text.contains("seven days")} ?? false)
        XCTAssertFalse(memory.owns(original))
    }
    func testUnrelatedAndOldWorkspaceNoticesCannotClearReplacementContext()async throws{
        let(memory,source,_,_)=try await rig(enabled:false)
        memory.retire(.record(workspaceEpoch:source.workspace,recordID:UUID()))
        XCTAssertTrue(memory.capture(question:"retention")?.payload.continuity.contains{$0.text.contains("seven days")} ?? false)
        memory.endSession()
        source.scope=LearningPersistenceScope(workspaceEpoch:UUID(),recordID:UUID(),expiresAt:1_900_000_000)
        let transcript=SessionTranscriptStore();transcript.onHistoryObservation=memory.session.observe
        var fresh=LearningTestEvents();fresh.start(transcript);fresh.final(1,text:"We decided replacement storage must use SQLite.",source:1,into:transcript)
        memory.retire(.record(workspaceEpoch:source.workspace,recordID:source.record))
        XCTAssertTrue(memory.capture(question:"replacement storage SQLite")?.payload.continuity.contains{$0.text.contains("replacement storage")} ?? false)
    }
    func testOrdinarySourceExplanationSurvivesPauseAndFreshCaptureAsReadOnlyContext()async throws{
        let memory=LearningSessionMemory(),transcript=SessionTranscriptStore();transcript.onHistoryObservation=memory.observe
        var old=LearningTestEvents();old.start(transcript);old.final(1,text:"The metrics count refunds against original order date.",source:1,into:transcript)
        memory.pause()
        let next=SessionTranscriptStore();next.onHistoryObservation=memory.observe;var fresh=LearningTestEvents();fresh.start(next)
        XCTAssertTrue(memory.projection(question:"refunds order date").contains{$0.text.contains("original order date")})
    }
}
