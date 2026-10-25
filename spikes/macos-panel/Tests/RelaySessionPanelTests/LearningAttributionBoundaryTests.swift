import Foundation
import XCTest
import RelayContextComposition
@testable import RelaySessionPanel

@MainActor private final class AttributionControlFixture:LearningControlPreferences {
    var value=LearningControlReceipt(revision:nil,enabled:false,pending:nil)
    func read()->LearningControlReceipt{value}
    func deny(_ pending:LearningPendingControl)->LearningControlReceipt{value=LearningControlReceipt(revision:pending.revision,enabled:false,pending:pending);return value}
    func commit(_ control:LearningControlRecord)->LearningControlReceipt{value=LearningControlReceipt(revision:control.revision,enabled:control.enabled,pending:nil);return value}
}

@MainActor final class LearningAttributionBoundaryTests:XCTestCase {
    func testOriginalAvailableSuggestionCannotBecomeANewRetainedEpisodeAcrossExplicitControlBoundary()async throws{
        for action in ["reset","disable_then_enable","enable"]{
            let controls=AttributionControlFixture(),workspace=UUID(),record=UUID()
            var archive=LearningArchive()
            let ports=LearningPersistencePorts(scope:{LearningPersistenceScope(workspaceEpoch:workspace,recordID:record,expiresAt:1_900_000_000)},load:{
                LearningArchiveReceipt(workspaceEpoch:workspace,archive:archive)
            },mutate:{mutation in
                switch mutation{
                case .control(let pending):archive=try pending.applying(to:archive)
                case .save(let episode):
                    let episodes=archive.episodes+[episode]
                    archive=LearningArchive(episodes:episodes,rules:try LearningDerivation.rebuild(episodes,suppressed:archive.control?.suppressedRuleIDs ?? []),control:archive.control)
                case .suppress,.reset:throw HistoryError.invalid
                }
                return LearningArchiveReceipt(workspaceEpoch:workspace,archive:archive)
            })
            let memory=LearningMemoryCoordinator(preferences:controls,persistence:ports,canEnable:{true},clock:{Date(timeIntervalSince1970:1_800_000_000)})
            if action != "enable"{try await memory.enable()}
            let transcript=SessionTranscriptStore();transcript.onHistoryObservation=memory.session.observe
            var events=LearningTestEvents();events.start(transcript);events.final(1,text:"How should bounded queues handle overload?",into:transcript)
            let original=PanelRequestBinding(lease:events.lease,requestID:UUID(),eventSequence:events.sequence)
            memory.session.available(binding:original,replacement:1,lead:"Explain bounded queues, then make overload explicit.",points:[],guideRevision:nil,visible:true,at:250_000_000)
            switch action{
            case "reset":try await memory.reset().value
            case "disable_then_enable":try await memory.disable().value;try await memory.enable()
            default:try await memory.enable()
            }
            events.final(3,text:"Keep bounded queues and make overload explicit.",source:1,into:transcript)
            events.final(4,text:"How should bounded queues handle capacity?",into:transcript)
            await memory.waitForQuiescence()
            XCTAssertTrue(archive.episodes.isEmpty,"\(action): old pending availability crossed the control boundary")
            XCTAssertTrue(memory.capture(question:"bounded queues overload")?.payload.continuity.contains{$0.text.contains("overload")} ?? false)
            memory.session.available(binding:original,replacement:1,lead:"Explain bounded queues, then make overload explicit.",points:[],guideRevision:nil,visible:true,at:470_000_000)
            let fresh=PanelRequestBinding(lease:events.lease,requestID:UUID(),eventSequence:events.sequence)
            memory.session.available(binding:fresh,replacement:2,lead:"Explain bounded queues, then make overload explicit.",points:[],guideRevision:nil,visible:true,at:475_000_000)
            events.final(5,text:"Keep bounded queues and make overload explicit.",source:1,into:transcript);events.final(6,text:"Discuss overload recovery?",into:transcript)
            await memory.waitForQuiescence()
            XCTAssertEqual(archive.episodes.map(\.id),[fresh.requestID],"\(action): only a fresh post-control availability may be retained")
        }
    }
}
