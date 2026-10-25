import Foundation
import RelayAudioBuffer
import XCTest
@testable import RelayNativeSession

private final class IngressProbe: @unchecked Sendable {
    private let lock=NSLock();private var values:[String]=[]
    func audio(_ event:NativeSessionEvent) { lock.withLock { values.append("audio-\(event.eventSequence)") } }
    func manual(_ request:NativeManualHelpRequest) { lock.withLock { values.append("manual-\(request.anchorEventSequence)") } }
    var entries:[String] { lock.withLock { values } }
}

@MainActor final class ManualHelpTests:XCTestCase {
    func testManualIssuancePreservesAudioSequenceAndPrecedesNextRealOnset() async throws {
        let probe=IngressProbe();let controller=NativeSessionController(onEvent:probe.audio)
        try controller.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,
            components:[2:SourceComponents(vad:ScriptVad([1:.start]),recognizer:RecordingRecognizer())])
        let first=try XCTUnwrap(controller.authority.snapshot())
        let request=try controller.issueManualHelp(expectedEventSequence:1,expectedLease:first,question:"Explain a dictionary.",enqueue:probe.manual)
        XCTAssertEqual(request.anchorEventSequence,1)
        XCTAssertGreaterThan(request.lease.presentationGeneration,first.presentationGeneration)
        controller.ingest(SessionAudioPacket(source:.remoteAudio,streamGeneration:1,sequence:1,hostTime:mach_absolute_time(),samples:Array(repeating:0.2,count:512)))
        for _ in 0..<100 where probe.entries.count<3 { try await Task.sleep(for:.milliseconds(1)) }
        XCTAssertEqual(probe.entries.prefix(3),["audio-1","manual-1","audio-2"])
        XCTAssertNotEqual(controller.authority.snapshot(),request.lease)
        controller.beginStop();await controller.waitForQuiescence();controller.finishStop(quiesced:true)
    }
    func testAlreadyStampedButUnforwardedAudioRejectsManualAnchorWithoutChangingLease() async throws {
        let probe=IngressProbe();let controller=NativeSessionController(onEvent:probe.audio)
        try controller.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,
            components:[2:SourceComponents(vad:ScriptVad([1:.start]),recognizer:RecordingRecognizer())])
        controller.ingest(SessionAudioPacket(source:.remoteAudio,streamGeneration:1,sequence:1,hostTime:mach_absolute_time(),samples:Array(repeating:0.2,count:512)))
        for _ in 0..<100 where probe.entries.count<2 { try await Task.sleep(for:.milliseconds(1)) }
        let current=try XCTUnwrap(controller.authority.snapshot())
        XCTAssertThrowsError(try controller.issueManualHelp(expectedEventSequence:1,expectedLease:current,question:"Explain a dictionary.",enqueue:probe.manual))
        XCTAssertEqual(controller.authority.snapshot(),current)
        XCTAssertEqual(probe.entries,["audio-1","audio-2"])
        controller.beginStop();await controller.waitForQuiescence();controller.finishStop(quiesced:true)
    }
    func testWrongLeaseCannotIssueAndThrowingIngressRetiresAdmission() async throws {
        let controller=NativeSessionController(onEvent:{_ in})
        try controller.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,
            components:[2:SourceComponents(vad:ScriptVad([:]),recognizer:RecordingRecognizer())])
        let first=try XCTUnwrap(controller.authority.snapshot())
        XCTAssertEqual(controller.authority.snapshot(),first)
        controller.authority.invalidate()
        XCTAssertThrowsError(try controller.issueManualHelp(expectedEventSequence:1,expectedLease:first,question:"Question?",enqueue:{_ in XCTFail()}))
        let current=try XCTUnwrap(controller.authority.snapshot())
        XCTAssertThrowsError(try controller.issueManualHelp(expectedEventSequence:1,expectedLease:current,question:"Question?",enqueue:{_ in throw NativeSessionError.transportClosed}))
        XCTAssertNil(controller.authority.snapshot());XCTAssertFalse(controller.isSourceActive(.remoteAudio))
        await controller.waitForQuiescence()
    }
}
