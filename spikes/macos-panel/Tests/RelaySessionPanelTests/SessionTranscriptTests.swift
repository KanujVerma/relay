import Foundation
import XCTest
import RelayNativeSession
@testable import RelaySessionPanel

@MainActor final class SessionTranscriptTests:XCTestCase {
    private let session=UUID()
    private var sequence:UInt64=0
    private let timebase:WireValue = .object(["hostTicksAtAnchor":.uint(0),"uptimeNsAtAnchor":.uint(0),"nsNumer":.uint(1),"nsDenom":.uint(1)])
    private func event(_ kind:SessionEventKind,_ source:UInt32?=nil,_ payload:[String:WireValue]=[:])->NativeSessionEvent {
        sequence+=1
        return NativeSessionEvent(captureSessionID:session,sessionEpoch:1,eventSequence:sequence,presentationGeneration:2,
            kind:kind,sourceCode:source,streamGeneration:source==nil ? nil:1,emittedUptimeNanoseconds:1_000_000,
            payload:payload,requestID:kind == .eou && source==2 ? UUID():nil)
    }
    private func final(_ index:UInt64,text:String,source:UInt32,store:SessionTranscriptStore,
                       alter:((inout [String:WireValue])->Void)? = nil) {
        store.observe(event(.speechStarted,source,["activityID":.uint(index),"startHostTime":.uint(index*100),"detectedUptimeNanoseconds":.uint(1000),"timebase":timebase]))
        store.observe(event(.speechEnded,source,["activityID":.uint(index),"endHostTime":.uint(index*100+50),"lastSpeechInputSequence":.uint(index*2),"timebase":timebase]))
        var inner:[String:WireValue] = ["version":.uint(1),"status":.string("final"),"sourceCode":.uint(UInt64(source)),
            "streamGeneration":.uint(1),"segmentID":.uint(index),"revision":.uint(1),"startHostTime":.uint(index*100),
            "endHostTime":.uint(index*100+50),"finalizedUptimeNanoseconds":.uint(100_000),
            "receivedUptimeNanoseconds":.uint(100_001),"text":.string(text),"confidence":.null,"timebase":timebase]
        alter?(&inner)
        store.observe(event(.eou,source,["event":.object(inner),"activityID":.uint(index),"firstInputSequence":.uint(index*2-1),
            "lastInputSequence":.uint(index*2),"activityClosed":.bool(true),"lastSpeechInputSequence":.uint(index*2)]))
    }
    func testOnlyAssociatedActualFinalSchemaCanProduceSourceLabelledRows() {
        let store=SessionTranscriptStore()
        store.observe(event(.sessionStarted,nil,["selectedBundleID":.string("com.example.fixture"),"microphoneEnabled":.bool(true)]))
        store.observe(event(.eou,2,["event":.object(["text":.string("Invented without a closed activity")])]))
        XCTAssertTrue(store.snapshot.rows.isEmpty)
        final(1,text:"A remote question.",source:2,store:store)
        final(2,text:"A microphone reply.",source:1,store:store)
        XCTAssertEqual(store.snapshot.rows.map(\.text),["A remote question.","A microphone reply."])
        XCTAssertEqual(store.snapshot.rows.map{ $0.source.label },["Selected app audio","Microphone"])
        store.end();final(3,text:"Late private text.",source:2,store:store)
        XCTAssertTrue(store.snapshot.rows.isEmpty)
    }
    func testWholeRowsAreBoundedAndPauseCannotBeReopenedByLateFinals() {
        let store=SessionTranscriptStore();store.observe(event(.sessionStarted))
        let text=String(repeating:"x",count:1200)
        for index in 1...70{final(UInt64(index),text:text,source:2,store:store)}
        XCTAssertLessThanOrEqual(store.snapshot.rows.count,64)
        XCTAssertLessThanOrEqual(store.snapshot.rows.reduce(0){$0+$1.text.utf8.count},65_536)
        XCTAssertEqual(store.snapshot.rows.last?.text,text)
        XCTAssertGreaterThan(store.snapshot.omittedRowCount,0)
        let before=store.snapshot.rows
        store.pause();final(71,text:"late",source:2,store:store)
        XCTAssertEqual(store.snapshot.rows,before)
        XCTAssertEqual(store.snapshot.phase,.paused)
    }
    func testExactFinalSchemaRejectsUnknownMissingAndInvalidConfidence() {
        let changes:[(inout [String:WireValue])->Void] = [
            {$0["extra"] = .string("unowned")},{$0.removeValue(forKey:"confidence")},
            {$0["confidence"] = .bool(true)},{$0["confidence"] = .uint(2)},
            {$0["sourceCode"] = .uint(1)},{$0["text"] = .string("")},
            {$0["text"] = .string(String(repeating:"x",count:1201))}]
        for change in changes {
            sequence=0;let store=SessionTranscriptStore();store.observe(event(.sessionStarted))
            final(1,text:"A final.",source:2,store:store,alter:change)
            XCTAssertTrue(store.snapshot.rows.isEmpty)
        }
    }
    func testOriginalIdentityDeduplicatesAndConsentRevocationPurgesOnlyItsSource() {
        let store=SessionTranscriptStore();store.observe(event(.sessionStarted))
        final(2,text:"Later source time.",source:2,store:store)
        final(1,text:"Earlier source time.",source:1,store:store)
        final(2,text:"Duplicate segment.",source:2,store:store)
        XCTAssertEqual(store.snapshot.rows.map(\.text),["Earlier source time.","Later source time."])
        store.observe(event(.sourceUnavailable,2,["reasonCode":.string("consent_revoked")]))
        XCTAssertEqual(store.snapshot.rows.map(\.source),[.microphone])
        XCTAssertEqual(store.snapshot.selectedAudio,.unavailable)
        // A real native sequence gap seals the read view; a later final cannot restore text.
        sequence+=1;final(3,text:"After the gap.",source:1,store:store)
        XCTAssertEqual(store.snapshot.phase,.unavailable);XCTAssertEqual(store.snapshot.rows.count,1)
    }
}
