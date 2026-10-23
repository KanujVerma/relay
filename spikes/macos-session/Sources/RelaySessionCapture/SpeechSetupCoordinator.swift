import Combine
import Foundation

public enum SpeechSetupStage:Sendable,Equatable {case notPrepared,checking,downloading,validating,ready,unavailable,cancelled}
public enum SpeechSetupRecovery:Sendable,Equatable {case none,retry,openSettings}
public struct SpeechSetupSnapshot:Sendable,Equatable {
    public let stage:SpeechSetupStage
    public let completedBytes:UInt64?
    public let totalBytes:UInt64?
    public let progressFraction:Double?
    public let userMessage:String
    public let recovery:SpeechSetupRecovery
    public let isBusy:Bool
    public init(stage:SpeechSetupStage = .notPrepared,completedBytes:UInt64?=nil,totalBytes:UInt64?=nil,
                progressFraction:Double?=nil,userMessage:String="Speech files prepare automatically when you start.",
                recovery:SpeechSetupRecovery = .none,isBusy:Bool=false){
        self.stage=stage;self.completedBytes=completedBytes;self.totalBytes=totalBytes
        self.progressFraction=progressFraction;self.userMessage=userMessage;self.recovery=recovery;self.isBusy=isBusy
    }
}

/// Issued only inside the managed preparation port. This is asset integrity and
/// the reviewed dependency policy, never audio/recording/account permission.
public struct PreparedSpeechAssets:Sendable,Equatable {
    public let manifestID:String
    public let asrModelRoot:URL
    public let vadCompiledModel:URL
    init(manifestID:String,asrModelRoot:URL,vadCompiledModel:URL){
        self.manifestID=manifestID;self.asrModelRoot=asrModelRoot;self.vadCompiledModel=vadCompiledModel
    }
}

public enum SpeechSetupError:Error,Sendable,Equatable,LocalizedError {
    case invalidManifest,invalidArtifacts,downloadUnavailable,offline,insufficientStorage,unsupportedPlatform,advancedOverrideInvalid
    public var errorDescription:String? {
        switch self {
        case .invalidManifest:"The speech dependency configuration is unavailable."
        case .invalidArtifacts:"Speech files could not be verified. Retry preparation."
        case .downloadUnavailable:"Speech files could not be downloaded. Check your connection and retry."
        case .offline:"Connect to the internet once to prepare local speech files."
        case .insufficientStorage:"Free at least 1 GB of storage, then retry speech preparation."
        case .unsupportedPlatform:"This device cannot prepare the selected local speech models."
        case .advancedOverrideInvalid:"The advanced speech folders are incomplete or unavailable."
        }
    }
    var recovery:SpeechSetupRecovery {
        switch self {
        case .invalidManifest,.unsupportedPlatform,.advancedOverrideInvalid:.openSettings
        default:.retry
        }
    }
}

struct SpeechSetupProgress:Sendable {
    let stage:SpeechSetupStage
    let completedBytes:UInt64?
    let totalBytes:UInt64?
    init(_ stage:SpeechSetupStage,completedBytes:UInt64?=nil,totalBytes:UInt64?=nil){self.stage=stage;self.completedBytes=completedBytes;self.totalBytes=totalBytes}
}

/// One owned preparation. Cancellation retires its intent before task cleanup;
/// ready means verified local assets only, not permissions or recognizer startup.
@MainActor public final class SpeechSetupCoordinator:ObservableObject {
    typealias Preparation=@Sendable (@escaping @Sendable(SpeechSetupProgress)->Void) async throws ->PreparedSpeechAssets
    private struct Operation {let id:UUID;let task:Task<PreparedSpeechAssets,any Error>}
    @Published public private(set) var snapshot=SpeechSetupSnapshot()
    private let preparation:Preparation
    private var generation=UUID()
    private var operation:Operation?
    public convenience init(){self.init(prepare:{_ in throw SpeechSetupError.downloadUnavailable})}
    init(prepare:@escaping Preparation){preparation=prepare}
    public func prepare()async throws->PreparedSpeechAssets {
        try Task.checkCancellation()
        let owned:Operation
        if let operation {
            guard generation==operation.id else{throw CancellationError()};owned=operation
        }else{
            let id=UUID();generation=id
            snapshot=SpeechSetupSnapshot(stage:.checking,userMessage:"Checking local speech files…",isBusy:true)
            let applyProgress:@MainActor @Sendable(SpeechSetupProgress)->Void = {[weak self] progress in self?.update(progress,for:id)}
            let task=Task{[preparation] in
                try await preparation{progress in Task{@MainActor in applyProgress(progress)}}
            }
            owned=Operation(id:id,task:task);operation=owned
        }
        do {
            let assets=try await withTaskCancellationHandler{try await owned.task.value}onCancel:{Task{@MainActor [weak self] in self?.cancel()}}
            guard generation==owned.id,!owned.task.isCancelled,!Task.isCancelled else{throw CancellationError()}
            if operation?.id==owned.id {
                operation=nil
                snapshot=SpeechSetupSnapshot(stage:.ready,completedBytes:snapshot.totalBytes,totalBytes:snapshot.totalBytes,progressFraction:1,userMessage:"Local speech files are ready.")
            }
            return assets
        }catch{
            if operation?.id==owned.id {
                operation=nil
                if generation != owned.id || error is CancellationError || owned.task.isCancelled {
                    snapshot=SpeechSetupSnapshot(stage:.cancelled,userMessage:"Speech preparation cancelled.",recovery:.retry)
                }else{
                    let failure=(error as? SpeechSetupError) ?? .downloadUnavailable
                    snapshot=SpeechSetupSnapshot(stage:.unavailable,userMessage:failure.localizedDescription,recovery:failure.recovery)
                }
            }
            throw error
        }
    }
    public func cancel(){
        guard let operation else{return}
        generation=UUID();operation.task.cancel()
        snapshot=SpeechSetupSnapshot(stage:.cancelled,userMessage:"Finishing cancelled speech preparation…",recovery:.retry,isBusy:true)
    }
    public func waitForQuiescence()async{
        while let owned=operation{_ = await owned.task.result;await Task.yield()}
    }
    private func update(_ progress:SpeechSetupProgress,for id:UUID){
        guard generation==id,operation?.id==id,[.checking,.downloading,.validating].contains(progress.stage) else{return}
        let fraction:Double?
        if let done=progress.completedBytes,let total=progress.totalBytes,total>0{fraction=min(1,Double(done)/Double(total))}else{fraction=nil}
        let message:String
        switch progress.stage{
        case .downloading:message="Downloading local speech files…"
        case .validating:message="Verifying local speech files…"
        default:message="Checking local speech files…"
        }
        snapshot=SpeechSetupSnapshot(stage:progress.stage,completedBytes:progress.completedBytes,totalBytes:progress.totalBytes,progressFraction:fraction,userMessage:message,isBusy:true)
    }
}
