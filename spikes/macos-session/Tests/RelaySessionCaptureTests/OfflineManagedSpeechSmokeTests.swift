import AVFoundation
import Darwin
import Foundation
import XCTest
@testable import RelaySessionCapture
import RelayNativeSession

/// Explicit local model acceptance, never an ordinary CI download/load path.
/// Inputs are the verified public cache and a generated fictional WAVE file.
final class OfflineManagedSpeechSmokeTests:XCTestCase {
    func testTwoIndependentLocalSourcesLoadAndRecognizeFictionalSpeech()async throws {
        let environment=ProcessInfo.processInfo.environment
        guard environment["RELAY_RUN_OFFLINE_MANAGED_SPEECH"] == "1",
              let cache=environment["RELAY_OFFLINE_SPEECH_CACHE"],
              let audio=environment["RELAY_OFFLINE_SYNTHETIC_AUDIO"] else {
            throw XCTSkip("Explicit offline model smoke needs the public cache and generated fictional audio; no capture or download.")
        }
        let store=try SpeechAssetStore(directory:URL(fileURLWithPath:cache))
        let assets=try XCTUnwrap(store.cachedAssets())
        let input=URL(fileURLWithPath:audio)
        let size=try input.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size>4096,size<=2_000_000 else{throw NativeSessionError.invalidFrame}
        let file=try AVAudioFile(forReading:input,commonFormat:.pcmFormatFloat32,interleaved:false)
        guard file.processingFormat.sampleRate==16_000,file.processingFormat.channelCount==1,
              file.length>0,file.length<=160_000,
              let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length)) else {
            throw NativeSessionError.invalidFrame
        }
        try file.read(into:buffer)
        let channel=try XCTUnwrap(buffer.floatChannelData?[0])
        let samples=Array(UnsafeBufferPointer(start:channel,count:Int(buffer.frameLength)))
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
        XCTAssertTrue(samples.contains{abs($0)>0.01},"Generated fixture must contain speech, not an empty or silent export")
        let started=DispatchTime.now().uptimeNanoseconds
        let firstVAD=try await FluidSpeechActivityDetector.local(compiledModel:assets.vadCompiledModel)
        let firstASR=try await FluidClosedActivityRecognizer.local(root:assets.asrModelRoot)
        let secondVAD=try await FluidSpeechActivityDetector.local(compiledModel:assets.vadCompiledModel)
        let secondASR=try await FluidClosedActivityRecognizer.local(root:assets.asrModelRoot)
        let loaded=DispatchTime.now().uptimeNanoseconds
        // Exercise both actual VAD instances with bounded 16k mono chunks.
        let chunk=firstVAD.chunkSamples
        XCTAssertEqual(chunk,secondVAD.chunkSamples)
        let padded=Array(repeating:Float(0),count:16_000)+samples+Array(repeating:Float(0),count:32_000)
        var firstBoundaries:[SpeechBoundary]=[],secondBoundaries:[SpeechBoundary]=[]
        for offset in stride(from:0,to:padded.count,by:chunk) {
            var frame=Array(padded[offset..<min(offset+chunk,padded.count)])
            frame+=Array(repeating:0,count:chunk-frame.count)
            firstBoundaries+=try await firstVAD.accept(frame)
            secondBoundaries+=try await secondVAD.accept(frame)
        }
        XCTAssertTrue(firstBoundaries.contains{$0.kind == .start})
        XCTAssertTrue(firstBoundaries.contains{$0.kind == .end})
        XCTAssertEqual(firstBoundaries.map(\.kind),secondBoundaries.map(\.kind))
        async let first=firstASR.recognize(samples)
        async let second=secondASR.recognize(samples)
        let texts=try await [first,second]
        for text in texts {
            let words=text.lowercased()
            XCTAssertTrue(words.contains("python") && words.contains("list"),"Fixed synthetic technical phrase was not recognized")
        }
        XCTAssertNotNil(try store.cachedAssets(),"CoreML loading must leave the pinned public asset cache valid")
        let finished=DispatchTime.now().uptimeNanoseconds
        var usage=rusage()
        XCTAssertEqual(getrusage(RUSAGE_SELF,&usage),0)
        print("OFFLINE_SYNTHETIC_SPEECH sources=2 cache_bytes=\(assets.byteCount ?? 0) audio_samples=\(samples.count) load_ms=\((loaded-started)/1_000_000) processing_ms=\((finished-loaded)/1_000_000) process_max_rss_bytes=\(usage.ru_maxrss) vad_starts=\(firstBoundaries.filter{$0.kind == .start}.count) vad_ends=\(firstBoundaries.filter{$0.kind == .end}.count) phrase_matches=\(texts.count)")
    }
}
