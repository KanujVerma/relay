import Foundation
import XCTest
@testable import FluidAudio
@testable import RelayNativeSession
@testable import RelaySessionCapture
import RelayLocalASR

private actor HeldPrefixFluidBackend:LocalEouRecognizer {
    private(set) var received:[Float]=[],resets=0,finishes=0,entered=false,busy=false,resetDuringAccept=false
    private var hold=false,waiter:CheckedContinuation<Void,Never>?
    func holdNext(){hold=true}
    func release(){waiter?.resume();waiter=nil;hold=false}
    func accept(_ samples:[Float])async throws->Bool{
        busy=true
        if hold{entered=true;await withCheckedContinuation{waiter=$0}}
        received+=samples;busy=false;return true
    }
    func finish()async throws->String{finishes+=1;return "complete later constraint"}
    func reset()async{if busy{resetDuringAccept=true};resets+=1}
}

final class PrefixFluidAdapterTests:XCTestCase {
    private func key()throws->RecognitionActivityKey{
        let authority=SessionPresentationAuthority(),lease=try authority.start()
        return RecognitionActivityKey(sourceCode:2,generation:1,activityID:1,startSample:1600,lease:lease)
    }
    private func until(_ predicate:()async->Bool)async throws{
        for _ in 0..<1500{if await predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NativeSessionError.modelUnavailable
    }
    func testActualPinnedHysteresisStateFreezesRecognitionWatermarkUntilOriginalLateCutoff()async throws{
        let manager=VadManager(skipModelLoading:true),config=VadSegmentationConfig.default
        var state=VadStreamState.initial(),finalEnd:Int?,maximumPrefix:UInt64=0
        let probabilities=Array(repeating:Float(0.95),count:4)+[0.1]+Array(repeating:Float(0.75),count:12)+[0.1]
        for p in probabilities{
            let result=await manager.streamingStateMachine(probability:p,chunkSampleCount:4096,
                modelState:state.modelState,state:state,config:config,returnSeconds:false,timeResolution:1)
            state=result.state
            let safe=try FluidSpeechActivityDetector.recognitionSafeEnd(state:state,event:result.event,config:config)
            if result.event?.isEnd==true{
                finalEnd=result.event?.sampleIndex;XCTAssertNil(safe)
                XCTAssertLessThanOrEqual(maximumPrefix,UInt64(try XCTUnwrap(finalEnd)))
            }else if let safe{maximumPrefix=max(maximumPrefix,safe)}
        }
        XCTAssertEqual(finalEnd,17984);XCTAssertEqual(state.processedSamples,73728)
        XCTAssertEqual(maximumPrefix,17984)
        XCTAssertEqual(config.minSilenceDuration,0.75);XCTAssertEqual(config.speechPadding,0.1)
    }
    func testActualPinnedLeadingPaddingAndResumedSpeechKeepTheWholeOriginalActivity()async throws{
        let manager=VadManager(skipModelLoading:true),config=VadSegmentationConfig.default
        var state=VadStreamState.initial(),starts:[Int]=[],ends:[Int]=[],prior:UInt64=0
        var probabilities=Array(repeating:Float(0.1),count:5)
        probabilities+=Array(repeating:Float(0.95),count:2);probabilities.append(0.1)
        probabilities+=Array(repeating:Float(0.75),count:8)
        probabilities+=Array(repeating:Float(0.95),count:4)
        probabilities+=Array(repeating:Float(0.1),count:4)
        for p in probabilities{
            let result=await manager.streamingStateMachine(probability:p,chunkSampleCount:4096,
                modelState:state.modelState,state:state,config:config,returnSeconds:false,timeResolution:1)
            state=result.state
            if let event=result.event{if event.isStart{starts.append(event.sampleIndex)}else{ends.append(event.sampleIndex)}}
            if let safe=try FluidSpeechActivityDetector.recognitionSafeEnd(state:state,event:result.event,config:config){
                XCTAssertGreaterThanOrEqual(safe,prior);prior=safe
            }
        }
        XCTAssertEqual(starts,[18880]);XCTAssertEqual(ends.count,1)
        XCTAssertLessThanOrEqual(prior,UInt64(try XCTUnwrap(ends.first)))
    }
    func testMalformedWatermarkStateCannotBeConvertedIntoPermissionToConsumeMoreAudio()throws{
        let config=VadSegmentationConfig.default
        for state in [VadStreamState(triggered:true,processedSamples:-1),
                      VadStreamState(triggered:true,tempEndSample:99_999,processedSamples:4096),
                      VadStreamState(triggered:true,tempEndSample:-1,processedSamples:4096)]{
            XCTAssertThrowsError(try FluidSpeechActivityDetector.recognitionSafeEnd(state:state,event:nil,config:config))
        }
    }
    func testPrefixAndClosedAdapterConsumeIdentical5120PartitionDespiteEarlyEOUHints()async throws{
        let prefixBackend=HeldPrefixFluidBackend(),closedBackend=HeldPrefixFluidBackend()
        let prefix=FluidClosedActivityRecognizer(backend:prefixBackend),closed=FluidClosedActivityRecognizer(backend:closedBackend)
        let key=try key(),first=Array(repeating:Float(1),count:5120),later=Array(repeating:Float(2),count:5120),tail=Array(repeating:Float(3),count:100)
        let original=first+later+tail
        try await prefix.begin(key)
        try await prefix.append(first,firstSample:key.startSample,for:key)
        try await prefix.append(later,firstSample:key.startSample+5120,for:key)
        let before=await prefixBackend.finishes;XCTAssertEqual(before,0)
        try await prefix.append(tail,firstSample:key.startSample+10240,for:key)
        let prefixed=try await prefix.finish(key,endSample:key.startSample+UInt64(original.count))
        let legacy=try await closed.recognize(original)
        let prefixSamples=await prefixBackend.received,closedSamples=await closedBackend.received
        let finishes=await prefixBackend.finishes
        XCTAssertEqual(prefixed,legacy);XCTAssertEqual(prefixSamples,original);XCTAssertEqual(closedSamples,original)
        XCTAssertEqual(finishes,1)
    }
    func testAbortAndLegacyRecognizeCannotResetTheActualHeldPrefixAccept()async throws{
        let backend=HeldPrefixFluidBackend(),adapter=FluidClosedActivityRecognizer(backend:backend),key=try key()
        try await adapter.begin(key);await backend.holdNext()
        let task=Task{try await adapter.append(Array(repeating:Float(1),count:5120),firstSample:key.startSample,for:key)}
        try await until{await backend.entered}
        do{try await adapter.abort(key);XCTFail("Reset under active accept must reject")}catch{}
        do{_=try await adapter.recognize([1]);XCTFail("Legacy work cannot steal prefix ownership")}catch{}
        let heldResets=await backend.resets;XCTAssertEqual(heldResets,1)
        await backend.release();try await task.value;try await adapter.abort(key)
        let bad=await backend.resetDuringAccept,resets=await backend.resets
        XCTAssertFalse(bad);XCTAssertEqual(resets,2)
    }
}
