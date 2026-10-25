import Foundation
import XCTest
import RelayContextComposition
@testable import RelaySessionPanel

@MainActor final class LearningDerivationTests:XCTestCase {
    private func episode(record:UUID=UUID(),question:String="How should a bounded queue handle overload?",reply:String="Keep bounded queues and make overload explicit.",expires:TimeInterval=1_900_000_000) throws->LearningEpisode{
        let memory=LearningSessionMemory(),transcript=SessionTranscriptStore();transcript.onHistoryObservation=memory.observe
        var events=LearningTestEvents();events.start(transcript)
        events.final(1,text:question,into:transcript)
        let binding=PanelRequestBinding(lease:events.lease,requestID:UUID(),eventSequence:events.sequence)
        memory.available(binding:binding,replacement:1,lead:"Explain bounded queues, then make overload explicit.",points:["Keep every request inside a fixed capacity and discuss a clear rejection policy."],guideRevision:nil,visible:true,at:250_000_000)
        events.final(3,text:reply,source:1,into:transcript);events.final(4,text:"What about bounded queues with null items?",into:transcript)
        return try XCTUnwrap(memory.episodes.first).retained(recordID:record,expiresAt:expires)
    }
    func testAutomaticTentativeRuleRequiresThreeCleanEpisodesAcrossTwoRetainedSessions()async throws{
        let one=UUID(),two=UUID(),a=try episode(record:one),b=try episode(record:one),c=try episode(record:two)
        XCTAssertTrue(try LearningDerivation.rebuild([a,b],suppressed:[]).isEmpty)
        XCTAssertTrue(try LearningDerivation.rebuild([a,b,episode(record:one)],suppressed:[]).isEmpty)
        let rules=try LearningDerivation.rebuild([a,b,c],suppressed:[])
        let rule=try XCTUnwrap(rules.first)
        XCTAssertEqual(rule.scope,.technical);XCTAssertEqual(rule.adjustment,.conciseLead)
        XCTAssertEqual(Set(rule.supportIDs),Set([a.id,b.id,c.id]));XCTAssertEqual(rule.sessionCount,2)
        XCTAssertFalse(rule.suppressed);XCTAssertEqual(rule.expiresAt,1_900_000_000)
    }
    func testRecruiterAndTechnicalExamplesNeverCombineToReachTheThreshold()async throws{
        let a=try episode(),b=try episode(),recruiter=try episode(question:"Tell me about your background.")
        XCTAssertTrue(try LearningDerivation.rebuild([a,b,recruiter],suppressed:[]).isEmpty)
    }
    func testUndoSuppressionSurvivesRebuildAndRemovingSupportMakesRuleUnavailable()async throws{
        let examples=try [episode(),episode(),episode()]
        let rules=try LearningDerivation.rebuild(examples,suppressed:["technical:concise_lead"])
        XCTAssertTrue(try XCTUnwrap(rules.first).suppressed)
        let without=try LearningDerivation.rebuild(Array(examples.prefix(2)),suppressed:[])
        XCTAssertTrue(without.isEmpty)
        let tombstone=try LearningDerivation.rebuild([],suppressed:["technical:concise_lead"])
        XCTAssertTrue(try XCTUnwrap(tombstone.first).suppressed);XCTAssertTrue(tombstone.first?.supportIDs.isEmpty==true)
    }
    func testProjectionIncludesRepresentativeActualWordingAndRelevantUnresolvedPreparationWithSources()async throws{
        let examples=try [episode(),episode(),episode()],rules=try LearningDerivation.rebuild(examples,suppressed:[])
        let archive=LearningArchive(episodes:examples,rules:rules)
        let projection=LearningDerivation.project(archive,question:"How do bounded queues handle null items?",now:1_800_000_000)
        XCTAssertEqual(projection.adjustments,[.conciseLead])
        XCTAssertEqual(projection.examples.first?.text,"Keep bounded queues and make overload explicit.")
        XCTAssertTrue(projection.examples.first?.sourceID.contains(":1:")==true)
        XCTAssertTrue(projection.preparation.first?.text.contains("null items")==true)
        XCTAssertFalse(projection.supportIDs.isEmpty)
        XCTAssertLessThanOrEqual(try projection.encodedPayload().count,LearningBounds.projectionBytes)
        XCTAssertTrue(LearningDerivation.project(archive,question:"Tell me about your background.",now:1_800_000_000).adjustments.isEmpty)
        XCTAssertTrue(LearningDerivation.project(archive,question:"bounded queues",now:1_900_000_001).examples.isEmpty)
    }
}
