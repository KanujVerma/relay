import Foundation
import XCTest
import RelayContextComposition
import RelayNativeSession
@testable import RelaySessionPanel

@MainActor struct LearningTestEvents {
    var session=UUID(),epoch:UInt64=1,sequence:UInt64=0,emitted:UInt64=0
    let clock:WireValue = .object(["hostTicksAtAnchor":.uint(0),"uptimeNsAtAnchor":.uint(0),"nsNumer":.uint(1),"nsDenom":.uint(1)])
    var lease:PresentationLease{NativeSessionEvent(captureSessionID:session,sessionEpoch:epoch,eventSequence:sequence,presentationGeneration:2,kind:.eou,sourceCode:nil,streamGeneration:nil,emittedUptimeNanoseconds:emitted,payload:[:]).lease}
    mutating func event(_ kind:SessionEventKind,source:UInt32?=nil,payload:[String:WireValue]=[:])->NativeSessionEvent{
        sequence+=1;emitted+=1
        return NativeSessionEvent(captureSessionID:session,sessionEpoch:epoch,eventSequence:sequence,presentationGeneration:2,kind:kind,sourceCode:source,streamGeneration:source==nil ? nil:1,emittedUptimeNanoseconds:emitted,payload:payload)
    }
    mutating func start(_ store:SessionTranscriptStore){store.observe(event(.sessionStarted,payload:["selectedBundleID":.string("com.example.learning"),"microphoneEnabled":.bool(true)]))}
    mutating func final(_ index:UInt64,text:String,source:UInt32=2,into store:SessionTranscriptStore){
        let begin=index*100_000_000,finish=begin+50_000_000
        emitted=max(emitted,begin)
        store.observe(event(.speechStarted,source:source,payload:["activityID":.uint(index),"startHostTime":.uint(begin),"detectedUptimeNanoseconds":.uint(begin),"timebase":clock]))
        emitted=max(emitted,finish)
        store.observe(event(.speechEnded,source:source,payload:["activityID":.uint(index),"endHostTime":.uint(finish),"lastSpeechInputSequence":.uint(index*2),"timebase":clock]))
        let inner:[String:WireValue] = ["version":.uint(1),"status":.string("final"),"sourceCode":.uint(UInt64(source)),"streamGeneration":.uint(1),"segmentID":.uint(index),"revision":.uint(1),"startHostTime":.uint(begin),"endHostTime":.uint(finish),"finalizedUptimeNanoseconds":.uint(finish),"receivedUptimeNanoseconds":.uint(finish),"text":.string(text),"confidence":.null,"timebase":clock]
        store.observe(event(.eou,source:source,payload:["event":.object(inner),"activityID":.uint(index),"firstInputSequence":.uint(index*2-1),"lastInputSequence":.uint(index*2),"lastSpeechInputSequence":.uint(index*2),"activityClosed":.bool(true)]))
    }
}

