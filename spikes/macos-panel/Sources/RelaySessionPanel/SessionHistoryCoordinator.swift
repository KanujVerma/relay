import Combine
import Foundation
import RelayProfile

public enum HistoryWorkspacePhase:Sendable,Equatable{case locked,opening,ready,closing,unavailable}
public struct HistoryWorkspaceSnapshot:Sendable,Equatable {
    public internal(set) var epoch=UUID()
    public internal(set) var phase:HistoryWorkspacePhase = .locked
    public internal(set) var savingEnabled=false
    public internal(set) var isBusy=false
    public internal(set) var pendingCount=0
    public internal(set) var message="History is locked. Saving is off by default."
    public internal(set) var records:[HistoryRecord]=[]
    public internal(set) var selected:HistoryDetail?
    public internal(set) var nextOffset:Int?
    public internal(set) var recordingID:UUID?
}
private final class HistoryAdmission:@unchecked Sendable {
    private let lock=NSLock();private var current=true
    var allowed:Bool{lock.withLock{current}}
    func retire(){lock.withLock{current=false}}
}
/// Issued only by this coordinator, never reconstructed from helper JSON or a
/// history record. Native capture identities are bound by issued observations.
@MainActor public final class HistorySessionPermit {
    public let id=UUID(),recordID:UUID,intentID:UUID
    fileprivate let gate=HistoryAdmission()
    fileprivate var preparing=true,acceptsNew=false,paused=false,captureSeen=false,failed=false
    fileprivate var captureID:String?
    fileprivate var blocked:Set<TranscriptSource>=[]
    fileprivate var finishGap:HistoryGap?
    fileprivate let resuming:Bool
    fileprivate init(recordID:UUID,intentID:UUID,resuming:Bool){self.recordID=recordID;self.intentID=intentID;self.resuming=resuming}
}

