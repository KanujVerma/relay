import AVFoundation
import Darwin
import Foundation
import XCTest
import RelayNativeSession
@testable import RelaySessionCapture
import RelaySessionPanel

@MainActor private final class OfflinePanelOutcome {
    let panel:SessionPanelController
    var failed=false
    init(authority:SessionPresentationAuthority){panel=SessionPanelController(authority:authority)}
}

/// Real local speech -> real native framing/helper -> the panel's real reducer.
/// Only the model answer is the existing injected synthetic fixture.
@MainActor final class OfflineSpeechPanelTests:XCTestCase {
    func testFictionalAudioAutomaticallyReachesTheRealAnswerPanel()async throws {
        let env=ProcessInfo.processInfo.environment
        guard env["RELAY_RUN_OFFLINE_MANAGED_SPEECH"]=="1",let cache=env["RELAY_OFFLINE_SPEECH_CACHE"],
              let audio=env["RELAY_OFFLINE_SYNTHETIC_AUDIO"],let python=env["RELAY_TEST_PYTHON"] else {
            throw XCTSkip("Explicit public-model/fictional-audio/owned-helper acceptance only; no capture or download.")
        }
        let assets=try XCTUnwrap(SpeechAssetStore(directory:URL(fileURLWithPath:cache)).cachedAssets())
        let url=URL(fileURLWithPath:audio)
        let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size>4096,size<2_000_000 else{throw NativeSessionError.invalidFrame}
        let file=try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
        guard file.processingFormat.sampleRate==16_000,file.processingFormat.channelCount==1,
              file.length>0,file.length<=160_000,
              let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length)) else{throw NativeSessionError.invalidFrame}
        try file.read(into:buffer)
        let channel=try XCTUnwrap(buffer.floatChannelData?[0])
        let speech=Array(UnsafeBufferPointer(start:channel,count:Int(buffer.frameLength)))
        XCTAssertTrue(speech.allSatisfy(\.isFinite));XCTAssertTrue(speech.contains{abs($0)>0.01})
        let vad=try await FluidSpeechActivityDetector.local(compiledModel:assets.vadCompiledModel)
        let recognizer=try await FluidClosedActivityRecognizer.local(root:assets.asrModelRoot)
        let authority=SessionPresentationAuthority(),outcome=OfflinePanelOutcome(authority:authority)
        let answers=BoundedMainDelivery<Data>(),events=BoundedMainDelivery<NativeSessionEvent>()
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let helper=HelperTransport(root:root,python:URL(fileURLWithPath:python),mode:.fixture,role:"developer",onFrame:{ data in
            try answers.enqueue(data,byteCount:data.count){ data in
                do{_ = try outcome.panel.accept(data)}catch{outcome.failed=true;authority.stop()}
            }
        },onFailure:{Task{@MainActor in outcome.failed=true;authority.stop()}})
        let native=NativeSessionController(authority:authority,onEvent:{ event in
            try events.enqueue(event,byteCount:event.encodedFrame().count){ event in
                outcome.panel.observe(event)
                do{try helper.send(event)}catch{outcome.failed=true;authority.stop()}
            }
        })
        try helper.start()
        do {
            try native.start(selectedBundleID:"com.example.offline-synthetic",microphoneEnabled:false,
                components:[2:SourceComponents(vad:vad,recognizer:recognizer)])
            let samples=Array(repeating:Float(0),count:8_000)+speech+Array(repeating:Float(0),count:32_000)
            var sequence:UInt64=1
            // Pace the file like real 32ms PCM delivery; no real source/permission.
            for offset in stride(from:0,to:samples.count,by:512) {
                var frame=Array(samples[offset..<min(offset+512,samples.count)])
                frame+=Array(repeating:0,count:512-frame.count)
                native.ingest(SessionAudioPacket(source:.remoteAudio,streamGeneration:1,sequence:sequence,hostTime:mach_absolute_time(),samples:frame))
                sequence+=1
                try await Task.sleep(for:.milliseconds(32))
                if outcome.failed{break}
            }
            for _ in 0..<2500 {
                if outcome.panel.snapshot.card != nil || outcome.failed{break}
                try await Task.sleep(for:.milliseconds(2))
            }
            XCTAssertFalse(outcome.failed)
            let question=try XCTUnwrap(outcome.panel.snapshot.question).lowercased()
            XCTAssertTrue(question.contains("python") && question.contains("list"))
            XCTAssertNotNil(outcome.panel.snapshot.card)
            XCTAssertEqual(outcome.panel.snapshot.status,"Talking points")
            print("OFFLINE_AUDIO_TO_PANEL automatic_question=true actual_vad_asr=true actual_helper=true synthetic_answer=true card_visible_in_reducer=true")
        }catch{
            native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
            await helper.shutdownAndWait();throw error
        }
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
        await helper.shutdownAndWait()
    }
}
