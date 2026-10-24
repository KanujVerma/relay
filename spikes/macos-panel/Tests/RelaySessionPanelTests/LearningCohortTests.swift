import Foundation
import XCTest
import RelayContextComposition
@testable import RelaySessionPanel

@MainActor final class LearningCohortTests:XCTestCase {
    private func episode(request:UUID,record:UUID,question:String,expires:TimeInterval)throws->LearningEpisode{
        let memory=LearningSessionMemory(),transcript=SessionTranscriptStore();transcript.onHistoryObservation=memory.observe
        var e=LearningTestEvents();e.start(transcript);e.final(1,text:question,into:transcript)
        memory.available(binding:PanelRequestBinding(lease:e.lease,requestID:request,eventSequence:e.sequence),replacement:1,
            lead:"Explain bounded queues, then make overload explicit.",points:["Keep every request inside a fixed capacity and discuss a clear rejection policy."],guideRevision:nil,visible:true,at:250_000_000)
        e.final(3,text:"Keep bounded queues and make overload explicit.",source:1,into:transcript);e.final(4,text:"Continue.",into:transcript)
        return try XCTUnwrap(memory.episodes.first).retained(recordID:record,expiresAt:expires)
    }
    func testSelectedExampleAndTwoSessionProofStayInsideTheActualBoundedSupportCohort()async throws{
        let firstRecord=UUID(),secondRecord=UUID()
        var episodes:[LearningEpisode]=[]
        for n in 1...8{
            let request=try XCTUnwrap(UUID(uuidString:String(format:"00000000-0000-0000-0000-%012d",n)))
            episodes.append(try episode(request:request,record:firstRecord,question:"How should bounded queues handle overload?",expires:1_900_000_000))
        }
        let selected=try episode(request:XCTUnwrap(UUID(uuidString:"ffffffff-ffff-ffff-ffff-ffffffffffff")),record:secondRecord,
            question:"How should bounded queues handle null items?",expires:1_880_000_000)
        episodes.append(selected)
        let rules=try LearningDerivation.rebuild(episodes,suppressed:[])
        let projection=LearningDerivation.project(LearningArchive(episodes:episodes,rules:rules),question:"bounded queues null items",now:1_800_000_000)
        XCTAssertEqual(projection.examples.first?.sourceID,selected.reply.id)
        XCTAssertTrue(projection.supportIDs.contains(selected.id))
        XCTAssertEqual(projection.supportIDs.count,3)
        let included=episodes.filter{projection.supportIDs.contains($0.id)}
        XCTAssertEqual(Set(included.compactMap(\.recordID)).count,2)
        XCTAssertEqual(projection.sourceRecordIDs,Set(included.compactMap(\.recordID)))
        XCTAssertEqual(projection.expiresAt,included.compactMap(\.expiresAt).min())
    }
}