/// Every speech fixture passes the original transcript validator. No model
/// output or synthesized final can substitute for a native source receipt.
@MainActor final class LearningMemoryTests:XCTestCase {
    private func rig()->(LearningSessionMemory,SessionTranscriptStore,LearningTestEvents){
        let memory=LearningSessionMemory(),transcript=SessionTranscriptStore()
        transcript.onHistoryObservation=memory.observe
        var events=LearningTestEvents();events.start(transcript)
        return(memory,transcript,events)
    }
    private func available(_ memory:LearningSessionMemory,_ events:LearningTestEvents,at:UInt64=250_000_000,visible:Bool=true){
        let binding=PanelRequestBinding(lease:events.lease,requestID:UUID(),eventSequence:events.sequence)
        memory.available(binding:binding,replacement:1,lead:"Explain bounded queues, then make overload explicit.",points:["Keep every request inside a fixed capacity."],guideRevision:nil,visible:visible,at:at)
    }
    func testOriginalQuestionAvailableCardSpokenReplyAndRemoteContinuationKeepExactSources()async throws{
        let(memory,transcript,initial)=rig();var e=initial
        e.final(1,text:"How should a bounded queue handle overload?",into:transcript);available(memory,e)
        e.final(3,text:"Keep bounded queues and make overload explicit.",source:1,into:transcript)
        e.final(4,text:"What about a full queue?",into:transcript)
        let episode=try XCTUnwrap(memory.episodes.first)
        XCTAssertEqual(episode.question.eventSequence.value,4);XCTAssertEqual(episode.reply.source,.microphone)
        XCTAssertEqual(episode.continuation.source,.selectedAppAudio);XCTAssertEqual(episode.suggestion.availableAt.value,250_000_000)
        XCTAssertTrue(episode.signal.temporallyEligible);XCTAssertTrue(episode.signal.possibleUptake)
        XCTAssertEqual(episode.reply.captureSessionID,episode.question.captureSessionID)
    }
    func testSpeechBeforeAvailabilityHiddenCardOverlapAndSourceGapNeverSupportAutomaticStyle()async throws{
        for variant in 0..<4{
            let(memory,transcript,initial)=rig();var e=initial
            e.final(1,text:"How should a bounded queue handle overload?",into:transcript)
            available(memory,e,at:variant==0 ? 350_000_000:250_000_000,visible:variant != 1)
            e.final(3,text:"Keep bounded queues and make overload explicit.",source:1,into:transcript)
            if variant==3{transcript.observe(e.event(.discontinuity,source:1,payload:["reasonCode":.string("source_changed")]))}
            e.final(variant==2 ? 2:4,text:"What about a full queue?",into:transcript)
            XCTAssertFalse(memory.episodes.contains{$0.signal.eligibleForStyle},"variant \(variant)")
        }
    }
    func testSourceLinkedDecisionsAndUnresolvedFollowupsSurviveRawWindowEviction()async throws{
        let(memory,transcript,initial)=rig();var e=initial
        e.final(1,text:"We decided timestamps must use UTC and retention is seven days.",into:transcript)
        for n in 2...25{e.final(UInt64(n),text:"A short unrelated discussion \(n).",into:transcript)}
        e.final(26,text:"We still need to clarify how retention handles a legal hold.",into:transcript)
        let projection=memory.projection(question:"What should retention do next?")
        XCTAssertTrue(projection.contains{$0.text.contains("seven days")})
        XCTAssertTrue(projection.contains{$0.text.contains("legal hold")})
        XCTAssertTrue(projection.allSatisfy{!$0.sourceID.isEmpty})
        memory.pause();XCTAssertFalse(memory.projection(question:"retention").isEmpty)
        memory.end();XCTAssertTrue(memory.projection(question:"retention").isEmpty)
    }
    func testLateFinalFromOldCaptureAndDuplicateAvailableReceiptCannotReplaceCurrentEpisode()async throws{
        let(memory,transcript,initial)=rig();var e=initial
        e.final(1,text:"How should a bounded queue handle overload?",into:transcript);available(memory,e)
        memory.pause();memory.observe(.init(event:e.event(.sessionStarted)))
        e.final(3,text:"Keep bounded queues and make overload explicit.",source:1,into:transcript)
        e.final(4,text:"What about a full queue?",into:transcript)
        XCTAssertTrue(memory.episodes.isEmpty)
    }
    func testTwoOriginalAvailableCardsBeforeReplyCarryCompetingCardAmbiguity()async throws{
        let(memory,transcript,initial)=rig();var e=initial
        e.final(1,text:"How should a bounded queue handle overload?",into:transcript);available(memory,e)
        e.final(2,text:"How should bounded queues handle capacity?",into:transcript);available(memory,e,at:275_000_000)
        e.final(3,text:"Keep bounded queues and make overload explicit.",source:1,into:transcript)
        e.final(4,text:"What about a full queue?",into:transcript)
        let episode=try XCTUnwrap(memory.episodes.first)
        XCTAssertTrue(episode.signal.flags.contains("competing_card"))
        XCTAssertFalse(episode.signal.eligibleForStyle)
    }
    func testFreshValidatedCaptureRejectsLateOriginalFinalsFromOldCapture()async throws{
        let(memory,oldTranscript,initial)=rig();var old=initial
        old.final(1,text:"How should a bounded queue handle overload?",into:oldTranscript);available(memory,old)
        memory.pause()
        let freshTranscript=SessionTranscriptStore();freshTranscript.onHistoryObservation=memory.observe
        var fresh=LearningTestEvents();fresh.start(freshTranscript)
        old.final(3,text:"Keep bounded queues and make overload explicit.",source:1,into:oldTranscript)
        old.final(4,text:"What about a full queue?",into:oldTranscript)
        XCTAssertTrue(memory.episodes.isEmpty)
        fresh.final(1,text:"How should a bounded queue handle overload?",into:freshTranscript);available(memory,fresh)
        fresh.final(3,text:"Keep bounded queues and make overload explicit.",source:1,into:freshTranscript)
        fresh.final(4,text:"What about a full queue?",into:freshTranscript)
        XCTAssertEqual(memory.episodes.count,1);XCTAssertEqual(memory.episodes.first?.question.captureSessionID,fresh.session)
    }
    func testExactDuplicateAvailableBindingCannotReplaceItsOriginalCardOrCreateAnotherEpisode()async throws{
        let(memory,transcript,initial)=rig();var e=initial
        e.final(1,text:"How should a bounded queue handle overload?",into:transcript)
        let binding=PanelRequestBinding(lease:e.lease,requestID:UUID(),eventSequence:e.sequence)
        memory.available(binding:binding,replacement:1,lead:"Explain bounded queues, then make overload explicit.",points:[],guideRevision:nil,visible:true,at:250_000_000)
        memory.available(binding:binding,replacement:2,lead:"Changed duplicate must not replace the original.",points:[],guideRevision:nil,visible:true,at:260_000_000)
        e.final(3,text:"Keep bounded queues and make overload explicit.",source:1,into:transcript);e.final(4,text:"What about a full queue?",into:transcript)
        XCTAssertEqual(memory.episodes.count,1);XCTAssertEqual(memory.episodes.first?.suggestion.replacement.value,1)
        XCTAssertEqual(memory.episodes.first?.suggestion.text,"Explain bounded queues, then make overload explicit.")
    }
    func testUnrelatedRecruiterQuestionDoesNotReceiveTechnicalDecisionAsCurrentContext()async throws{
        let(memory,transcript,initial)=rig();var e=initial
        e.final(1,text:"We decided timestamps must use UTC and retention is seven days.",into:transcript)
        XCTAssertTrue(memory.projection(question:"Tell me about your background.").isEmpty)
    }
    func testRelevantOriginalExplanationSurvivesMoreThanTwelveUtterancesWithoutAConstraintKeyword()async throws{
        let(memory,transcript,initial)=rig();var e=initial
        e.final(1,text:"The existing metrics count refunds against original order date.",source:1,into:transcript)
        for n in 2...25{e.final(UInt64(n),text:"A short unrelated discussion \(n).",into:transcript)}
        let projection=memory.projection(question:"How are refunds dated?")
        XCTAssertTrue(projection.contains{$0.text.contains("original order date") && $0.source == .microphone})
        XCTAssertTrue(memory.projection(question:"Tell me about your background.").isEmpty)
    }
}
