import Darwin
import Foundation
import XCTest
import RelayNativeSession
import RelayAudioBuffer
@testable import RelaySessionCapture

private actor ProductionSelectionVAD:RecognitionWatermarkDetector {
    nonisolated let chunkSamples=5120
    private var count=0
    func accept(_ samples:[Float])async throws->[SpeechBoundary]{throw NativeSessionError.invalidFrame}
    func observe(_ samples:[Float])async throws->SpeechActivityObservation{
        count+=1
        if count==1{return SpeechActivityObservation(boundaries:[SpeechBoundary(kind:.start,sampleIndex:0)],processedSamples:5120,safePrefixEnd:5120)}
        return SpeechActivityObservation(boundaries:[SpeechBoundary(kind:.end,sampleIndex:10240)],processedSamples:10240,safePrefixEnd:nil)
    }
}
private final class ProductionSpeechEvents:@unchecked Sendable {
    private let lock=NSLock();private var values:[NativeSessionEvent]=[]
    func append(_ event:NativeSessionEvent){lock.withLock{values.append(event)}}
    var events:[NativeSessionEvent]{lock.withLock{values}}
}

@MainActor final class ProductionSpeechSelectionTests:XCTestCase {
    private func until(_ predicate:()async->Bool)async throws{
        for _ in 0..<1500{if await predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NativeSessionError.modelUnavailable
    }
    private func packet(_ sequence:UInt64)->SessionAudioPacket{
        let clock=NativeClockCalibration.now()
        return SessionAudioPacket(source:.remoteAudio,streamGeneration:1,sequence:sequence,
            hostTime:mach_absolute_time()-UInt64(2_000_000_000)*clock.nsDenom/clock.nsNumer,
            samples:Array(repeating:Float(sequence),count:5120))
    }
    func testActualNormalFactoryAssemblyChoosesPrefixBeforeClosureWithoutModelDownload()async throws{
        let backend=HintRecognizer(),recognizer=FluidClosedActivityRecognizer(backend:backend)
        // The exact same assembly function is called after actual local model
        // preparation by NativeCaptureSession's normal convenience initializer.
        let components=NativeCaptureSession.productionSpeechComponents(vad:ProductionSelectionVAD(),recognizer:recognizer)
        let events=ProductionSpeechEvents()
        let actual=NativeSessionController(onEvent:events.append)
        addTeardownBlock{actual.beginStop();await actual.waitForQuiescence();actual.finishStop(quiesced:true)}
        try actual.start(selectedBundleID:"com.example.production-speech-selection",microphoneEnabled:false,components:[2:components])
        actual.ingest(packet(1));try await until{await backend.received.count==5120}
        XCTAssertFalse(events.events.contains{$0.kind == .eou})
        actual.ingest(packet(2));try await until{events.events.contains{$0.kind == .eou}}
        let received=await backend.received,finishes=await backend.finishes
        var original=Array(repeating:Float(1),count:5120);original+=Array(repeating:Float(2),count:5120)
        XCTAssertEqual(received,original);XCTAssertEqual(finishes,1)
        XCTAssertEqual(events.events.filter{$0.kind == .eou}.count,1)
    }
}