/// Optional native storage owner. Observation callbacks only enqueue bounded
/// memory; all SQLite/key/file work runs off the UI actor. Cancellation fences
/// before await and joins the original actual task, including native writes.
@MainActor public final class SessionHistoryCoordinator:ObservableObject {
    @Published public private(set) var snapshot=HistoryWorkspaceSnapshot()
    private var state=HistoryWorkspaceSnapshot()
    private let factory:@Sendable ()throws->any ProtectedSnapshotStorage
    private let preferences:any HistorySavingPreferences
    private let canEnable:@MainActor ()->Bool
    private let clock:@Sendable ()->Date
    private var store:HistoryStore?
    private var epoch=UUID(),selectionEpoch=UUID(),visibilityEpoch=UUID()
    private var opened=false
    private var current:HistorySessionPermit?
    private var pending:[ValidatedTranscriptObservation]=[]
    private var pendingBytes=0
    private var terminalGap:HistoryGap?
    private var tombstones:Set<UUID>=[]
    private struct Flight {let id:UUID;let gate:HistoryAdmission;let join:Task<Void,Never>}
    private var flight:Flight?
    private var writer:Task<Void,Never>?,writerID:UUID?
    private var retirement:Task<Void,Never>?,retirementID:UUID?
    private var exclusive:Task<Void,Error>?,exclusiveID:UUID?
    private var exportTask:Task<Void,Error>?,exportID:UUID?,exportGate:HistoryAdmission?
    private var pauseWriter=false
    private var closeRequested=false
    public var isBusy:Bool{flight != nil || writer != nil || retirement != nil || exclusive != nil || exportTask != nil}
    public var savingEnabled:Bool{preferences.savingEnabled}
    public init(storageFactory:@escaping @Sendable ()throws->any ProtectedSnapshotStorage,
                preferences:any HistorySavingPreferences,canEnable:@escaping @MainActor ()->Bool,
                clock:@escaping @Sendable ()->Date={Date()}){
        factory=storageFactory;self.preferences=preferences;self.canEnable=canEnable;self.clock=clock
        state.epoch=epoch;state.savingEnabled=preferences.savingEnabled;snapshot=state
    }
    private func publish(){
        state.epoch=epoch;state.isBusy=isBusy;state.pendingCount=pending.count;state.savingEnabled=preferences.savingEnabled
        let original=epoch;snapshot=state
        // @Published observers may synchronously Lock. Never leave their
        // cleared private state overwritten by the older completion's setter.
        if epoch != original{state.epoch=epoch;state.isBusy=isBusy;state.pendingCount=pending.count;snapshot=state}
    }
    private func ownedStore()throws->HistoryStore{
        if let store{return store}
        let value=HistoryStore(storage:try factory(),clock:clock);store=value;return value
    }
    private func run<T:Sendable>(gate:HistoryAdmission,_ body:@escaping @Sendable (HistoryStore)throws->T)async throws->T{
        guard flight==nil,gate.allowed else{throw HistoryError.stale}
        let store=try ownedStore(),id=UUID()
        let actual=Task.detached(priority:.utility){guard gate.allowed else{throw HistoryError.stale};return try body(store)}
        let joined=Task.detached{_=await actual.result}
        flight=Flight(id:id,gate:gate,join:joined);publish()
        let result=await actual.result;await joined.value
        if flight?.id==id{flight=nil};publish()
        startWriter()
        return try result.get()
    }
    private func join(_ original:Flight?)async{
        guard let original else{return};await original.join.value
        while flight?.id==original.id{await Task.yield()}
    }
    private func refreshRecords()async{
        guard store != nil,state.phase != .closing else{return}
        let original=epoch,visibility=visibilityEpoch,gate=HistoryAdmission()
        do{
            let page=try await run(gate:gate){try $0.list()}
            guard original==epoch,visibility==visibilityEpoch,state.phase != .closing else{return}
            state.records=page.records.filter{!tombstones.contains($0.id)};state.nextOffset=page.nextOffset;publish()
        }catch{}
    }
    private func fail(_ error:any Error){
        current?.acceptsNew=false;current?.failed=true;current?.gate.retire();pending=[];pendingBytes=0
        state.phase = .unavailable;state.records=[];state.selected=nil
        if case HistoryError.capacity=error{state.message="History is full. Delete saved sessions or turn saving off."}
        else if case HistoryError.inUse=error{state.message="Local history is in use. Close or lock another Relay app, then retry, or turn saving off here."}
        else if case HistoryError.missing=error{state.message="Saved history is missing. Enable saving explicitly, or turn it off before starting."}
        else{state.message="History is unavailable. Open it to retry, or turn saving off before starting."}
        publish()
    }
    public func enableSaving()async throws{
        try Task.checkCancellation()
        guard !isBusy,canEnable(),current==nil else{throw HistoryError.stale}
        epoch=UUID();let original=epoch,gate=HistoryAdmission();state.selected=nil;state.phase = .opening;state.message="Opening local history…";publish()
        do{
            let page=try await withTaskCancellationHandler(operation:{try await run(gate:gate){store in try store.open(create:true,admission:{gate.allowed});return try store.list()}},onCancel:{gate.retire()})
            guard epoch==original,gate.allowed,!isBusy,canEnable(),!Task.isCancelled else{throw HistoryError.stale}
            opened=true
            preferences.savingEnabled=true;state.phase = .ready;state.records=page.records;state.nextOffset=page.nextOffset
            state.message="Session text and notes are kept locally for 30 days. No audio or screenshots.";publish()
            guard epoch==original,preferences.savingEnabled else{throw HistoryError.stale}
        }catch{if epoch==original{fail(error)};throw error}
    }
    public func openExisting()async throws{
        try Task.checkCancellation()
        guard !isBusy else{throw HistoryError.stale}
        if current != nil{guard state.phase == .ready else{throw HistoryError.unavailable};return}
        epoch=UUID();let original=epoch,gate=HistoryAdmission();state.selected=nil;state.phase = .opening;state.message="Opening saved history…";publish()
        do{
            let page=try await withTaskCancellationHandler(operation:{try await run(gate:gate){store in try store.open(create:false,admission:{gate.allowed});return try store.list()}},onCancel:{gate.retire()})
            guard original==epoch,gate.allowed,!isBusy,!Task.isCancelled else{throw HistoryError.stale}
            opened=true;tombstones=[]
            state.phase = .ready;state.records=page.records;state.nextOffset=page.nextOffset;state.message="Saved locally. Expired items are removed when History opens.";publish()
            guard epoch==original,gate.allowed else{throw HistoryError.stale}
        }catch{if original==epoch{fail(error)};throw error}
    }
    public func beginSession(intentID:UUID,resuming:Bool,isCurrent:@escaping @MainActor ()->Bool)async throws->HistorySessionPermit?{
        try Task.checkCancellation()
        guard !isBusy,isCurrent() else{throw HistoryError.stale}
        guard preferences.savingEnabled else{return nil}
        if resuming{guard let current,current.paused,!current.failed else{throw HistoryError.unavailable}}
        let original=epoch,old=current
        let permit=HistorySessionPermit(recordID:resuming ? old!.recordID:UUID(),intentID:intentID,resuming:resuming)
        old?.gate.retire();current=permit;state.phase = .opening;publish()
        let gate=permit.gate,id=permit.recordID
        do{
            let result=try await withTaskCancellationHandler(operation:{
                try await run(gate:gate){store in
                    try store.open(create:false,admission:{gate.allowed})
                    if resuming{try store.finish(id,outcome:.recording,admission:{gate.allowed})}
                    else{_=try store.createRecord(id:id,admission:{gate.allowed})}
                    return(try store.detail(id).record,try store.list())
                }
            },onCancel:{gate.retire()})
            guard epoch==original,current === permit,gate.allowed,preferences.savingEnabled,isCurrent(),!isBusy,!Task.isCancelled else{throw HistoryError.stale}
            opened=true
            permit.preparing=false;permit.acceptsNew=true
            permit.blocked=Set(result.0.blockedSources);let page=result.1
            state.phase = .ready;state.records=page.records;state.nextOffset=page.nextOffset;state.recordingID=id;state.message="Saving session text locally";publish()
            guard owns(permit),!isBusy,isCurrent(),!Task.isCancelled else{throw HistoryError.stale}
            return permit
        }catch{
            permit.acceptsNew=false;gate.retire()
            if epoch==original,retirement==nil,current === permit{
                await clean(permit,gap:nil);current=nil;state.recordingID=nil;await refreshRecords()
                if case HistoryError.stale=error{state.phase = opened ? .ready:.unavailable;state.message="History start cancelled.";publish()}
                else if error is CancellationError{state.phase = opened ? .ready:.unavailable;state.message="History start cancelled.";publish()}
                else{fail(error)}
            }
            throw error
        }
    }
    public func owns(_ permit:HistorySessionPermit)->Bool{current === permit && permit.gate.allowed && !permit.failed && !tombstones.contains(permit.recordID)}
    public func observe(_ observation:ValidatedTranscriptObservation){
        guard let permit=current,!permit.preparing,permit.acceptsNew,owns(permit) else{return}
        let event=observation.event
        if event.kind == .sessionStarted{
            guard permit.captureID==nil else{return}
            permit.captureID=HistoryCapture.identity(event.captureSessionID,event.sessionEpoch);permit.captureSeen=true
        }else{
            guard permit.captureID==HistoryCapture.identity(event.captureSessionID,event.sessionEpoch) else{return}
            if let final=observation.final,permit.blocked.contains(final.source){return}
            guard observation.final != nil || observation.sequenceGap || [.sourceUnavailable,.discontinuity].contains(event.kind) else{return}
        }
        let size=(observation.final?.originalEventJSON.count ?? 1024)+(observation.final?.text.utf8.count ?? 0)+512
        guard pending.count<HistoryBounds.pending,pendingBytes+size<=HistoryBounds.pendingBytes else{
            permit.acceptsNew=false;terminalGap = .capacity;state.message="History reached its limit. This session's saved text is partial.";publish();startWriter();return
        }
        visibilityEpoch=UUID()
        pending.append(observation);pendingBytes+=size;publish();startWriter()
    }
    private func startWriter(){
        guard writer==nil,flight==nil,retirement==nil,!pauseWriter,!pending.isEmpty,let permit=current,permit.gate.allowed else{return}
        let id=UUID();writerID=id
        writer=Task{[weak self,permit] in
            guard let self else{return}
            while !self.pauseWriter,self.retirement==nil,self.current === permit,permit.gate.allowed,!self.pending.isEmpty{
                let observation=self.pending.removeFirst()
                self.pendingBytes=max(0,self.pendingBytes-((observation.final?.originalEventJSON.count ?? 1024)+(observation.final?.text.utf8.count ?? 0)+512))
                let gate=permit.gate,recordID=permit.recordID
                do{
                    try await self.run(gate:gate){store in try store.append(observation,to:recordID,admission:{gate.allowed})}
                }catch{
                    if !gate.allowed || self.retirement != nil || self.tombstones.contains(recordID){break}
                    self.terminalGap=(error as? HistoryError).map{if case .capacity=$0{return .capacity};return .storageFailure} ?? .storageFailure
                    permit.acceptsNew=false;self.pending=[];self.pendingBytes=0;break
                }
            }
            if self.writerID==id{self.writer=nil;self.writerID=nil}
            if self.retirement==nil,!self.pauseWriter,self.current === permit,let gap=self.terminalGap{
                self.terminalGap=nil
                do{
                    let gate=permit.gate,recordID=permit.recordID
                    try await self.run(gate:gate){try $0.finish(recordID,outcome:.partial,gap:gap,admission:{gate.allowed})}
                    permit.acceptsNew=false;permit.failed=true;gate.retire();self.state.recordingID=nil
                    self.state.message=gap == .capacity ? "History reached its limit. Saved text is partial.":"History could not save more text. The saved prefix is partial."
                }catch{self.fail(error)}
            }
            if self.retirement==nil,!self.pauseWriter{await self.refreshRecords()}
            self.publish()
        }
        publish()
    }
    @discardableResult public func retireCurrentSession(gap:HistoryGap?=nil)->HistorySessionPermit?{
        guard let permit=current else{return nil};permit.acceptsNew=false
        if let gap{permit.finishGap=gap}
        if permit.preparing{permit.gate.retire()};publish();return permit
    }
    public func finishSession(_ permit:HistorySessionPermit,paused:Bool)async throws{
        permit.acceptsNew=false
        await waitForQuiescence()
        guard current === permit,retirement==nil,!tombstones.contains(permit.recordID) else{return}
        if permit.preparing || !permit.captureSeen{
            await clean(permit,gap:nil);if current === permit{current=nil};state.recordingID=nil;publish();return
        }
        guard permit.gate.allowed,!permit.failed else{return}
        if permit.paused && paused{return}
        let gate=permit.gate,id=permit.recordID
        do{
            let gap=permit.finishGap
            let page=try await run(gate:gate){store in try store.finish(id,outcome:paused ? .paused:.completed,gap:gap,admission:{gate.allowed});return try store.list()}
            guard current === permit,gate.allowed else{return}
            permit.paused=paused;state.records=page.records;state.nextOffset=page.nextOffset
            if !paused{current=nil;gate.retire();state.recordingID=nil}
            state.message=paused ? "History paused. Resume uses a fresh audio segment.":"Session history saved locally.";publish()
        }catch{fail(error);throw error}
    }
    private func clean(_ permit:HistorySessionPermit,gap:HistoryGap?)async{
        guard store != nil else{return}
        let id=permit.recordID,hadCapture=permit.captureSeen,resuming=permit.resuming,gate=HistoryAdmission()
        do{try await run(gate:gate){store in
            let detail:HistoryDetail
            do{detail=try store.detail(id)}catch HistoryError.missing{return}
            if [.completed,.partial,.interrupted].contains(detail.record.state){return}
            if !hadCapture && !resuming && detail.captures.isEmpty{try store.delete(id,expectedRevision:detail.record.revision)}
            else if let gap{try store.finish(id,outcome:.partial,gap:gap)}
        }}catch{state.message="History cleanup did not finish. Open History to recover the saved prefix."}
    }
    public func stopSaving(){beginClose(lock:false,preservePreference:false)}
    public func lock(){beginClose(lock:true,preservePreference:false)}
    private func beginClose(lock:Bool,preservePreference:Bool){
        if !preservePreference{preferences.savingEnabled=false}
        // Snapshot observers may repeat either action while its original owner
        // publishes. Only a new Lock escalation or preference change publishes.
        if retirement != nil,(!lock || closeRequested),state.savingEnabled==preferences.savingEnabled{return}
        if lock{closeRequested=true;epoch=UUID();selectionEpoch=UUID();state.records=[];state.selected=nil;state.phase = .closing;state.message="Closing history…"}
        let permit=current;permit?.acceptsNew=false;permit?.gate.retire();flight?.gate.retire()
        pending=[];pendingBytes=0;terminalGap=nil;pauseWriter=true
        guard retirement==nil else{publish();return}
        exportGate?.retire()
        let oldWriter=writer,oldFlight=flight,oldExclusive=exclusive,oldExport=exportTask,id=UUID()
        retirementID=id
        retirement=Task{[weak self] in
            guard let self else{return}
            await oldWriter?.value;await self.join(oldFlight);_=await oldExclusive?.result;_=await oldExport?.result
            if let permit,!self.tombstones.contains(permit.recordID){await self.clean(permit,gap:.savingStopped)}
            if !self.closeRequested{await self.refreshRecords()}
            let shouldClose=self.closeRequested
            if shouldClose,let store=self.store{
                var closed=false
                while !closed{
                    do{try await self.run(gate:HistoryAdmission()){try $0.close()};closed=true}
                    catch{self.state.message="History is still closing. Its old storage is unavailable.";self.publish();try? await Task.sleep(for:.milliseconds(100))}
                }
                _=store;self.store=nil;self.opened=false
            }
            if self.current === permit{self.current=nil};self.state.recordingID=nil
            if self.retirementID==id{self.retirement=nil;self.retirementID=nil;self.closeRequested=false}
            self.pauseWriter=false
            if shouldClose{self.state.phase = .locked;self.state.message="History locked. Saved encrypted data remains on this Mac."}
            else{self.state.phase = self.opened ? .ready:.unavailable;self.state.message="Saving is off. Open History to view previously saved sessions."}
            self.publish()
        }
        publish()
    }
    public func closeForOwnerRetirement()async{
        beginClose(lock:true,preservePreference:true);await waitForQuiescence()
    }
    public func waitForQuiescence()async{
        while true{
            if let retirement{await retirement.value;continue}
            if let exclusive{_=await exclusive.result;continue}
            if let exportTask{_=await exportTask.result;continue}
            if let writer{await writer.value;continue}
            if let flight{await flight.join.value;await Task.yield();continue}
            return
        }
    }
    public func openRecord(_ id:UUID,offset:Int=0)async throws{
        try Task.checkCancellation()
        guard !isBusy,state.phase == .ready,!tombstones.contains(id) else{throw HistoryError.stale}
        selectionEpoch=UUID();let selected=selectionEpoch,original=epoch,gate=HistoryAdmission()
        state.selected=nil;publish()
        let detail=try await withTaskCancellationHandler(operation:{try await run(gate:gate){try $0.detail(id,offset:offset)}},onCancel:{gate.retire()})
        guard epoch==original,selectionEpoch==selected,gate.allowed,!Task.isCancelled,!tombstones.contains(id) else{throw HistoryError.stale}
        state.selected=detail;publish()
    }
    public func loadMoreRecords()async throws{
        try Task.checkCancellation()
        guard !isBusy,state.phase == .ready,let offset=state.nextOffset else{throw HistoryError.stale}
        let original=epoch,visibility=visibilityEpoch,gate=HistoryAdmission()
        let page=try await withTaskCancellationHandler(operation:{try await run(gate:gate){try $0.list(offset:offset)}},onCancel:{gate.retire()})
        guard epoch==original,visibilityEpoch==visibility,gate.allowed,!Task.isCancelled else{throw HistoryError.stale}
        let known=Set(state.records.map(\.id));state.records+=page.records.filter{!known.contains($0.id) && !tombstones.contains($0.id)}
        state.nextOffset=page.nextOffset;publish()
    }
    public func loadMoreTranscript()async throws{
        try Task.checkCancellation()
        guard !isBusy,state.phase == .ready,let before=state.selected,let offset=before.nextOffset else{throw HistoryError.stale}
        let original=epoch,selected=selectionEpoch,gate=HistoryAdmission(),id=before.record.id
        let page=try await withTaskCancellationHandler(operation:{try await run(gate:gate){try $0.detail(id,offset:offset)}},onCancel:{gate.retire()})
        guard epoch==original,selectionEpoch==selected,gate.allowed,!Task.isCancelled,page.record.revision==before.record.revision,!tombstones.contains(id) else{throw HistoryError.stale}
        state.selected=HistoryDetail(record:page.record,captures:page.captures,rows:before.rows+page.rows,nextOffset:page.nextOffset,totalRows:page.totalRows);publish()
    }
    public func saveNotes(_ id:UUID,expectedRevision:Int64,title:String,note:String)async throws{
        try Task.checkCancellation()
        guard !isBusy,state.phase == .ready,!tombstones.contains(id),state.selected?.record.id==id else{throw HistoryError.stale}
        let original=epoch,selected=selectionEpoch,gate=HistoryAdmission()
        let result=try await withTaskCancellationHandler(operation:{try await run(gate:gate){store in
            _=try store.edit(id,expectedRevision:expectedRevision,title:title,note:note,admission:{gate.allowed})
            return(try store.detail(id),try store.list())
        }},onCancel:{gate.retire()})
        guard epoch==original,selectionEpoch==selected,gate.allowed,!Task.isCancelled,!tombstones.contains(id) else{throw HistoryError.stale}
        state.selected=result.0;state.records=result.1.records;state.nextOffset=result.1.nextOffset
        state.message="Your notes were saved locally. They are not approved personal facts.";publish()
    }
    public func export(_ id:UUID,expectedRevision:Int64,format:HistoryExportFormat,to destination:any HistoryExportDestination)->Task<Void,Error>{
        guard !isBusy,state.phase == .ready,state.selected?.record.id==id,!tombstones.contains(id) else{return Task{throw HistoryError.stale}}
        let original=epoch,selected=selectionEpoch,operationID=UUID(),gate=HistoryAdmission()
        exportID=operationID;exportGate=gate;pauseWriter=true
        let task=Task{[weak self] in
            guard let self else{throw HistoryError.closed}
            do{
                let data=try await self.run(gate:gate){store in
                    let detail=try store.detail(id,all:true)
                    guard detail.record.revision==expectedRevision else{throw HistoryError.stale}
                    return try HistoryExport.encode(detail,format:format)
                }
                guard self.epoch==original,self.selectionEpoch==selected,gate.allowed,!self.tombstones.contains(id) else{throw HistoryError.stale}
                try await self.run(gate:gate){_ in guard gate.allowed else{throw HistoryError.stale};try destination.write(data)}
                guard self.epoch==original,gate.allowed else{throw HistoryError.stale}
                self.state.message="Export saved. This copy is outside Relay's local history retention."
            }catch{
                if self.epoch==original,gate.allowed{self.state.message="Export did not finish. Your saved history is unchanged."}
                self.endExport(operationID);throw error
            }
            self.endExport(operationID)
        }
        exportTask=task;publish();return task
    }
    private func endExport(_ id:UUID){
        if exportID==id{exportTask=nil;exportID=nil;exportGate=nil}
        if exclusive==nil,retirement==nil{pauseWriter=false};publish();startWriter()
    }
    /// Prefix is synchronous: hide/tombstone and fence matching queued writes
    /// before the caller awaits the actual deletion receipt.
    public func delete(_ id:UUID,expectedRevision:Int64)->Task<Void,Error>{
        guard retirement==nil,exclusive==nil,state.phase == .ready else{return Task{throw HistoryError.stale}}
        exportGate?.retire()
        tombstones.insert(id);selectionEpoch=UUID();visibilityEpoch=UUID();state.records.removeAll{$0.id==id}
        if state.selected?.record.id==id{state.selected=nil}
        if current?.recordID==id{current?.acceptsNew=false;current?.gate.retire();pending=[];pendingBytes=0}
        pauseWriter=true
        let oldWriter=writer,oldFlight=flight,oldExport=exportTask,original=epoch,operationID=UUID(),gate=HistoryAdmission()
        exclusiveID=operationID
        let task=Task{[weak self] in
            guard let self else{throw HistoryError.closed}
            await oldWriter?.value;await self.join(oldFlight);_=await oldExport?.result
            do{
                let page=try await self.run(gate:gate){store in
                    let current=try store.detail(id).record
                    guard current.revision>=expectedRevision else{throw HistoryError.stale}
                    try store.delete(id,expectedRevision:current.revision,admission:{gate.allowed});return try store.list()
                }
                guard self.epoch==original,gate.allowed else{throw HistoryError.stale}
                self.state.records=page.records;self.state.nextOffset=page.nextOffset
                self.tombstones.remove(id)
                if self.current?.recordID==id{self.current=nil;self.state.recordingID=nil}
                self.state.message="Session deleted from local history. Exported copies are unchanged."
            }catch{
                if self.epoch==original{self.state.phase = .unavailable;self.state.message="Deletion did not finish. Open History to retry."}
                if self.exclusiveID==operationID{self.exclusive=nil;self.exclusiveID=nil};self.pauseWriter=false;self.publish();throw error
            }
            if self.exclusiveID==operationID{self.exclusive=nil;self.exclusiveID=nil};self.pauseWriter=false;self.publish();self.startWriter()
        }
        exclusive=task;publish();return task
    }
    /// Delete one recorded capture/source and block future saved text from that
    /// logical source for this record. Other sources and user notes remain.
    public func deleteSource(_ id:UUID,expectedRevision:Int64,captureID:String,source:TranscriptSource)->Task<Void,Error>{
        guard retirement==nil,exclusive==nil,state.phase == .ready,!tombstones.contains(id) else{return Task{throw HistoryError.stale}}
        exportGate?.retire();selectionEpoch=UUID();visibilityEpoch=UUID();state.selected=nil
        if current?.recordID==id{
            current?.blocked.insert(source)
            pending.removeAll{$0.final?.source==source};pendingBytes=pending.reduce(0){$0+($1.final?.originalEventJSON.count ?? 1024)+($1.final?.text.utf8.count ?? 0)+512}
        }
        pauseWriter=true
        let oldWriter=writer,oldFlight=flight,oldExport=exportTask,original=epoch,operationID=UUID(),gate=HistoryAdmission()
        exclusiveID=operationID
        let task=Task{[weak self] in
            guard let self else{throw HistoryError.closed}
            await oldWriter?.value;await self.join(oldFlight);_=await oldExport?.result
            do{
                let result=try await self.run(gate:gate){store in
                    let record=try store.detail(id).record;guard record.revision>=expectedRevision else{throw HistoryError.stale}
                    try store.deleteSource(id,expectedRevision:record.revision,captureID:captureID,source:source,admission:{gate.allowed})
                    return(try store.detail(id),try store.list())
                }
                guard self.epoch==original,gate.allowed else{throw HistoryError.stale}
                self.state.selected=result.0;self.state.records=result.1.records;self.state.nextOffset=result.1.nextOffset
                self.state.message="Source text deleted. Other sources and your notes remain. Exported copies are unchanged."
            }catch{
                if self.epoch==original{self.state.phase = .unavailable;self.state.message="Source deletion did not finish. Open History to retry."}
                self.endExclusive(operationID);throw error
            }
            self.endExclusive(operationID)
        }
        exclusive=task;publish();return task
    }
    public func deleteAll()->Task<Void,Error>{
        guard retirement==nil,exclusive==nil,state.phase == .ready else{return Task{throw HistoryError.stale}}
        preferences.savingEnabled=false;exportGate?.retire();epoch=UUID();selectionEpoch=UUID();visibilityEpoch=UUID()
        state.records=[];state.selected=nil;state.nextOffset=nil
        current?.acceptsNew=false;current?.gate.retire();pending=[];pendingBytes=0;terminalGap=nil;pauseWriter=true
        let oldWriter=writer,oldFlight=flight,oldExport=exportTask,original=epoch,operationID=UUID(),gate=HistoryAdmission()
        exclusiveID=operationID
        let task=Task{[weak self] in
            guard let self else{throw HistoryError.closed}
            await oldWriter?.value;await self.join(oldFlight);_=await oldExport?.result
            do{
                try await self.run(gate:gate){try $0.deleteAll(admission:{gate.allowed})}
                guard self.epoch==original,gate.allowed else{throw HistoryError.stale}
                self.current=nil;self.state.recordingID=nil;self.tombstones=[]
                self.state.message="All local history deleted. Saving is off. Exported copies are unchanged."
            }catch{
                if self.epoch==original{self.state.phase = .unavailable;self.state.message="Deletion did not finish. Open History to retry."}
                self.endExclusive(operationID);throw error
            }
            self.endExclusive(operationID)
        }
        exclusive=task;publish();return task
    }
    private func endExclusive(_ id:UUID){
        if exclusiveID==id{exclusive=nil;exclusiveID=nil}
        if retirement==nil,exportTask==nil{pauseWriter=false};publish();startWriter()
    }
}
