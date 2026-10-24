import Foundation

public struct SpeechActivityObservation:Sendable {
    public let boundaries:[SpeechBoundary]
    public let processedSamples:UInt64
    public let safePrefixEnd:UInt64?
    public init(boundaries:[SpeechBoundary],processedSamples:UInt64,safePrefixEnd:UInt64?){
        self.boundaries=boundaries;self.processedSamples=processedSamples;self.safePrefixEnd=safePrefixEnd
    }
}
public protocol RecognitionWatermarkDetector:SpeechActivityDetector {
    func observe(_ samples:[Float])async throws->SpeechActivityObservation
}

/// Created only by the native source owner. This is local recognizer identity,
/// not a permission, serialized claim or alternative presentation authority.
public struct RecognitionActivityKey:Sendable,Equatable {
    private let identity=UUID()
    public let sourceCode:UInt32
    public let generation:UInt64
    public let activityID:UInt64
    public let startSample:UInt64
    public let lease:PresentationLease
    init(sourceCode:UInt32,generation:UInt64,activityID:UInt64,startSample:UInt64,lease:PresentationLease){
        self.sourceCode=sourceCode;self.generation=generation;self.activityID=activityID
        self.startSample=startSample;self.lease=lease
    }
}
public protocol IncrementalActivityRecognizer:ActivityRecognizer {
    func begin(_ key:RecognitionActivityKey)async throws
    func append(_ samples:[Float],firstSample:UInt64,for key:RecognitionActivityKey)async throws
    func finish(_ key:RecognitionActivityKey,endSample:UInt64)async throws->String
    /// Only the serialized owner calls this after actual accept/finish returns.
    /// Implementations must reject a reset underneath active model work.
    func abort(_ key:RecognitionActivityKey)async throws
}

struct ActivityPreprocessingStatistics:Sendable {
    var prefixSamples=0
    var prefixCompletedBeforeCloseSamples=0
    var suffixSamples=0
    var closedSpanFallbacks=0
    var closedReplaySamples=0
}

