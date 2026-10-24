import Combine
import Foundation

public enum SessionContextUseStatus:Sendable,Equatable {case off,idle,opening,restoring,ready,closing,missing,unavailable}
public enum SessionContextRestoreResult:Sendable,Equatable {case disabled,ready,missing,unavailable,stale,busy}
public struct SessionContextUseSnapshot:Sendable,Equatable {
    public let useInSessions:Bool
    public let status:SessionContextUseStatus
    public let isBusy:Bool
    public let message:String
}

/// Root supplies the actual current native helper/profile binding, not JSON
/// identity or a caller's claim that a profile is ready. The guard performs no IO.
@MainActor public struct ProfileUseTarget {
    public let controller:ProfileController
    public let bindingID:UUID
    let isCurrent:@MainActor ()->Bool
    public init(controller:ProfileController,bindingID:UUID,isCurrent:@escaping @MainActor ()->Bool){
        self.controller=controller;self.bindingID=bindingID;self.isCurrent=isCurrent
    }
}

/// Remembers explicit use, while every load remains bound to one actual helper
/// and Start. Its ready state is never native capture/publication authority.
@MainActor public final class SessionContextUseCoordinator:ObservableObject {
    private final class Flight {
        enum Mode:Equatable{case explicitOpen,restore(UUID),closing}
        let id=UUID(),generation:UUID,target:ProfileUseTarget,mode:Mode
        let isStartCurrent:@MainActor ()->Bool
        var retired=false
        var task:Task<SessionContextRestoreResult,Never>?
        var closeTask:Task<ProfileCloseOutcome,Never>?
        init(generation:UUID,target:ProfileUseTarget,mode:Mode,isStartCurrent:@escaping @MainActor ()->Bool){
            self.generation=generation;self.target=target;self.mode=mode;self.isStartCurrent=isStartCurrent
        }
    }
    @Published public private(set) var snapshot:SessionContextUseSnapshot
    public var useInSessions:Bool{enabled}
    public var isBusy:Bool{flight != nil}
    private let preferences:any SessionContextUsePreferences
    private let onInvalidate:@MainActor ()->Void
    private var enabled:Bool
    private var generation=UUID()
    private var flight:Flight?
    private var readyTarget:ProfileUseTarget?
    private var readyOperationID:UUID?
    private var publishing=false
    private var pendingSnapshot:SessionContextUseSnapshot?

