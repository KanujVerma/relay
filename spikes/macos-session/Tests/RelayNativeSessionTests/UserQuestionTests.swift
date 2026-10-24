import Foundation
import RelayAudioBuffer
import XCTest
@testable import RelayNativeSession

private final class UserIngressProbe:@unchecked Sendable {
    private let lock=NSLock();private var entries:[String]=[]
    func audio(_ event:NativeSessionEvent){lock.withLock{entries.append("audio-\(event.eventSequence)")}}
    func user(_ request:NativeUserQuestionRequest){lock.withLock{entries.append("user-\(request.anchorEventSequence)")}}
    var values:[String]{lock.withLock{entries}}
}

@MainActor final class UserQuestionTests:XCTestCase {
    func testFreshUserIssuanceAnchorsStampedAudioWithoutRestampingItsOrder() async throws {
        let probe=UserIngressProbe();let controller=NativeSessionController(onEvent:probe.audio)
        try controller.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,
            components:[2:SourceComponents(vad:ScriptVad([1:.start]),recognizer:RecordingRecognizer())])
        controller.ingest(SessionAudioPacket(source:.remoteAudio,streamGeneration:1,sequence:1,
            hostTime:mach_absolute_time(),samples:Array(repeating:0.2,count:512)))
        for _ in 0..<100 where probe.values.count<2{try await Task.sleep(for:.milliseconds(1))}
        let original=try XCTUnwrap(controller.authority.snapshot())
        let issued=try controller.issueUserQuestion(expectedLease:original,intent:.ask,
            question:"Explain queues.",baseRequestID:nil,enqueue:probe.user)
        XCTAssertEqual(issued.anchorEventSequence,2)
        XCTAssertEqual(probe.values,["audio-1","audio-2","user-2"])
        XCTAssertEqual(issued.lease.presentationGeneration,original.presentationGeneration+1)
        let json=try JSONSerialization.jsonObject(with:issued.encodedJSON()) as! [String:Any]
        XCTAssertEqual(json.count,11);XCTAssertEqual(json["kind"] as? String,"user_question_request")
        XCTAssertEqual(json["question"] as? String,"Explain queues.")
        controller.beginStop();await controller.waitForQuiescence();controller.finishStop(quiesced:true)
    }
    func testCancelTargetsOnlyTheActualIssuedRequestAndCarriesOriginalRetirement() async throws {
        let controller=NativeSessionController(onEvent:{_ in})
        try controller.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,
            components:[2:SourceComponents(vad:ScriptVad([:]),recognizer:RecordingRecognizer())])
        let first=try controller.issueUserQuestion(expectedLease:try XCTUnwrap(controller.authority.snapshot()),
            intent:.ask,question:"Explain queues.",baseRequestID:nil,enqueue:{_ in})
        XCTAssertThrowsError(try controller.issueAnswerCancellation(expectedLease:first.lease,targetRequestID:UUID(),enqueue:{_ in XCTFail()}))
        XCTAssertEqual(controller.authority.snapshot(),first.lease)
        let stopped=try controller.issueAnswerCancellation(expectedLease:first.lease,targetRequestID:first.requestID,enqueue:{_ in})
        XCTAssertEqual(stopped.anchorEventSequence,1)
        let json=try JSONSerialization.jsonObject(with:stopped.encodedJSON()) as! [String:Any]
        XCTAssertEqual(json.count,9)
        let denied=try JSONSerialization.jsonObject(with:stopped.retirementJSON()) as! [String:Any]
        XCTAssertEqual(denied.count,7)
        XCTAssertEqual(denied["requestID"] as? String,first.requestID.uuidString.lowercased())
        XCTAssertEqual(denied["presentationGeneration"] as? UInt64,first.lease.presentationGeneration)
        XCTAssertThrowsError(try controller.issueAnswerCancellation(expectedLease:stopped.lease,targetRequestID:first.requestID,enqueue:{_ in XCTFail()}))
        controller.beginStop();await controller.waitForQuiescence();controller.finishStop(quiesced:true)
    }
    func testMalformedOrStaleActionsCannotChangeAuthority() async throws {
        let controller=NativeSessionController(onEvent:{_ in})
        try controller.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,
            components:[2:SourceComponents(vad:ScriptVad([:]),recognizer:RecordingRecognizer())])
        let lease=try XCTUnwrap(controller.authority.snapshot())
        for text in ["", "two\nlines",String(repeating:"🧠",count:126)] {
            XCTAssertThrowsError(try controller.issueUserQuestion(expectedLease:lease,intent:.ask,question:text,baseRequestID:nil,enqueue:{_ in XCTFail()}))
            XCTAssertEqual(controller.authority.snapshot(),lease)
        }
        XCTAssertThrowsError(try controller.issueUserQuestion(expectedLease:lease,intent:.helpCurrent,question:nil,baseRequestID:UUID(),enqueue:{_ in XCTFail()}))
        let issued=try controller.issueUserQuestion(expectedLease:lease,intent:.ask,question:"Explain queues.",baseRequestID:nil,enqueue:{_ in})
        XCTAssertThrowsError(try controller.issueUserQuestion(expectedLease:lease,intent:.ask,question:"Stale question?",baseRequestID:nil,enqueue:{_ in XCTFail()}))
        XCTAssertEqual(controller.authority.snapshot(),issued.lease)
        controller.beginStop();await controller.waitForQuiescence();controller.finishStop(quiesced:true)
    }
    func testLastSourceLossCannotIssueFreshTypedAuthority()async throws {
        let controller=NativeSessionController(onEvent:{_ in})
        try controller.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,
            components:[2:SourceComponents(vad:ScriptVad([:]),recognizer:RecordingRecognizer())])
        let first=try controller.issueUserQuestion(expectedLease:try XCTUnwrap(controller.authority.snapshot()),intent:.ask,
            question:"Explain queues.",baseRequestID:nil,enqueue:{_ in})
        controller.sourceUnavailable(source:.remoteAudio,generation:1,reason:.selectedAppUnavailable)
        let lease=try XCTUnwrap(controller.authority.snapshot())
        XCTAssertThrowsError(try controller.issueUserQuestion(expectedLease:lease,intent:.ask,question:"Explain caches.",baseRequestID:nil,enqueue:{_ in XCTFail()}))
        XCTAssertThrowsError(try controller.issueUserQuestion(expectedLease:lease,intent:.helpCurrent,question:nil,baseRequestID:first.requestID,enqueue:{_ in XCTFail()}))
        controller.beginStop();await controller.waitForQuiescence();controller.finishStop(quiesced:true)
    }
}
