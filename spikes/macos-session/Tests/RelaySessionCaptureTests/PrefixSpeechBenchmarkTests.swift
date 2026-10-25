import AVFoundation
import CryptoKit
import Darwin
import Foundation
import XCTest
import RelayNativeSession
import RelayAudioBuffer
@testable import RelaySessionCapture

private let prefixFixtureSHA="98f0000e24688c1e665bd90de70d99b378b661bb749b483aeeed90cd5b2be9c7"
private let prefixResultMarker="PREFIX_SPEECH_BENCHMARK_RESULT "
private struct PrefixBenchSpan:Codable,Equatable,Sendable {
    let source:UInt32,activity:UInt64,startSample:UInt64,endSample:UInt64,text:String
}
private struct PrefixBenchTiming:Codable,Sendable {
    let source:UInt32,activity:UInt64,inputSamples:Int,acceptedBeforeEnd:Int,remainingInputAtEnd:Int,legacyCalls:Int
    let nativeEndToFinalMs:Double,reportedBoundaryToFinalMs:Double
}
private struct PrefixBenchRun:Codable,Sendable {
    let leadingSilenceSamples:Int,trailingSilenceSamples:Int,lastPacketZeroPaddingSamples:Int,pacedSamplesPerSource:Int
    let spans:[PrefixBenchSpan],timings:[PrefixBenchTiming]
}
private struct PrefixBenchReport:Codable,Sendable {
    let schemaVersion:Int,mode:String,inputSHA:String,inputSamples:Int,sourceCount:Int,warmups:Int
    let asrLoadMs:UInt64,peakRSSBytes:UInt64,runs:[PrefixBenchRun]
}
private final class PrefixBenchmarkEvents:@unchecked Sendable {
    private let lock=NSLock()
    private var values:[NativeSessionEvent]=[]
    func append(_ event:NativeSessionEvent)throws{
        try lock.withLock{guard values.count<256 else{throw NativeSessionError.frameTooLarge};values.append(event)}
    }
    var events:[NativeSessionEvent]{lock.withLock{values}}
}
private actor PrefixBenchmarkVAD:RecognitionWatermarkDetector {
    nonisolated let chunkSamples:Int
    let actual:FluidSpeechActivityDetector
    private var boundaries:[SpeechBoundary]=[]
    init(_ actual:FluidSpeechActivityDetector){self.actual=actual;chunkSamples=actual.chunkSamples}
    func accept(_ samples:[Float])async throws->[SpeechBoundary]{
        let value=try await actual.accept(samples);boundaries+=value;return value
    }
    func observe(_ samples:[Float])async throws->SpeechActivityObservation{
        let value=try await actual.observe(samples);boundaries+=value.boundaries;return value
    }
    func trace()->[SpeechBoundary]{boundaries}
}
private actor PrefixBenchmarkASR:IncrementalActivityRecognizer {
    struct Ack:Sendable{let activity:UInt64,count:Int,at:UInt64}
    struct Legacy:Sendable{let activity:UInt64,count:Int}
    let actual:FluidClosedActivityRecognizer
    private var acknowledgements:[Ack]=[],legacy:[Legacy]=[]
    private var pendingFallback:RecognitionActivityKey?
    private var legacyOrdinal:UInt64=0
    init(_ actual:FluidClosedActivityRecognizer){self.actual=actual}
    func begin(_ key:RecognitionActivityKey)async throws{try await actual.begin(key)}
    func append(_ samples:[Float],firstSample:UInt64,for key:RecognitionActivityKey)async throws{
        try await actual.append(samples,firstSample:firstSample,for:key)
        guard acknowledgements.count<2048 else{throw NativeSessionError.frameTooLarge}
        acknowledgements.append(Ack(activity:key.activityID,count:samples.count,at:DispatchTime.now().uptimeNanoseconds))
    }
    func finish(_ key:RecognitionActivityKey,endSample:UInt64)async throws->String{try await actual.finish(key,endSample:endSample)}
    func abort(_ key:RecognitionActivityKey)async throws{try await actual.abort(key);pendingFallback=key}
    func recognize(_ samples:[Float])async throws->String{
        legacyOrdinal+=1
        let id=pendingFallback?.activityID ?? legacyOrdinal;pendingFallback=nil
        legacy.append(Legacy(activity:id,count:samples.count))
        return try await actual.recognize(samples)
    }
    func inputs()->([Ack],[Legacy]){(acknowledgements,legacy)}
}

