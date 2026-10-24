import Combine
import Foundation

public enum LearningMemoryPhase:Sendable,Equatable{case off,working,ready,unavailable}
public struct LearningMemorySnapshot:Sendable {
    public internal(set) var phase:LearningMemoryPhase = .off
    public internal(set) var isBusy=false,episodeCount=0
    public internal(set) var rules:[LearningRule]=[]
    public internal(set) var message="Learning Memory is off. Current-session context stays separate."
}
/// Read-only request data. Its identity is usable only through the original
/// coordinator's owns check and the app's independently current native binding.
public final class LearningProjectionSnapshot:Sendable {
    public let revision=UUID(),payload:LearningRequestProjection,lifetimeEpoch:UUID
    fileprivate let retentionEpoch:UUID,controlRevision:UUID?,requiresRetention:Bool
    fileprivate init(payload:LearningRequestProjection,lifetime:UUID,retention:UUID,controlRevision:UUID?,requiresRetention:Bool){
        self.payload=payload;lifetimeEpoch=lifetime;retentionEpoch=retention;self.controlRevision=controlRevision;self.requiresRetention=requiresRetention
    }
}

/// One optional source owner and one bounded deterministic writer. All durable
/// work goes through the existing History owner. No provider/model call exists.
@MainActor public final class LearningMemoryCoordinator:ObservableObject {
    @Published public private(set) var snapshot=LearningMemorySnapshot()
    public let session=LearningSessionMemory()
    public var onRetire:(@MainActor (UUID)->Void)?
    private let preferences:any LearningControlPreferences
    private let persistence:LearningPersistencePorts
    private let canEnable:@MainActor ()->Bool
    private let clock:@Sendable ()->Date
    private var state=LearningMemorySnapshot(),archive=LearningArchive()
    private var lastControl:LearningControlRecord?,lastReceipt:LearningControlReceipt?
    private var sourceEpoch:UUID?,projectionEpoch=UUID(),retentionEpoch=UUID()
    private var ready=false
    private struct Affiliation {let workspace:UUID,record:UUID,capture:String,source:TranscriptSource?,expiresAt:TimeInterval?;var sources:Set<TranscriptSource>=[]}
    private var finalAffiliations:[String:Affiliation]=[:],captureAffiliations:[String:Affiliation]=[:]
    private final class Flight {
        let id=UUID(),generation:UUID
        var task:Task<Void,Error>?
        init(_ generation:UUID){self.generation=generation}
    }
    private var control:Flight?
    private struct Writer {let id:UUID,generation:UUID,task:Task<Void,Never>}
    private var writer:Writer?
    private var pending:[LearningEpisode]=[],pendingBytes=0
    private var publishing=false,publicationPending=false
    public var isBusy:Bool{control != nil || writer != nil}
    public var retainedEpisodes:[LearningEpisode]{retentionAvailable ? archive.episodes:[]}
    public init(preferences:any LearningControlPreferences,persistence:LearningPersistencePorts,canEnable:@escaping @MainActor ()->Bool,
                clock:@escaping @Sendable ()->Date={Date()}){
        self.preferences=preferences;self.persistence=persistence;self.canEnable=canEnable;self.clock=clock
        session.onEpisode={[weak self] in self?.enqueue($0)}
        session.onObservation={[weak self] in self?.rememberAffiliation($0)}
    }
    private var retentionAvailable:Bool{
        guard ready,let scope=persistence.scope(),scope.workspaceEpoch==sourceEpoch,
              let control=archive.control,control.enabled,lastReceipt?.matches(control)==true else{return false}
        return true
    }
    private func publish(){
        publicationPending=true;guard !publishing else{return};publishing=true;defer{publishing=false}
        while publicationPending{
            publicationPending=false;state.isBusy=isBusy
            state.rules=ready ? archive.rules:[];state.episodeCount=ready ? archive.episodes.count:0;snapshot=state
        }
    }
    @discardableResult private func retireProjection()->UUID{
        let old=projectionEpoch;projectionEpoch=UUID();let next=projectionEpoch;onRetire?(old);return next
    }
    @discardableResult private func retireRetention()->UUID{
        retentionEpoch=UUID();let generation=retentionEpoch
        ready=false;archive=LearningArchive();pending=[];pendingBytes=0;writer?.task.cancel()
        _=retireProjection();return generation
    }
    private func current(_ flight:Flight,scope:LearningPersistenceScope?)throws{
        guard control === flight,retentionEpoch==flight.generation,!Task.isCancelled else{throw HistoryError.stale}
        if let scope{guard persistence.scope()?.workspaceEpoch==scope.workspaceEpoch else{throw HistoryError.stale}}
    }
    private func checked(_ receipt:LearningArchiveReceipt,scope:LearningPersistenceScope)throws{
        guard receipt.workspaceEpoch==scope.workspaceEpoch,persistence.scope()?.workspaceEpoch==scope.workspaceEpoch else{throw HistoryError.stale}
        try receipt.archive.validate()
    }
    private func adopt(_ receipt:LearningArchiveReceipt,preference:LearningControlReceipt,scope:LearningPersistenceScope)throws{
        try checked(receipt,scope:scope);try preference.validate()
        guard preference.matches(receipt.archive.control),let actual=receipt.archive.control else{throw HistoryError.stale}
        lastControl=actual;lastReceipt=preference;sourceEpoch=scope.workspaceEpoch
        ready=actual.enabled;archive=actual.enabled ? receipt.archive:LearningArchive()
        state.phase=actual.enabled ? .ready:.off
        state.message=actual.enabled ? "Tentative adjustments use retained source examples. Review why or undo below.":"Learning Memory is off. Retained examples and adjustments were cleared."
    }
    public func restore()async throws{
        try Task.checkCancellation()
        guard control==nil else{throw HistoryError.inUse}
        let preference:LearningControlReceipt
        do{preference=try preferences.read();try preference.validate()}
        catch{
            _=retireRetention();state.phase = .unavailable;state.message="Learning controls could not be read. Retained memory is unavailable.";publish();throw error
        }
        guard preference.enabled || preference.pending != nil else{
            if ready{_=retireRetention()};lastReceipt=preference;state.phase = .off;publish();return
        }
        if preference.pending==nil,retentionAvailable,lastReceipt==preference{return}
        try await perform(.restore(preference))
    }
    public func enable()async throws{
        try Task.checkCancellation()
        guard canEnable(),persistence.scope() != nil else{throw HistoryError.unavailable}
        guard control==nil else{throw HistoryError.inUse}
        try await perform(.enable)
    }
    private enum Action {case restore(LearningControlReceipt),enable,disable,reset,suppress(String)}
    public func disable()->Task<Void,Error>{begin(.disable)}
    public func reset()->Task<Void,Error>{begin(.reset)}
    public func undo(_ ruleID:String)->Task<Void,Error>{
        guard LearningControlRecord.knownRuleIDs.contains(ruleID),retentionAvailable,archive.rules.contains(where:{$0.id==ruleID}) else{return Task{throw HistoryError.stale}}
        return begin(.suppress(ruleID))
    }
    private func begin(_ action:Action)->Task<Void,Error>{
        session.clearPendingAttribution()
        let old=control,oldWriter=writer?.task
        old?.task?.cancel()
        let generation=retireRetention()
        guard retentionEpoch==generation else{return Task{throw HistoryError.stale}}
        let flight=Flight(generation);control=flight
        state.phase = .working;state.message="Learning is unavailable while this change finishes."
        let task=Task{[self,flight] in
            _=await old?.task?.result;await oldWriter?.value
            try await execute(action,flight:flight)
        }
        flight.task=task;publish();return task
    }
    private func perform(_ action:Action)async throws{
        try Task.checkCancellation();guard control==nil else{throw HistoryError.inUse}
        switch action{case .enable:session.clearPendingAttribution();case .restore(let receipt):if receipt.pending != nil{session.clearPendingAttribution()};default:break}
        let oldWriter=writer?.task,generation=retireRetention()
        guard retentionEpoch==generation else{throw HistoryError.stale}
        let flight=Flight(generation);control=flight
        state.phase = .working;state.message="Opening source-backed Learning Memory…"
        let task=Task{[self,flight] in await oldWriter?.value;try await execute(action,flight:flight)}
        flight.task=task;publish()
        try await withTaskCancellationHandler{try await task.value}onCancel:{task.cancel()}
    }
    private func execute(_ action:Action,flight:Flight)async throws{
        do{
            try current(flight,scope:nil)
            let scope=persistence.scope()
            sourceEpoch=scope?.workspaceEpoch
            var loaded:LearningArchiveReceipt?
            if let scope{loaded=try await persistence.load();try current(flight,scope:scope);try checked(loaded!,scope:scope)}
            let observed=try preferences.read();try observed.validate()
            try current(flight,scope:scope)
            var proposed:LearningPendingControl?
            switch action{
            case .restore(let original):
                guard observed==original else{throw HistoryError.stale}
                proposed=original.pending
                if proposed==nil{
                    guard let loaded,let scope,original.matches(loaded.archive.control),loaded.archive.control?.enabled==true else{throw HistoryError.stale}
                    try adopt(loaded,preference:original,scope:scope)
                }
            case .enable,.disable,.reset,.suppress:
                let base=loaded?.archive.control ?? lastControl
                var suppressed=base?.suppressedRuleIDs ?? []
                let enabled:Bool,clear:Bool
                switch action{
                case .enable:enabled=true;clear=false
                case .disable:enabled=false;clear=true
                case .reset:enabled=base?.enabled ?? observed.enabled;clear=true;suppressed=[]
                case .suppress(let id):enabled=base?.enabled ?? observed.enabled;clear=false;suppressed.insert(id)
                case .restore:throw HistoryError.invalid
                }
                proposed=LearningPendingControl(target:LearningControlRecord(revision:UUID(),enabled:enabled,suppressedRuleIDs:suppressed),expectedRevision:base?.revision ?? observed.revision,clearExamples:clear)
                let denial=try preferences.deny(proposed!);try denial.validate()
                guard denial.pending==proposed,!denial.enabled else{throw HistoryError.unavailable}
                lastReceipt=denial;try current(flight,scope:scope)
            }
            if let proposed{
                guard let scope else{throw HistoryError.closed}
                // Pending intent must still be the exact user-owned control.
                guard try preferences.read().pending==proposed else{throw HistoryError.stale}
                let result=try await persistence.mutate(.control(proposed));try current(flight,scope:scope);try checked(result,scope:scope)
                guard result.archive.control==proposed.target else{throw HistoryError.stale}
                let committed=try preferences.commit(proposed.target);try current(flight,scope:scope)
                guard committed.matches(proposed.target) else{throw HistoryError.unavailable}
                try adopt(result,preference:committed,scope:scope)
            }
            try current(flight,scope:scope)
            if control === flight{control=nil};publish();startWriter()
        }catch{
            if control === flight{
                control=nil;ready=false;archive=LearningArchive();state.phase = .unavailable
                state.message="Learning could not finish this change. No retained adjustment is available. Open History and retry."
                publish()
            }
            throw error
        }
    }
    public func retire(_ notice:LearningSourceRetirement){
        let affected:Set<String>,captures:Set<String>
        switch notice{
        case .workspace:affected=[];captures=[]
        case .record(_,let id):
            affected=Set(finalAffiliations.filter{$0.value.workspace==notice.workspaceEpoch && $0.value.record==id}.map(\.key))
            captures=Set(captureAffiliations.filter{$0.value.workspace==notice.workspaceEpoch && $0.value.record==id}.map(\.key))
        case .source(_,let id,let capture,let source):
            affected=Set(finalAffiliations.filter{$0.value.workspace==notice.workspaceEpoch && $0.value.record==id && $0.value.capture==capture && $0.value.source==source}.map(\.key))
            captures=Set(captureAffiliations.filter{$0.value.workspace==notice.workspaceEpoch && $0.value.record==id && $0.key==capture && $0.value.sources.contains(source)}.map(\.key))
        }
        if !affected.isEmpty || !captures.isEmpty{
            session.removeFinals(affected);session.clearPendingAttribution(captureIDs:captures)
            finalAffiliations=finalAffiliations.filter{!affected.contains($0.key)}
            if case .record=notice{captureAffiliations=captureAffiliations.filter{!captures.contains($0.key)}}
            if case .source(_,_,_,let source)=notice{for capture in captures{captureAffiliations[capture]?.sources.remove(source)}}
        }
        if sourceEpoch==notice.workspaceEpoch{
            control?.task?.cancel();_=retireRetention();sourceEpoch=nil
            state.phase = .unavailable;state.message="Learning sources are unavailable. Reopen History before using retained adjustments.";publish()
        }else if !affected.isEmpty || !captures.isEmpty{_=retireProjection()}
    }
    public func pauseSession(){session.pause();_=retireProjection()}
    public func endSession(){session.end();finalAffiliations=[:];captureAffiliations=[:];_=retireProjection()}
    private func rememberAffiliation(_ observation:ValidatedTranscriptObservation){
        let retained=session.retainedFinalIDs
        finalAffiliations=finalAffiliations.filter{retained.contains($0.key)}
        let retainedCaptures=Set(finalAffiliations.values.map(\.capture))
        captureAffiliations=captureAffiliations.filter{retainedCaptures.contains($0.key) || $0.key==session.currentCaptureID}
        guard let scope=persistence.affiliation(observation),let record=scope.recordID else{return}
        if observation.event.kind == .sessionStarted{
            let capture=HistoryCapture.identity(observation.event.captureSessionID,observation.event.sessionEpoch)
            var sources:Set<TranscriptSource>=[]
            if observation.event.payload["microphoneEnabled"] == .bool(true){sources.insert(.microphone)}
            if case .string=observation.event.payload["selectedBundleID"]{sources.insert(.selectedAppAudio)}
            captureAffiliations[capture]=Affiliation(workspace:scope.workspaceEpoch,record:record,capture:capture,source:nil,expiresAt:scope.expiresAt,sources:sources)
        }else if let final=observation.final{
            let value=Affiliation(workspace:scope.workspaceEpoch,record:record,capture:final.captureID,source:final.source,expiresAt:scope.expiresAt)
            finalAffiliations[final.id]=value
            if var captured=captureAffiliations[final.captureID],captured.workspace==scope.workspaceEpoch,captured.record==record{
                captured.sources.insert(final.source);captureAffiliations[final.captureID]=captured
            }else{var captured=value;captured.sources=[final.source];captureAffiliations[final.captureID]=captured}
        }
    }
    public func capture(question:String)->LearningProjectionSnapshot?{
        let now=clock().timeIntervalSince1970
        var value=retentionAvailable ? LearningDerivation.project(archive,question:question,now:now):LearningRequestProjection(scope:LearningScope.matching(question))
        value.continuity=session.projection(question:question)
        if let interaction=session.interactionProjection(question:question){value.interactions=[interaction]}
        value.evidenceGap=session.evidenceGap;value.bound()
        guard !value.isEmpty else{return nil}
        return LearningProjectionSnapshot(payload:value,lifetime:projectionEpoch,retention:retentionEpoch,controlRevision:archive.control?.revision,requiresRetention:!value.supportIDs.isEmpty)
    }
    public func owns(_ original:LearningProjectionSnapshot)->Bool{
        guard original.lifetimeEpoch==projectionEpoch else{return false}
        guard !original.requiresRetention else{
            return original.retentionEpoch==retentionEpoch && retentionAvailable && original.controlRevision==archive.control?.revision
                && original.payload.expiresAt.map{$0>clock().timeIntervalSince1970} != false
        }
        return true
    }
    private func enqueue(_ original:LearningEpisode){
        guard retentionAvailable,control==nil,let scope=persistence.scope(),let recordID=scope.recordID,let expiry=scope.expiresAt,
              let episode=try? original.retained(recordID:recordID,expiresAt:expiry),
              let bytes=try? HistoryJSON.encode(episode).count else{return}
        guard pending.count<8,pendingBytes+bytes<=LearningBounds.liveBytes else{state.message="Learning reached its pending limit. Some examples were not retained.";publish();return}
        pending.append(episode);pendingBytes+=bytes;startWriter()
    }
    private func startWriter(){
        guard writer==nil,control==nil,retentionAvailable,!pending.isEmpty else{return}
        let id=UUID(),generation=retentionEpoch,source=sourceEpoch
        let task=Task{[weak self] in
            guard let self else{return}
            while !Task.isCancelled,self.retentionEpoch==generation,self.retentionAvailable,!self.pending.isEmpty{
                let episode=self.pending.removeFirst();self.pendingBytes=max(0,self.pendingBytes-((try? HistoryJSON.encode(episode).count) ?? 0))
                do{
                    let result=try await self.persistence.mutate(.save(episode))
                    guard !Task.isCancelled,self.retentionEpoch==generation,self.sourceEpoch==source,
                          let scope=self.persistence.scope(),scope.workspaceEpoch==result.workspaceEpoch else{break}
                    try self.checked(result,scope:scope)
                    guard result.archive.control==self.lastControl,self.lastReceipt?.matches(result.archive.control)==true else{throw HistoryError.stale}
                    self.archive=result.archive;self.publish()
                }catch{
                    if self.retentionEpoch==generation{
                        _=self.retireRetention();self.state.phase = .unavailable
                        self.state.message="Learning reflection did not finish. Previous derived data is unavailable until reopened.";self.publish()
                    };break
                }
            }
            if self.writer?.id==id{self.writer=nil};self.publish();self.startWriter()
        }
        writer=Writer(id:id,generation:generation,task:task);publish()
    }
    public func waitForQuiescence()async{
        while control != nil || writer != nil{
            let oldControl=control,oldWriter=writer
            _=await oldControl?.task?.result;await oldWriter?.task.value;await Task.yield()
        }
    }
}
