import Darwin
import Dispatch
import Foundation
import XCTest
import RelayAudioBuffer
@testable import RelayNativeSession

private actor PipelineWatermarkVAD:RecognitionWatermarkDetector {
    nonisolated let chunkSamples=5120
    private let starts:Set<Int>,ends:Set<Int>,badAt:Int?
    private var active=false,count=0
    private(set) var observations=0,legacyAccepts=0
    init(starts:Set<Int>=[1],ends:Set<Int>=[3],badAt:Int?=nil){self.starts=starts;self.ends=ends;self.badAt=badAt}
    private func next()->SpeechActivityObservation{
        count+=1;let processed=UInt64(count*5120)
        var boundaries:[SpeechBoundary]=[]
        if starts.contains(count){active=true;boundaries.append(SpeechBoundary(kind:.start,sampleIndex:processed-5120))}
        if ends.contains(count){active=false;boundaries.append(SpeechBoundary(kind:.end,sampleIndex:processed))}
        return SpeechActivityObservation(boundaries:boundaries,processedSamples:processed,
            safePrefixEnd:badAt==count ? processed+5120:active ? processed:nil)
    }
    func accept(_ samples:[Float])async throws->[SpeechBoundary]{legacyAccepts+=1;return next().boundaries}
    func observe(_ samples:[Float])async throws->SpeechActivityObservation{observations+=1;return next()}
}
private actor PipelinePrefixASR:IncrementalActivityRecognizer {
    private(set) var begins:[RecognitionActivityKey]=[],parts:[(RecognitionActivityKey,[Float])]=[],legacy:[[Float]]=[]
    private(set) var appendEntered=false,finishEntered=false,aborts=0,resetUnderModel=false
    private var active:RecognitionActivityKey?,next:UInt64=0,busy=false,holdAppend=false,holdFinish=false
    private let failsPrefix:Bool
    private var waiter:CheckedContinuation<Void,Never>?
    init(failsPrefix:Bool=false){self.failsPrefix=failsPrefix}
    func holdPrefix(){holdAppend=true}
    func holdFinal(){holdFinish=true}
    func release(){waiter?.resume();waiter=nil;holdAppend=false;holdFinish=false}
    func begin(_ key:RecognitionActivityKey)async throws{
        guard active==nil,!busy else{throw NativeSessionError.invalidFrame};active=key;next=key.startSample;begins.append(key)
    }
    func append(_ samples:[Float],firstSample:UInt64,for key:RecognitionActivityKey)async throws{
        guard active==key,!busy,firstSample==next else{throw NativeSessionError.invalidFrame}
        busy=true;defer{busy=false}
        if holdAppend{appendEntered=true;await withCheckedContinuation{waiter=$0}}
        if failsPrefix{throw NativeSessionError.modelUnavailable}
        parts.append((key,samples));next+=UInt64(samples.count)
    }
    func finish(_ key:RecognitionActivityKey,endSample:UInt64)async throws->String{
        guard active==key,!busy,next==endSample else{throw NativeSessionError.invalidFrame}
        busy=true
        if holdFinish{finishEntered=true;await withCheckedContinuation{waiter=$0}}
        busy=false;active=nil;return "explain dictionaries including collisions"
    }
    func abort(_ key:RecognitionActivityKey)async throws{
        if busy{resetUnderModel=true;throw NativeSessionError.invalidFrame}
        guard active==key else{throw NativeSessionError.invalidFrame};aborts+=1;active=nil
    }
    func recognize(_ samples:[Float])async throws->String{
        guard active==nil,!busy else{throw NativeSessionError.invalidFrame};legacy.append(samples)
        return "explain dictionaries including collisions"
    }
}