    public init(preferences:any SessionContextUsePreferences,onInvalidate:@escaping @MainActor ()->Void){
        self.preferences=preferences;self.onInvalidate=onInvalidate;enabled=preferences.useInSessions
        snapshot=SessionContextUseSnapshot(useInSessions:enabled,status:enabled ? .idle:.off,isBusy:false,message:enabled ? "Saved context will load when you start.":"Saved context is locked for sessions.")
    }
    public convenience init(onInvalidate:@escaping @MainActor ()->Void){
        self.init(preferences:UserDefaultsSessionContextUsePreferences(),onInvalidate:onInvalidate)
    }
    public func openFromUserAction(target:ProfileUseTarget){
        guard flight==nil else{return}
        guard target.isCurrent(),!target.controller.busy else{publish(.unavailable);return}
        if let old=readyTarget,!same(old,target){retireForHelperChange();if flight != nil{return}}
        enabled=true;preferences.useInSessions=true;generation=UUID()
        _=beginLoad(target:target,mode:.explicitOpen,isStartCurrent:{true})
    }
    public func lockFromUserAction(target:ProfileUseTarget){
        let wasEnabled=enabled
        enabled=false;preferences.useInSessions=false;generation=UUID()
        if let flight{retire(flight);return}
        let owned=readyTarget ?? (target.isCurrent() ? target:nil)
        readyTarget=nil;readyOperationID=nil
        if let owned,owned.controller.opened || owned.controller.busy{beginClosing(target:owned)}
        else{if wasEnabled{onInvalidate()};publish(.off)}
    }
    public func retireForHelperChange(){
        generation=UUID()
        if let flight{retire(flight);return}
        if let target=readyTarget{
            readyTarget=nil;readyOperationID=nil
            if target.controller.opened || target.controller.busy{beginClosing(target:target);return}
        }
        publish(enabled ? .idle:.off)
    }
    public func restoreBeforeSession(target:ProfileUseTarget,startIntentID:UUID,
                                     isStartCurrent:@escaping @MainActor ()->Bool)async->SessionContextRestoreResult{
        guard !Task.isCancelled else{return .stale}
        // An opt-out cannot stand in for completion of an old close/load.
        if let owned=flight{
            guard target.isCurrent(),isStartCurrent() else{return .stale}
            guard !owned.retired,owned.mode == .restore(startIntentID),same(owned.target,target) else{return .busy}
            return await wait(owned,isCallerCurrent:{target.isCurrent() && isStartCurrent()})
        }
        guard enabled else{return .disabled}
        guard target.isCurrent(),isStartCurrent() else{return .stale}
        guard !target.controller.busy else{return .busy}
        if let old=readyTarget,!same(old,target){retireForHelperChange();if flight != nil{return .busy}}
        if target.controller.opened{
            let id=readyOperationID ?? UUID();readyTarget=target;readyOperationID=id
            publish(.ready)
            return admitted(target:target,operationID:id,isStartCurrent:isStartCurrent) ? .ready:.stale
        }
        let owned=beginLoad(target:target,mode:.restore(startIntentID),isStartCurrent:isStartCurrent)
        return await wait(owned,isCallerCurrent:{target.isCurrent() && isStartCurrent()})
    }
    public func waitForQuiescence()async{
        while let owned=flight{
            if let task=owned.task{_=await task.value}else{await Task.yield()}
        }
    }
    private func same(_ a:ProfileUseTarget,_ b:ProfileUseTarget)->Bool{a.bindingID==b.bindingID && a.controller === b.controller}
    private func current(_ owned:Flight)->Bool{
        flight === owned && !owned.retired && owned.generation==generation && enabled
            && owned.target.isCurrent() && owned.isStartCurrent()
    }
    private func beginLoad(target:ProfileUseTarget,mode:Flight.Mode,isStartCurrent:@escaping @MainActor ()->Bool)->Flight{
        let owned=Flight(generation:generation,target:target,mode:mode,isStartCurrent:isStartCurrent)
        flight=owned
        owned.task=Task{@MainActor [self] in
            var result=await load(owned)
            if result == .ready && !current(owned){result=await finishStale(owned)}
            finish(owned,result:result)
            return result
        }
        publish(mode == .explicitOpen ? .opening:.restoring)
        return owned
    }
    private func load(_ owned:Flight)async->SessionContextRestoreResult{
        guard current(owned),!Task.isCancelled else{return await finishStale(owned)}
        let outcome:ProfileOpenOutcome
        if owned.mode == .explicitOpen{
            await owned.target.controller.openProfile()
            outcome=owned.target.controller.opened ? .opened:.unavailable
        }else{outcome=await owned.target.controller.openExistingProfile()}
        guard current(owned),!Task.isCancelled else{return await finishStale(owned)}
        switch outcome{
        case .opened:readyTarget=owned.target;readyOperationID=owned.id;return .ready
        case .missing:return .missing
        case .unavailable:return .unavailable
        case .stale:return await finishStale(owned)
        }
    }
    private func wait(_ owned:Flight,isCallerCurrent:@MainActor ()->Bool)async->SessionContextRestoreResult{
        guard let task=owned.task else{return .busy}
        let id=owned.id
        let result=await withTaskCancellationHandler{await task.value}onCancel:{
            Task{@MainActor [weak self] in self?.retire(operationID:id)}
        }
        if result == .ready,(!isCallerCurrent() || !admitted(target:owned.target,operationID:id,isStartCurrent:owned.isStartCurrent)){return .stale}
        return result
    }
    private func admitted(target:ProfileUseTarget,operationID:UUID,isStartCurrent:@MainActor ()->Bool)->Bool{
        guard !Task.isCancelled,enabled,flight==nil,readyOperationID==operationID,
              let readyTarget,same(readyTarget,target),target.controller.opened else{return false}
        return target.isCurrent() && isStartCurrent()
    }
    private func retire(operationID:UUID){guard let flight,flight.id==operationID else{return};retire(flight)}
    private func retire(_ owned:Flight){
        guard flight === owned,!owned.retired else{return}
        owned.retired=true;readyTarget=nil;readyOperationID=nil
        onInvalidate()
        let controller=owned.target.controller
        if controller.opened || controller.busy{owned.closeTask=controller.beginClose()}
        owned.task?.cancel()
        publish(.closing)
    }
    private func beginClosing(target:ProfileUseTarget){
        let owned=Flight(generation:generation,target:target,mode:.closing,isStartCurrent:{true})
        flight=owned
        owned.task=Task{@MainActor [self] in
            _=await owned.closeTask?.value
            finish(owned,result:.stale)
            return .stale
        }
        retire(owned)
    }
    private func finishStale(_ owned:Flight)async->SessionContextRestoreResult{
        retire(owned)
        _=await owned.closeTask?.value
        return .stale
    }
    private func finish(_ owned:Flight,result:SessionContextRestoreResult){
        guard flight === owned else{return}
        flight=nil
        switch result{
        case .ready:publish(.ready)
        case .missing:publish(.missing)
        case .unavailable:publish(.unavailable)
        default:publish(enabled ? .idle:.off)
        }
    }
    private func publish(_ status:SessionContextUseStatus){
        let message:String
        switch status{
        case .off:message="Saved context is locked for sessions."
        case .idle:message="Saved context will load when you start."
        case .opening:message="Opening My Context…"
        case .restoring:message="Loading saved context for this session…"
        case .ready:message="Your saved context is ready."
        case .closing:message="Finishing saved context work…"
        case .missing:message="Saved context was not found. Open My Context, or lock it and retry."
        case .unavailable:message="Saved context is unavailable. Open My Context, or lock it and retry."
        }
        pendingSnapshot=SessionContextUseSnapshot(useInSessions:enabled,status:status,isBusy:isBusy,message:message)
        guard !publishing else{return}
        publishing=true
        // Synchronous observers may invoke Lock. Drain that newer state after
        // the current @Published willSet returns instead of overwriting it.
        while let next=pendingSnapshot{pendingSnapshot=nil;snapshot=next}
        publishing=false
    }
}