/// One serial owner per existing source/backend. Producer operations never
/// await model work. PCM pressure selects one original local fallback; final,
/// fallback and cancellation are out-of-band state, never dropped queue items.
actor ActivityPreprocessingLane {
    private struct Piece {let first:UInt64;let samples:[Float]}
    private final class Job {
        let key:RecognitionActivityKey
        var nextOffered:UInt64
        var pieces:[Piece]=[]
        var closed:ClosedActivity?
        var finalEnd:UInt64?
        var fallback=false,started=false,legacyStarted=false
        var stats=ActivityPreprocessingStatistics()
        init(_ key:RecognitionActivityKey){self.key=key;nextOffered=key.startSample}
    }
    private let recognizer:any IncrementalActivityRecognizer
    private let isActive:@Sendable ()->Bool
    private let onFinal:@Sendable (ClosedActivity,String,ActivityPreprocessingStatistics)->Void
    private let onFailure:@Sendable (SessionReason,UInt64)->Void
    private var jobs:[Job]=[]
    private var pendingSamples=0
    private var stopped=false
    private var signature:RecognitionActivityKey?
    private var lastActivity:UInt64=0,lastStart:UInt64=0
    private var activeKey:RecognitionActivityKey?
    private var drainer:Task<Void,Never>?
    private var waiter:CheckedContinuation<Void,Never>?

    init(recognizer:any IncrementalActivityRecognizer,isActive:@escaping @Sendable ()->Bool,
         onFinal:@escaping @Sendable (ClosedActivity,String,ActivityPreprocessingStatistics)->Void,
         onFailure:@escaping @Sendable (SessionReason,UInt64)->Void){
        self.recognizer=recognizer;self.isActive=isActive;self.onFinal=onFinal;self.onFailure=onFailure
    }
    func begin(_ key:RecognitionActivityKey)throws{
        guard !stopped,isActive(),[1,2].contains(key.sourceCode),key.generation>0,key.activityID>lastActivity,
              key.startSample>=lastStart,jobs.count<2 else{throw NativeSessionError.invalidFrame}
        if let s=signature{
            guard s.sourceCode==key.sourceCode,s.generation==key.generation,
                  s.lease.captureSessionID==key.lease.captureSessionID,s.lease.sessionEpoch==key.lease.sessionEpoch else{
                throw NativeSessionError.invalidFrame
            }
        }else{signature=key}
        lastActivity=key.activityID;lastStart=key.startSample;jobs.append(Job(key));wake()
        if drainer==nil{drainer=Task{await run()}}
    }
    func offer(_ samples:[Float],firstSample:UInt64,for key:RecognitionActivityKey)throws->Bool{
        guard !stopped,isActive(),let job=jobs.first(where:{$0.key==key}),job.closed==nil else{throw NativeSessionError.invalidFrame}
        let (end,overflow)=firstSample.addingReportingOverflow(UInt64(samples.count))
        guard !overflow,firstSample==job.nextOffered,samples.count==5120,
              samples.allSatisfy(\.isFinite),end>=key.startSample,
              end-key.startSample<=UInt64(NativeSessionLimits.maximumActivitySamples) else{throw NativeSessionError.invalidFrame}
        if job.fallback{return false}
        let count=jobs.reduce(0){$0+$1.pieces.count}
        if pendingSamples+samples.count>16_000 || count>=32{
            job.fallback=true
            pendingSamples-=job.pieces.reduce(0){$0+$1.samples.count};job.pieces=[];wake()
            return false
        }
        job.nextOffered=end;job.pieces.append(Piece(first:firstSample,samples:samples));pendingSamples+=samples.count
        wake();return true
    }
    func close(_ activity:ClosedActivity,endSample:UInt64,for key:RecognitionActivityKey)throws{
        guard !stopped,isActive(),let job=jobs.first(where:{$0.key==key}),job.closed==nil,
              activity.id==key.activityID,activity.generation==key.generation,activity.lease==key.lease,
              !activity.samples.isEmpty,activity.samples.count<=NativeSessionLimits.maximumActivitySamples,
              activity.samples.allSatisfy(\.isFinite),endSample>=key.startSample,
              endSample-key.startSample==UInt64(activity.samples.count),job.nextOffered<=endSample else{
            throw NativeSessionError.invalidFrame
        }
        job.stats.prefixCompletedBeforeCloseSamples=job.stats.prefixSamples
        job.closed=activity;job.finalEnd=endSample;wake()
    }
    func cancel(){
        stopped=true;drainer?.cancel();discardQueuedData();wake()
    }
    func waitForQuiescence()async{
        while let original=drainer{await original.value}
    }
    private var live:Bool{!stopped && !Task.isCancelled && isActive()}
    private func wake(){let old=waiter;waiter=nil;old?.resume()}
    private func waitForInput()async{await withCheckedContinuation{waiter=$0}}
    private func discardQueuedData(){
        for job in jobs{job.pieces=[];job.closed=nil};pendingSamples=0
    }
    private func run()async{
        var failure:UInt64?
        do{try await runLoop()}
        catch{if live{failure=jobs.first?.key.generation};stopped=true}
        // Every awaited backend operation has returned before this cleanup.
        if let activeKey{try? await recognizer.abort(activeKey)}
        activeKey=nil;discardQueuedData();jobs=[];wake();drainer=nil
        if let failure{onFailure(.asrUnavailable,failure)}
    }
    private func runLoop()async throws{
        while live{
            guard let job=jobs.first else{return}
            if job.fallback{
                if job.started{
                    try await recognizer.abort(job.key);job.started=false;activeKey=nil
                    guard live else{return}
                }
                guard let closed=job.closed else{await waitForInput();continue}
                guard !job.legacyStarted else{throw NativeSessionError.invalidFrame}
                job.legacyStarted=true;job.stats.closedSpanFallbacks=1;job.stats.closedReplaySamples=closed.samples.count
                let text=try await recognizer.recognize(closed.samples)
                guard live else{return};complete(job,closed,text);continue
            }
            if !job.started{
                job.started=true;activeKey=job.key
                try await recognizer.begin(job.key)
                guard live else{return}
                if job.fallback{continue}
            }
            if !job.pieces.isEmpty{
                let piece=job.pieces.removeFirst();pendingSamples-=piece.samples.count
                try await recognizer.append(piece.samples,firstSample:piece.first,for:job.key)
                job.stats.prefixSamples+=piece.samples.count
                continue
            }
            guard let closed=job.closed,let finalEnd=job.finalEnd else{await waitForInput();continue}
            var offset=job.stats.prefixSamples
            guard offset<=closed.samples.count else{throw NativeSessionError.invalidFrame}
            while offset<closed.samples.count{
                guard live else{return}
                let end=min(offset+5120,closed.samples.count)
                try await recognizer.append(Array(closed.samples[offset..<end]),firstSample:job.key.startSample+UInt64(offset),for:job.key)
                job.stats.suffixSamples+=end-offset;offset=end
            }
            guard live else{return}
            let text=try await recognizer.finish(job.key,endSample:finalEnd)
            activeKey=nil;job.started=false
            guard live else{return};complete(job,closed,text)
        }
    }
    private func complete(_ job:Job,_ closed:ClosedActivity,_ text:String){
        guard jobs.first === job else{return}
        jobs.removeFirst();onFinal(closed,text,job.stats)
    }
}
