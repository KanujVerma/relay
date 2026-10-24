import Dispatch
import Foundation
import XCTest
@testable import RelayNativeSession

private actor PrefixBackend:IncrementalActivityRecognizer {
    private(set) var begins:[RecognitionActivityKey]=[]
    private(set) var finishes:[RecognitionActivityKey]=[]
    private(set) var appends:[(RecognitionActivityKey,[Float])]=[]
    private(set) var legacy:[[Float]]=[]
    private(set) var aborts=0,resetDuringAccept=false,entered=false
    private var active:RecognitionActivityKey?,next:UInt64=0,busy=false,hold=false
    private var release:CheckedContinuation<Void,Never>?
    func holdAppend(){hold=true}
    func releaseAppend(){release?.resume();release=nil;hold=false}
    func begin(_ key:RecognitionActivityKey)async throws{
        guard active==nil,!busy else{throw NativeSessionError.invalidFrame}
        active=key;next=key.startSample;begins.append(key)
    }
    func append(_ samples:[Float],firstSample:UInt64,for key:RecognitionActivityKey)async throws{
        guard active==key,!busy,firstSample==next else{throw NativeSessionError.invalidFrame}
        busy=true
        if hold{entered=true;await withCheckedContinuation{release=$0}}
        appends.append((key,samples));next+=UInt64(samples.count);busy=false
    }
    func finish(_ key:RecognitionActivityKey,endSample:UInt64)async throws->String{
        guard active==key,!busy,next==endSample else{throw NativeSessionError.invalidFrame}
        finishes.append(key);active=nil;return "prefix final"
    }
    func abort(_ key:RecognitionActivityKey)async throws{
        if busy{resetDuringAccept=true;throw NativeSessionError.invalidFrame}
        guard active==key else{throw NativeSessionError.invalidFrame}
        aborts+=1;active=nil
    }
    func recognize(_ samples:[Float])async throws->String{
        guard active==nil,!busy else{throw NativeSessionError.invalidFrame}
        legacy.append(samples);return "closed final"
    }
}
private final class PrefixLaneProbe:@unchecked Sendable {
    private let lock=NSLock()
    private var values:[(UInt64,String,ActivityPreprocessingStatistics)]=[]
    private var errors:[SessionReason]=[]
    func final(_ activity:ClosedActivity,_ text:String,_ stats:ActivityPreprocessingStatistics){lock.withLock{values.append((activity.id,text,stats))}}
    func fail(_ reason:SessionReason,_ generation:UInt64){lock.withLock{errors.append(reason)}}
    var finals:[(UInt64,String,ActivityPreprocessingStatistics)]{lock.withLock{values}}
    var failures:[SessionReason]{lock.withLock{errors}}
}