/// Opt-in real local speech measurement only. Ordinary discovery skips before
/// cache inspection, model load, child creation or audio access. No capture,
/// playback, regeneration, provider/account request or new model is permitted.
@MainActor final class PrefixSpeechBenchmarkTests:XCTestCase {
    func testMatchedPacedExistingWavePreservesTextCutoffsAndReducesFinalizationWork()async throws{
        let environment=ProcessInfo.processInfo.environment
        guard environment["RELAY_RUN_PREFIX_SPEECH_BENCHMARK"]=="1",
              let cache=environment["RELAY_OFFLINE_SPEECH_CACHE"],
              let audio=environment["RELAY_OFFLINE_SYNTHETIC_AUDIO"] else{
            throw XCTSkip("Explicit unchanged fictional WAVE and verified public cache required; no download or capture")
        }
        if let mode=environment["RELAY_PREFIX_BENCHMARK_CHILD"]{
            guard ["baseline","prefix"].contains(mode) else{throw NativeSessionError.invalidConfiguration}
            try await child(mode:mode,cache:cache,audio:audio);return
        }
        let baseline=try await launch(mode:"baseline",cache:cache,audio:audio)
        let prefix=try await launch(mode:"prefix",cache:cache,audio:audio)
        XCTAssertEqual(baseline.schemaVersion,1);XCTAssertEqual(prefix.schemaVersion,1)
        XCTAssertEqual(baseline.mode,"baseline");XCTAssertEqual(prefix.mode,"prefix")
        XCTAssertEqual(baseline.warmups,1);XCTAssertEqual(prefix.warmups,1)
        XCTAssertEqual(baseline.inputSHA,prefixFixtureSHA);XCTAssertEqual(prefix.inputSHA,prefixFixtureSHA)
        XCTAssertEqual(baseline.inputSamples,prefix.inputSamples)
        XCTAssertEqual(baseline.sourceCount,2);XCTAssertEqual(prefix.sourceCount,2)
        XCTAssertEqual(baseline.runs.count,2);XCTAssertEqual(prefix.runs.count,2)
        for index in 0..<min(baseline.runs.count,prefix.runs.count){
            XCTAssertEqual(baseline.runs[index].spans,prefix.runs[index].spans,"Full synthetic text and exact source cutoffs must match")
            let baseRun=baseline.runs[index],prefixRun=prefix.runs[index]
            XCTAssertEqual(baseRun.leadingSilenceSamples,8000);XCTAssertEqual(prefixRun.leadingSilenceSamples,8000)
            XCTAssertEqual(baseRun.trailingSilenceSamples,32000);XCTAssertEqual(prefixRun.trailingSilenceSamples,32000)
            XCTAssertEqual(baseRun.lastPacketZeroPaddingSamples,prefixRun.lastPacketZeroPaddingSamples)
            XCTAssertEqual(baseRun.lastPacketZeroPaddingSamples,baseRun.pacedSamplesPerSource-baseline.inputSamples-40000)
            XCTAssertEqual(baseRun.pacedSamplesPerSource,prefixRun.pacedSamplesPerSource)
            XCTAssertEqual(baseRun.pacedSamplesPerSource,((baseline.inputSamples+8000+32000+511)/512)*512)
        }
        for row in baseline.runs.flatMap(\.timings){
            XCTAssertEqual(row.legacyCalls,1);XCTAssertEqual(row.acceptedBeforeEnd,0)
            XCTAssertEqual(row.remainingInputAtEnd,row.inputSamples)
        }
        let baseTimes=baseline.runs.flatMap(\.timings).map(\.nativeEndToFinalMs)
        let prefixTimes=prefix.runs.flatMap(\.timings).map(\.nativeEndToFinalMs)
        guard !baseTimes.isEmpty,baseTimes.count==prefixTimes.count else{throw NativeSessionError.invalidFrame}
        let baseMedian=median(baseTimes),prefixMedian=median(prefixTimes)
        let summary:[String:Any]=["schemaVersion":1,"inputSHA":prefixFixtureSHA,
            "scope":"actual paced local ASR; excludes helper, cloud inference, app publication, window and usefulness",
            "sourceCount":2,"trialsPerMode":2,"observationsPerMode":baseTimes.count,
            "unchangedWaveSamples":prefix.inputSamples,"leadingSilenceSamples":8000,"trailingSilenceSamples":32000,
            "lastPacketZeroPaddingSamples":prefix.runs.first?.lastPacketZeroPaddingSamples ?? 0,
            "pacedSamplesPerSource":prefix.runs.first?.pacedSamplesPerSource ?? 0,
            "baselineMedianEndToFinalMs":baseMedian,"prefixMedianEndToFinalMs":prefixMedian,
            "baselinePeakRSSBytes":baseline.peakRSSBytes,"prefixPeakRSSBytes":prefix.peakRSSBytes]
        print("PREFIX_SPEECH_BENCHMARK_SUMMARY "+String(decoding:try JSONSerialization.data(withJSONObject:summary,options:[.sortedKeys]),as:UTF8.self))
        // A controlled opt-in performance gate, never a default CI timing test.
        XCTAssertLessThan(prefixMedian,baseMedian*0.9,"No normal activation without a material observed finalization reduction")
        XCTAssertLessThanOrEqual(prefix.peakRSSBytes,baseline.peakRSSBytes+256*1024*1024,"Investigate unexpected memory growth before normal activation")
        for row in prefix.runs.flatMap(\.timings){
            XCTAssertGreaterThan(row.acceptedBeforeEnd,0);XCTAssertLessThan(row.remainingInputAtEnd,row.inputSamples)
            XCTAssertEqual(row.legacyCalls,0,"Retain/report any local fallback; this normal-rate gate must not hide it")
        }
    }
    private func launch(mode:String,cache:String,audio:String)async throws->PrefixBenchReport{
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-prefix-benchmark-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        addTeardownBlock{try? FileManager.default.removeItem(at:directory)}
        let stdout=directory.appendingPathComponent("stdout.log"),stderr=directory.appendingPathComponent("stderr.log")
        FileManager.default.createFile(atPath:stdout.path,contents:nil);FileManager.default.createFile(atPath:stderr.path,contents:nil)
        let out=try FileHandle(forWritingTo:stdout),err=try FileHandle(forWritingTo:stderr)
        defer{try? out.close();try? err.close()}
        let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/xcrun")
        process.arguments=["xctest","-XCTest","RelaySessionCaptureTests.PrefixSpeechBenchmarkTests/testMatchedPacedExistingWavePreservesTextCutoffsAndReducesFinalizationWork",Bundle(for:Self.self).bundleURL.path]
        var env=["PATH":"/usr/bin:/bin","RELAY_RUN_PREFIX_SPEECH_BENCHMARK":"1","RELAY_PREFIX_BENCHMARK_CHILD":mode,
            "RELAY_OFFLINE_SPEECH_CACHE":cache,"RELAY_OFFLINE_SYNTHETIC_AUDIO":audio,
            "RELAY_RUN_OFFLINE_MANAGED_SPEECH":"0","RELAY_TEST_SPEECH_DOWNLOAD":"0","HF_HUB_OFFLINE":"1"]
        for name in ["DYLD_LIBRARY_PATH","DYLD_FRAMEWORK_PATH","DEVELOPER_DIR","TMPDIR"]{
            if let value=ProcessInfo.processInfo.environment[name]{env[name]=value}
        }
        process.environment=env;process.standardOutput=out;process.standardError=err
        try process.run()
        defer{if process.isRunning{_=Darwin.kill(process.processIdentifier,SIGKILL)}}
        let deadline=DispatchTime.now().uptimeNanoseconds+60_000_000_000
        while process.isRunning,DispatchTime.now().uptimeNanoseconds<deadline{
            let bytes=(try stdout.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)+(try stderr.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)
            if bytes>4*1024*1024{process.terminate();break}
            try await Task.sleep(for:.milliseconds(50))
        }
        if process.isRunning{process.terminate()}
        for _ in 0..<100{if !process.isRunning{break};try await Task.sleep(for:.milliseconds(20))}
        if process.isRunning{_=Darwin.kill(process.processIdentifier,SIGKILL)}
        for _ in 0..<100{if !process.isRunning{break};try await Task.sleep(for:.milliseconds(20))}
        guard !process.isRunning else{throw NativeSessionError.modelUnavailable}
        let output=try String(contentsOf:stdout,encoding:.utf8)
        guard process.terminationStatus==0 else{
            let diagnostic=try String(contentsOf:stderr,encoding:.utf8)
            XCTFail("Controlled local \(mode) child failed: \(diagnostic.suffix(6000))")
            throw NativeSessionError.modelUnavailable
        }
        let records=output.split(separator:"\n").filter{$0.hasPrefix(prefixResultMarker)}
        guard records.count==1 else{throw NativeSessionError.invalidFrame}
        let report=try JSONDecoder().decode(PrefixBenchReport.self,from:Data(records[0].dropFirst(prefixResultMarker.count).utf8))
        // Only sanitized numeric/synthetic-source results cross to the parent log.
        print(prefixResultMarker+String(decoding:try JSONEncoder().encode(report),as:UTF8.self))
        return report
    }
    private func child(mode:String,cache:String,audio:String)async throws{
        let url=URL(fileURLWithPath:audio),bytes=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard bytes>4096,bytes<=2_000_000 else{throw NativeSessionError.invalidFrame}
        let digest=SHA256.hash(data:try Data(contentsOf:url)).map{String(format:"%02x",$0)}.joined()
        guard digest==prefixFixtureSHA else{throw NativeSessionError.invalidFrame}
        let store=try SpeechAssetStore(directory:URL(fileURLWithPath:cache))
        let assets=try XCTUnwrap(store.cachedAssets())
        let file=try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
        guard file.processingFormat.sampleRate==16_000,file.processingFormat.channelCount==1,file.length>0,file.length<=64_000,
              let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length)) else{throw NativeSessionError.invalidFrame}
        try file.read(into:buffer)
        let samples=Array(UnsafeBufferPointer(start:try XCTUnwrap(buffer.floatChannelData?[0]),count:Int(buffer.frameLength)))
        guard samples.allSatisfy(\.isFinite),samples.contains(where:{abs($0)>0.01}) else{throw NativeSessionError.invalidFrame}
        let started=DispatchTime.now().uptimeNanoseconds
        let first=try await FluidClosedActivityRecognizer.local(root:assets.asrModelRoot)
        let second=try await FluidClosedActivityRecognizer.local(root:assets.asrModelRoot)
        let loaded=DispatchTime.now().uptimeNanoseconds
        let actual:[UInt32:FluidClosedActivityRecognizer]=[1:first,2:second]
        // Warm only through an actual synthetic native start/end scope, not an
        // inference before native source permission. Setup/warm-up are separate.
        _=try await paced(mode:.closedSpan,assets:assets,samples:samples,actual:actual)
        var runs:[PrefixBenchRun]=[]
        for _ in 0..<2{runs.append(try await paced(mode:mode=="prefix" ? .safePrefixes:.closedSpan,assets:assets,samples:samples,actual:actual))}
        XCTAssertNotNil(try store.cachedAssets(),"Existing public cache must remain valid after the real model gate")
        var usage=rusage();guard getrusage(RUSAGE_SELF,&usage)==0,usage.ru_maxrss>0 else{throw NativeSessionError.modelUnavailable}
        let report=PrefixBenchReport(schemaVersion:1,mode:mode,inputSHA:digest,inputSamples:samples.count,sourceCount:2,warmups:1,
            asrLoadMs:(loaded-started)/1_000_000,peakRSSBytes:UInt64(usage.ru_maxrss),runs:runs)
        FileHandle.standardOutput.write(Data((prefixResultMarker+String(decoding:try JSONEncoder().encode(report),as:UTF8.self)+"\n").utf8))
    }
    private func paced(mode:ActivityRecognitionMode,assets:PreparedSpeechAssets,samples:[Float],actual:[UInt32:FluidClosedActivityRecognizer])async throws->PrefixBenchRun{
        let events=PrefixBenchmarkEvents()
        var detectors:[UInt32:PrefixBenchmarkVAD]=[:],recognizers:[UInt32:PrefixBenchmarkASR]=[:],components:[UInt32:SourceComponents]=[:]
        for code:UInt32 in [1,2]{
            let detector=PrefixBenchmarkVAD(try await FluidSpeechActivityDetector.local(compiledModel:assets.vadCompiledModel))
            let recognizer=PrefixBenchmarkASR(try XCTUnwrap(actual[code]))
            detectors[code]=detector;recognizers[code]=recognizer
            components[code]=SourceComponents(vad:detector,recognizer:recognizer,recognitionMode:mode)
        }
        let native=NativeSessionController(onEvent:events.append)
        var deliveredSamples=0
        do{
            try native.start(selectedBundleID:"com.example.synthetic-prefix-benchmark",microphoneEnabled:true,components:components)
            var pacedSamples=Array(repeating:Float(0),count:8000);pacedSamples+=samples;pacedSamples+=Array(repeating:0,count:32000)
            var sequence:UInt64=1
            for offset in stride(from:0,to:pacedSamples.count,by:512){
                var frame=Array(pacedSamples[offset..<min(offset+512,pacedSamples.count)])
                frame+=Array(repeating:0,count:512-frame.count)
                let time=mach_absolute_time()
                for source in [PCMSource.microphone,.remoteAudio]{
                    native.ingest(SessionAudioPacket(source:source,streamGeneration:1,sequence:sequence,hostTime:time,samples:frame))
                }
                sequence+=1;deliveredSamples+=frame.count;try await Task.sleep(for:.milliseconds(32))
                if events.events.contains(where:{$0.kind == .sourceUnavailable || $0.kind == .discontinuity}){throw NativeSessionError.modelUnavailable}
            }
            for _ in 0..<2500{
                let observed=events.events
                if observed.contains(where:{$0.kind == .sourceUnavailable || $0.kind == .discontinuity}){throw NativeSessionError.modelUnavailable}
                var complete=true
                for code:UInt32 in [1,2]{
                    let trace=await detectors[code]!.trace()
                    let starts=trace.filter{$0.kind == .start}.count,ends=trace.filter{$0.kind == .end}.count
                    let finals=observed.filter{$0.kind == .eou && $0.sourceCode==code}.count
                    if starts==0 || starts != ends || finals != ends{complete=false}
                }
                if complete{break}
                try await Task.sleep(for:.milliseconds(2))
            }
            native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
        }catch{
            native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true);throw error
        }
        let observed=events.events
        guard !observed.contains(where:{$0.kind == .sourceUnavailable || $0.kind == .discontinuity}) else{throw NativeSessionError.modelUnavailable}
        var spans:[PrefixBenchSpan]=[],timings:[PrefixBenchTiming]=[]
        for code:UInt32 in [1,2]{
            let trace=await detectors[code]!.trace(),inputs=await recognizers[code]!.inputs()
            let starts=trace.filter{$0.kind == .start}.map(\.sampleIndex),ends=trace.filter{$0.kind == .end}.map(\.sampleIndex)
            let finals=observed.filter{$0.kind == .eou && $0.sourceCode==code}
            guard !starts.isEmpty,starts.count==ends.count,finals.count==ends.count else{throw NativeSessionError.invalidFrame}
            for event in finals{
                let activity=try uint(event.payload["activityID"])
                guard activity>0,activity<=UInt64(starts.count) else{throw NativeSessionError.invalidFrame}
                let index=Int(activity-1)
                guard ends[index]>starts[index],
                      let ended=observed.first(where:{$0.kind == .speechEnded && $0.sourceCode==code && $0.payload["activityID"] == .uint(activity)}),
                      case .object(let inner)=event.payload["event"],case .string(let text)=inner["text"] else{throw NativeSessionError.invalidFrame}
                guard text.lowercased().contains("python"),text.lowercased().contains("list") else{throw NativeSessionError.invalidFrame}
                let final=try uint(inner["finalizedUptimeNanoseconds"]),boundary=try boundaryTime(inner)
                guard final>=ended.emittedUptimeNanoseconds,final>=boundary else{throw NativeSessionError.invalidClock}
                let length=Int(ends[index]-starts[index])
                let accepted=inputs.0.filter{$0.activity==activity && $0.at<=ended.emittedUptimeNanoseconds}.reduce(0){$0+$1.count}
                guard accepted<=length else{throw NativeSessionError.invalidFrame}
                let legacy=inputs.1.filter{$0.activity==activity}.count
                spans.append(PrefixBenchSpan(source:code,activity:activity,startSample:starts[index],endSample:ends[index],text:text))
                timings.append(PrefixBenchTiming(source:code,activity:activity,inputSamples:length,acceptedBeforeEnd:accepted,
                    remainingInputAtEnd:length-accepted,legacyCalls:legacy,
                    nativeEndToFinalMs:Double(final-ended.emittedUptimeNanoseconds)/1_000_000,
                    reportedBoundaryToFinalMs:Double(final-boundary)/1_000_000))
            }
        }
        return PrefixBenchRun(leadingSilenceSamples:8000,trailingSilenceSamples:32000,
            lastPacketZeroPaddingSamples:deliveredSamples-samples.count-40000,
            pacedSamplesPerSource:deliveredSamples,spans:spans,timings:timings)
    }
    private func uint(_ value:WireValue?)throws->UInt64{guard case .uint(let n)=value else{throw NativeSessionError.invalidFrame};return n}
    private func boundaryTime(_ inner:[String:WireValue])throws->UInt64{
        guard case .object(let c)=inner["timebase"] else{throw NativeSessionError.invalidClock}
        let clock=try NativeClockCalibration(hostTicksAtAnchor:uint(c["hostTicksAtAnchor"]),uptimeNsAtAnchor:uint(c["uptimeNsAtAnchor"]),
            nsNumer:uint(c["nsNumer"]),nsDenom:uint(c["nsDenom"]))
        return try clock.uptimeNanoseconds(forHostTicks:uint(inner["endHostTime"]))
    }
    private func median(_ values:[Double])->Double{let sorted=values.sorted(),i=sorted.count/2;return sorted.count%2==1 ? sorted[i]:(sorted[i-1]+sorted[i])/2}
}
