import Foundation
import XCTest
import RelayContextComposition
@testable import RelaySessionPanel

@MainActor final class LearningInteractionProjectionTests:XCTestCase {
    private func episode(detail:String?=nil,long:Bool=false)throws->(LearningSessionMemory,LearningEpisode){
        let memory=LearningSessionMemory(),transcript=SessionTranscriptStore();transcript.onHistoryObservation=memory.observe
        var e=LearningTestEvents();e.start(transcript)
        e.final(1,text:"How should bounded queues handle overload?"+(long ? String(repeating:" Discuss capacity.",count:20):""),into:transcript)
        let binding=PanelRequestBinding(lease:e.lease,requestID:UUID(),eventSequence:e.sequence)
        memory.available(binding:binding,replacement:1,lead:"Explain bounded queues, then make overload explicit.",points:["Keep requests inside a fixed capacity."],detail:detail,guideRevision:nil,visible:true,at:250_000_000)
        e.final(3,text:"Keep bounded queues and make overload explicit."+(long ? String(repeating:" Check capacity.",count:20):""),source:1,into:transcript)
        e.final(4,text:"What about null items?",into:transcript)
        return(memory,try XCTUnwrap(memory.episodes.first))
    }
    func testProjectedInteractionKeepsAllOriginalIdentitiesAndExcerptLabels()async throws{
        let(memory,episode)=try episode(long:true)
        let projection=try XCTUnwrap(memory.interactionProjection(question:"bounded queues"))
        XCTAssertEqual(projection.question.sourceID,episode.question.id)
        XCTAssertEqual(projection.reply.sourceID,episode.reply.id)
        XCTAssertEqual(projection.continuation.sourceID,episode.continuation.id)
        XCTAssertEqual(projection.suggestion.requestID,episode.suggestion.requestID)
        XCTAssertEqual(projection.suggestion.cardHash,episode.suggestion.cardHash)
        XCTAssertTrue(projection.question.excerpt);XCTAssertTrue(projection.reply.excerpt)
        XCTAssertFalse(projection.continuation.excerpt)
        var request=LearningRequestProjection(scope:.technical);request.interactions=[projection]
        XCTAssertLessThanOrEqual(try request.encodedPayload().count,2048)
    }
    func testFullDetailHasContentIdentityButNeverSuppliesUnobservedUptakeTokens()async throws{
        let(memory,one)=try episode(detail:"code:python\nreturn distinctive_hidden_token")
        let(_,two)=try episode(detail:"code:python\nreturn a_different_hidden_token")
        XCTAssertNotEqual(one.suggestion.cardHash,two.suggestion.cardHash)
        XCTAssertEqual(one.suggestion.detail,"code:python\nreturn distinctive_hidden_token")
        XCTAssertFalse(one.suggestion.text.contains("distinctive_hidden_token"))
        let projection=try XCTUnwrap(memory.interactionProjection(question:"bounded queues"))
        XCTAssertTrue(projection.suggestion.excerpt)
        XCTAssertFalse(projection.suggestion.text.contains("distinctive_hidden_token"))
    }
    func testOldInteractionDoesNotAttributeOtherSpeakersOrAssistantTextToMicrophoneQuote()async throws{
        let memory=LearningSessionMemory(),transcript=SessionTranscriptStore();transcript.onHistoryObservation=memory.observe
        var e=LearningTestEvents();e.start(transcript)
        e.final(1,text:"How should bounded queues handle overload?",into:transcript)
        memory.available(binding:PanelRequestBinding(lease:e.lease,requestID:UUID(),eventSequence:e.sequence),replacement:1,
            lead:"Explain bounded queues and overload.",points:[],guideRevision:nil,visible:true,at:250_000_000)
        e.final(3,text:"Keep bounded queues and make overload explicit.",source:1,into:transcript)
        e.final(4,text:"Discuss overload recovery?",into:transcript)
        let original=try XCTUnwrap(memory.episodes.first)
        for n in 5...80{e.final(UInt64(n),text:"Unrelated discussion \(n).",into:transcript)}
        let quotes=memory.projection(question:"bounded queues overload")
        for quote in quotes where quote.source == .microphone{XCTAssertEqual(quote.text,original.reply.text)}
        let chain=try XCTUnwrap(memory.interactionProjection(question:"bounded queues"))
        XCTAssertEqual(chain.reply.sourceID,original.reply.id);XCTAssertEqual(chain.continuation.sourceID,original.continuation.id)
        XCTAssertTrue(memory.evidenceGap)
    }
}