@MainActor final class PrefixSourcePipelineTests:XCTestCase {
    private func packet(_ sequence:UInt64,_ value:Float=1,source:PCMSource = .remoteAudio)->SessionAudioPacket{
        let clock=NativeClockCalibration.now()
        let past=mach_absolute_time()-UInt64(2_000_000_000)*clock.nsDenom/clock.nsNumer
        return SessionAudioPacket(source:source,streamGeneration:1,sequence:sequence,hostTime:past,
            samples:Array(repeating:value,count:5120))
    }
    private func until(_ predicate:()async->Bool)async throws{
        for _ in 0..<2000{if await predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NativeSessionError.modelUnavailable
    }
    private func cleanup(_ controller:NativeSessionController,_ recognizers:[PipelinePrefixASR]){
        addTeardownBlock{
            controller.beginStop();for recognizer in recognizers{await recognizer.release()}
            await controller.waitForQuiescence();controller.finishStop(quiesced:true)
        }
    }
    func testPrefixWorkStartsOnlyAfterActualNativeOnsetAndFinalConsumesWholeOriginalSpan()async throws{
        let probe=EventProbe(),vad=PipelineWatermarkVAD(),asr=PipelinePrefixASR()
        let controller=NativeSessionController(onEvent:probe.append);cleanup(controller,[asr])
        try controller.start(selectedBundleID:"com.example.prefix",microphoneEnabled:false,
            components:[2:SourceComponents(vad:vad,recognizer:asr,recognitionMode:.safePrefixes)])
        controller.ingest(packet(1,1));try await until{await asr.parts.count==1}
        XCTAssertTrue(probe.events.contains{$0.kind == .speechStarted});XCTAssertFalse(probe.events.contains{$0.kind == .eou})
        controller.ingest(packet(2,2));try await until{await asr.parts.count==2}
        XCTAssertFalse(probe.events.contains{$0.kind == .speechEnded || $0.kind == .eou})
        controller.ingest(packet(3,3));try await until{probe.events.contains{$0.kind == .eou}}
        let samples=await asr.parts.flatMap{$0.1},legacy=await asr.legacy,keys=await asr.begins
        var original=Array(repeating:Float(1),count:5120)
        original+=Array(repeating:Float(2),count:5120);original+=Array(repeating:Float(3),count:5120)
        XCTAssertEqual(samples,original)
        XCTAssertTrue(legacy.isEmpty);XCTAssertEqual(keys.count,1);XCTAssertEqual(keys.first?.sourceCode,2)
        let final=try XCTUnwrap(probe.events.first{$0.kind == .eou})
        XCTAssertEqual(final.payload["firstInputSequence"],.uint(1));XCTAssertEqual(final.payload["lastInputSequence"],.uint(3))
        XCTAssertEqual(probe.events.map(\.eventSequence),Array(1...UInt64(probe.events.count)))
        XCTAssertEqual(probe.events.filter{$0.kind == .eou}.count,1)
    }
    func testDefaultComponentModeStaysClosedAndDoesNotInvokeWatermarkOrPrefix()async throws{
        let probe=EventProbe(),vad=PipelineWatermarkVAD(),asr=PipelinePrefixASR()
        let controller=NativeSessionController(onEvent:probe.append);cleanup(controller,[asr])
        try controller.start(selectedBundleID:"com.example.prefix",microphoneEnabled:false,
            components:[2:SourceComponents(vad:vad,recognizer:asr)])
        for n:UInt64 in 1...3{controller.ingest(packet(n));try await until{await vad.legacyAccepts>=Int(n)}}
        try await until{probe.events.contains{$0.kind == .eou}}
        let begins=await asr.begins,legacy=await asr.legacy,observed=await vad.observations
        XCTAssertTrue(begins.isEmpty);XCTAssertEqual(legacy.count,1);XCTAssertEqual(legacy.first?.count,15360);XCTAssertEqual(observed,0)
    }
    func testWatermarkWithoutNativeSpeechStartCannotGrantRecognizerWork()async throws{
        let probe=EventProbe(),vad=PipelineWatermarkVAD(starts:[],ends:[]),asr=PipelinePrefixASR()
        let controller=NativeSessionController(onEvent:probe.append);cleanup(controller,[asr])
        try controller.start(selectedBundleID:"com.example.prefix",microphoneEnabled:false,
            components:[2:SourceComponents(vad:vad,recognizer:asr,recognitionMode:.safePrefixes)])
        controller.ingest(packet(1));try await until{await vad.observations==1}
        let begins=await asr.begins,legacy=await asr.legacy
        XCTAssertTrue(begins.isEmpty);XCTAssertTrue(legacy.isEmpty);XCTAssertFalse(probe.events.contains{$0.kind == .eou})
    }
    func testHeldRemoteModelCannotDelayIndependentMicrophoneFinalOrMixItsSamples()async throws{
        let probe=EventProbe(),remote=PipelinePrefixASR(),microphone=PipelinePrefixASR()
        await remote.holdPrefix()
        let controller=NativeSessionController(onEvent:probe.append);cleanup(controller,[remote,microphone])
        try controller.start(selectedBundleID:"com.example.prefix",microphoneEnabled:true,components:[
            2:SourceComponents(vad:PipelineWatermarkVAD(),recognizer:remote,recognitionMode:.safePrefixes),
            1:SourceComponents(vad:PipelineWatermarkVAD(),recognizer:microphone,recognitionMode:.safePrefixes)])
        controller.ingest(packet(1,1));try await until{await remote.appendEntered}
        for n:UInt64 in 1...3{controller.ingest(packet(n,2,source:.microphone))}
        try await until{probe.events.contains{$0.kind == .eou && $0.sourceCode==1}}
        XCTAssertFalse(probe.events.contains{$0.kind == .eou && $0.sourceCode==2})
        let mic=await microphone.parts.flatMap{$0.1},key=await microphone.begins.first
        XCTAssertEqual(mic.count,15360);XCTAssertTrue(mic.allSatisfy{$0==2});XCTAssertEqual(key?.sourceCode,1)
        await remote.release()
    }
    func testLaterOnsetDoesNotCancelSourceLiveOldFinalOrStampItWithNewDisplayLease()async throws{
        let probe=EventProbe(),vad=PipelineWatermarkVAD(starts:[1,4],ends:[3,6]),asr=PipelinePrefixASR()
        await asr.holdFinal()
        let controller=NativeSessionController(onEvent:probe.append);cleanup(controller,[asr])
        try controller.start(selectedBundleID:"com.example.prefix",microphoneEnabled:false,
            components:[2:SourceComponents(vad:vad,recognizer:asr,recognitionMode:.safePrefixes)])
        for n:UInt64 in 1...3{controller.ingest(packet(n));try await until{await vad.observations>=Int(n)}}
        try await until{await asr.finishEntered}
        let original=try XCTUnwrap(probe.events.first{$0.kind == .speechStarted}).lease
        controller.ingest(packet(4));try await until{probe.events.filter{$0.kind == .speechStarted}.count==2}
        XCTAssertNotEqual(controller.authority.snapshot(),original)
        await asr.release();try await until{probe.events.contains{$0.kind == .eou}}
        let oldFinal=try XCTUnwrap(probe.events.first{$0.kind == .eou})
        XCTAssertEqual(oldFinal.lease,original)
        if case .object(let inner)=oldFinal.payload["event"]{
            XCTAssertEqual(inner["timebase"],probe.events.first{$0.kind == .speechStarted}?.payload["timebase"])
        }else{XCTFail("Original final has no inner source event")}
        XCTAssertFalse(probe.events.contains{$0.kind == .sourceUnavailable})
    }
    func testStopKeepsActualHeldPrefixOwnerUntilReturnAndCannotPublishLateFinal()async throws{
        let probe=EventProbe(),asr=PipelinePrefixASR()
        let controller=NativeSessionController(onEvent:probe.append)
        await asr.holdPrefix();cleanup(controller,[asr])
        try controller.start(selectedBundleID:"com.example.prefix",microphoneEnabled:false,
            components:[2:SourceComponents(vad:PipelineWatermarkVAD(),recognizer:asr,recognitionMode:.safePrefixes)])
        controller.ingest(packet(1));try await until{await asr.appendEntered};controller.beginStop()
        var joined=false;let task=Task{await controller.waitForQuiescence();joined=true}
        for _ in 0..<10{await Task.yield()}
        let before=await asr.aborts;XCTAssertFalse(joined);XCTAssertEqual(before,0)
        await asr.release();await task.value;controller.finishStop(quiesced:true)
        let bad=await asr.resetUnderModel,aborts=await asr.aborts
        XCTAssertFalse(bad);XCTAssertEqual(aborts,1);XCTAssertTrue(joined)
        XCTAssertFalse(probe.events.contains{$0.kind == .eou})
    }
    func testOptimizationQueuePressureRetainsNativeCaptureAndRunsOneOriginalClosedFallback()async throws{
        let probe=EventProbe(),vad=PipelineWatermarkVAD(ends:[7]),asr=PipelinePrefixASR()
        await asr.holdPrefix()
        let controller=NativeSessionController(onEvent:probe.append);cleanup(controller,[asr])
        try controller.start(selectedBundleID:"com.example.prefix",microphoneEnabled:false,
            components:[2:SourceComponents(vad:vad,recognizer:asr,recognitionMode:.safePrefixes)])
        controller.ingest(packet(1));try await until{await asr.appendEntered}
        for n:UInt64 in 2...7{controller.ingest(packet(n,Float(n)));try await until{await vad.observations>=Int(n)}}
        XCTAssertFalse(probe.events.contains{$0.kind == .sourceUnavailable || $0.kind == .discontinuity})
        await asr.release();try await until{probe.events.contains{$0.kind == .eou}}
        let legacy=await asr.legacy,bad=await asr.resetUnderModel
        XCTAssertEqual(legacy.count,1);XCTAssertEqual(legacy.first?.count,35840);XCTAssertFalse(bad)
        let original=(1...7).flatMap{Array(repeating:Float($0),count:5120)}
        XCTAssertEqual(legacy.first,original)
        XCTAssertEqual(probe.events.filter{$0.kind == .eou}.count,1)
        XCTAssertFalse(probe.events.contains{$0.kind == .sourceUnavailable || $0.kind == .discontinuity})
    }
    func testInvalidWatermarkFailsClosedWithoutLegacyRepairOrFinal()async throws{
        let probe=EventProbe(),vad=PipelineWatermarkVAD(badAt:2),asr=PipelinePrefixASR()
        let controller=NativeSessionController(onEvent:probe.append);cleanup(controller,[asr])
        try controller.start(selectedBundleID:"com.example.prefix",microphoneEnabled:false,
            components:[2:SourceComponents(vad:vad,recognizer:asr,recognitionMode:.safePrefixes)])
        controller.ingest(packet(1));try await until{await asr.parts.count==1};controller.ingest(packet(2))
        try await until{probe.events.contains{$0.kind == .sourceUnavailable}}
        let legacy=await asr.legacy;XCTAssertTrue(legacy.isEmpty);XCTAssertFalse(probe.events.contains{$0.kind == .eou})
    }
    func testPrefixModelErrorFailsClosedAndNeverUsesOptimizationFallbackAsRepair()async throws{
        let probe=EventProbe(),asr=PipelinePrefixASR(failsPrefix:true)
        let controller=NativeSessionController(onEvent:probe.append);cleanup(controller,[asr])
        try controller.start(selectedBundleID:"com.example.prefix",microphoneEnabled:false,
            components:[2:SourceComponents(vad:PipelineWatermarkVAD(),recognizer:asr,recognitionMode:.safePrefixes)])
        controller.ingest(packet(1));try await until{probe.events.contains{$0.kind == .sourceUnavailable}}
        let failure=try XCTUnwrap(probe.events.first{$0.kind == .sourceUnavailable})
        XCTAssertEqual(failure.payload["reasonCode"],.string("asr_unavailable"))
        let legacy=await asr.legacy;XCTAssertTrue(legacy.isEmpty);XCTAssertFalse(probe.events.contains{$0.kind == .eou})
    }
    func testRetiredPrefixGraphReleasesItsRecognizerAfterActualNativeJoin()async throws{
        weak var released:PipelinePrefixASR?
        let probe=EventProbe()
        var asr:PipelinePrefixASR?=PipelinePrefixASR();released=asr
        var controller:NativeSessionController?=NativeSessionController(onEvent:probe.append)
        do{
            try controller!.start(selectedBundleID:"com.example.prefix",microphoneEnabled:false,
                components:[2:SourceComponents(vad:PipelineWatermarkVAD(),recognizer:asr!,recognitionMode:.safePrefixes)])
            for n:UInt64 in 1...3{controller!.ingest(packet(n))}
            try await until{probe.events.contains{$0.kind == .eou}}
        }catch{
            controller!.beginStop();await controller!.waitForQuiescence();controller!.finishStop(quiesced:true);throw error
        }
        controller!.beginStop();await controller!.waitForQuiescence();controller!.finishStop(quiesced:true)
        controller=nil;asr=nil
        try await until{released==nil}
        XCTAssertNil(released,"The retained source-live predicate cannot keep the old source/model graph alive")
    }
}