@MainActor final class ActivityPreprocessingTests:XCTestCase {
    private func key(_ id:UInt64=1,start:UInt64=1600,lease supplied:PresentationLease?=nil)throws->RecognitionActivityKey{
        let authority=SessionPresentationAuthority(),lease=try supplied ?? authority.start()
        return RecognitionActivityKey(sourceCode:2,generation:1,activityID:id,startSample:start,lease:lease)
    }
    private func closed(_ key:RecognitionActivityKey,_ samples:[Float])->ClosedActivity{
        ClosedActivity(id:key.activityID,firstSequence:1,lastSequence:2,startHostTime:100,endHostTime:200,
            generation:key.generation,samples:samples,lease:key.lease,
            clock:NativeClockCalibration(hostTicksAtAnchor:0,uptimeNsAtAnchor:0,nsNumer:1,nsDenom:1))
    }
    private func lane(_ backend:PrefixBackend,_ probe:PrefixLaneProbe)->ActivityPreprocessingLane{
        ActivityPreprocessingLane(recognizer:backend,isActive:{true},onFinal:probe.final,onFailure:probe.fail)
    }
    private func until(_ predicate:()async->Bool)async throws{
        for _ in 0..<1500{if await predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NativeSessionError.modelUnavailable
    }
    func testOriginalPartitionAndSuffixProduceExactlyOneFinalWithoutLegacyReplay()async throws{
        let backend=PrefixBackend(),probe=PrefixLaneProbe(),lane=lane(backend,probe),key=try key()
        let first=Array(repeating:Float(1),count:5120),second=Array(repeating:Float(2),count:5120),tail=Array(repeating:Float(3),count:1024)
        let original=first+second+tail
        try await lane.begin(key)
        let offeredFirst=try await lane.offer(first,firstSample:key.startSample,for:key)
        let offeredSecond=try await lane.offer(second,firstSample:key.startSample+5120,for:key)
        XCTAssertTrue(offeredFirst);XCTAssertTrue(offeredSecond)
        try await lane.close(closed(key,original),endSample:key.startSample+UInt64(original.count),for:key)
        try await until{probe.finals.count==1};await lane.waitForQuiescence()
        let received=await backend.appends.flatMap{$0.1},legacy=await backend.legacy,finishes=await backend.finishes
        XCTAssertEqual(received,original);XCTAssertTrue(legacy.isEmpty);XCTAssertEqual(finishes,[key])
        XCTAssertEqual(probe.finals[0].0,key.activityID);XCTAssertEqual(probe.finals[0].2.prefixSamples,10240)
        XCTAssertEqual(probe.finals[0].2.suffixSamples,1024);XCTAssertEqual(probe.finals[0].2.closedSpanFallbacks,0)
        XCTAssertTrue(probe.failures.isEmpty)
    }
    func testSpeculativeQueuePressureFallsBackOnceAfterActualHeldAcceptAndKeepsFullOriginalSpan()async throws{
        let backend=PrefixBackend(),probe=PrefixLaneProbe(),lane=lane(backend,probe),key=try key()
        await backend.holdAppend();try await lane.begin(key)
        let first=Array(repeating:Float(1),count:5120),rest=Array(repeating:Float(2),count:5120)
        let offeredFirst=try await lane.offer(first,firstSample:key.startSample,for:key);XCTAssertTrue(offeredFirst)
        try await until{await backend.entered}
        for offset in 1...3{
            let accepted=try await lane.offer(rest,firstSample:key.startSample+UInt64(offset*5120),for:key);XCTAssertTrue(accepted)
        }
        let overflow=try await lane.offer(rest,firstSample:key.startSample+20480,for:key)
        let repeatOverflow=try await lane.offer(rest,firstSample:key.startSample+20480,for:key)
        XCTAssertFalse(overflow);XCTAssertFalse(repeatOverflow)
        let original=first+Array(repeating:Float(2),count:20480)+Array(repeating:Float(3),count:1024)
        try await lane.close(closed(key,original),endSample:key.startSample+UInt64(original.count),for:key)
        let beforeAborts=await backend.aborts,beforeLegacy=await backend.legacy
        XCTAssertEqual(beforeAborts,0);XCTAssertTrue(beforeLegacy.isEmpty);XCTAssertTrue(probe.finals.isEmpty)
        await backend.releaseAppend();try await until{probe.finals.count==1};await lane.waitForQuiescence()
        let replay=await backend.legacy,aborts=await backend.aborts,badReset=await backend.resetDuringAccept,finishes=await backend.finishes
        XCTAssertEqual(replay,[original]);XCTAssertEqual(aborts,1);XCTAssertFalse(badReset);XCTAssertTrue(finishes.isEmpty)
        XCTAssertEqual(probe.finals[0].1,"closed final");XCTAssertEqual(probe.finals[0].2.closedSpanFallbacks,1)
        XCTAssertEqual(probe.finals[0].2.closedReplaySamples,original.count);XCTAssertTrue(probe.failures.isEmpty)
    }
    func testCancelJoinsActualHeldAcceptBeforeResetAndCannotPublishOrReplay()async throws{
        let backend=PrefixBackend(),probe=PrefixLaneProbe(),lane=lane(backend,probe),key=try key()
        await backend.holdAppend();try await lane.begin(key)
        _=try await lane.offer(Array(repeating:Float(1),count:5120),firstSample:key.startSample,for:key)
        try await until{await backend.entered};await lane.cancel()
        var joined=false;let join=Task{await lane.waitForQuiescence();joined=true}
        for _ in 0..<10{await Task.yield()}
        let before=await backend.aborts;XCTAssertFalse(joined);XCTAssertEqual(before,0)
        await backend.releaseAppend();await join.value
        let bad=await backend.resetDuringAccept,aborts=await backend.aborts,replay=await backend.legacy
        XCTAssertTrue(joined);XCTAssertFalse(bad);XCTAssertEqual(aborts,1);XCTAssertTrue(replay.isEmpty)
        XCTAssertTrue(probe.finals.isEmpty);XCTAssertTrue(probe.failures.isEmpty)
    }
    func testNextOriginalActivityWaitsForOldFinishAndNeverResetsItsLiveState()async throws{
        let backend=PrefixBackend(),probe=PrefixLaneProbe(),lane=lane(backend,probe)
        let old=try key()
        let next=try key(2,start:100_000,lease:PresentationLease(captureSessionID:old.lease.captureSessionID,
            sessionEpoch:old.lease.sessionEpoch,presentationGeneration:old.lease.presentationGeneration+1))
        let first=Array(repeating:Float(1),count:5120),second=Array(repeating:Float(2),count:5120)
        await backend.holdAppend();try await lane.begin(old)
        _=try await lane.offer(first,firstSample:old.startSample,for:old);try await until{await backend.entered}
        try await lane.close(closed(old,first),endSample:old.startSample+5120,for:old)
        try await lane.begin(next);_=try await lane.offer(second,firstSample:next.startSample,for:next)
        try await lane.close(closed(next,second),endSample:next.startSample+5120,for:next)
        let before=await backend.begins;XCTAssertEqual(before,[old])
        await backend.releaseAppend();try await until{probe.finals.count==2};await lane.waitForQuiescence()
        let begins=await backend.begins,finishes=await backend.finishes,bad=await backend.resetDuringAccept
        XCTAssertEqual(begins,[old,next]);XCTAssertEqual(finishes,[old,next]);XCTAssertFalse(bad)
        XCTAssertEqual(probe.finals.map{$0.0},[1,2]);XCTAssertTrue(probe.failures.isEmpty)
    }
}
