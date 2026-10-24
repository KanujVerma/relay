import Combine
import Foundation

public enum ResponsePreferencesStage:Sendable,Equatable{case general,loading,saving,ready,cancelling,cancelled,unavailable}
public struct ResponsePreferencesState:Sendable,Equatable {
    public let stage:ResponsePreferencesStage,guideName:String,isBusy:Bool,message:String
    public init(stage:ResponsePreferencesStage = .general,guideName:String="General",isBusy:Bool=false,message:String="General follows the current question automatically."){
        self.stage=stage;self.guideName=guideName;self.isBusy=isBusy;self.message=message
    }
}

/// Catalog readiness is presentation data only. Original native requests and
/// the existing conversation owner remain the sole publication authority.
@MainActor public final class ResponsePreferencesCoordinator:ObservableObject {
    private final class Flight {
        let id=UUID(),intentID:UUID?
        let isCurrent:@MainActor ()->Bool
        var retired=false
        var task:Task<Void,any Error>?
        init(intentID:UUID?,isCurrent:@escaping @MainActor ()->Bool){self.intentID=intentID;self.isCurrent=isCurrent}
    }
    @Published public private(set) var snapshot=ResponsePreferencesState()
    public private(set) var catalog:ResponsePreferencesCatalog?
    private let storage:any ProtectedSnapshotStorage
    private let receipts:any ResponsePreferencesReceiptStore
    private let onRetire:@MainActor (ResponsePreferenceSnapshot)->Void
    private var activation:ResponsePreferenceSnapshot?
    private var selected="general",catalogExists=false
    private var flight:Flight?
    private var publishing=false,pending:ResponsePreferencesState?
    public var isBusy:Bool{flight != nil}
    public init(storage:any ProtectedSnapshotStorage,receipts:any ResponsePreferencesReceiptStore,
                onRetire:@escaping @MainActor (ResponsePreferenceSnapshot)->Void={_ in}){
        self.storage=storage;self.receipts=receipts;self.onRetire=onRetire
    }
    public convenience init(onRetire:@escaping @MainActor (ResponsePreferenceSnapshot)->Void={_ in}){
        self.init(storage:DefaultResponsePreferencesStorage(),receipts:UserDefaultsResponsePreferencesReceipts(),onRetire:onRetire)
    }
    public func capture()->ResponsePreferenceSnapshot?{activation}
    public func owns(_ original:ResponsePreferenceSnapshot)->Bool{activation === original}
    private func publish(_ stage:ResponsePreferencesStage,message:String){
        pending=ResponsePreferencesState(stage:stage,guideName:activation?.displayName ?? "General",isBusy:isBusy,message:message)
        guard !publishing else{return};publishing=true;defer{publishing=false}
        while let next=pending{pending=nil;snapshot=next}
    }
    private func checkCurrent()throws{
        guard let flight,!flight.retired,flight.isCurrent(),!Task.isCancelled else{throw CancellationError()}
    }
    private func activate(_ value:ResponsePreferencesCatalog,record:Bool)throws{
        let candidate=value.activation()
        if let old=activation,let candidate,old.sameGuide(as:candidate){}else{
            let old=activation;activation=nil
            if let old{onRetire(old)}
            try checkCurrent()
            activation=candidate
        }
        try checkCurrent()
        catalog=value;catalogExists=true;selected=value.selected
        if record{receipts.commit(value.revision)}
    }
    public func useGeneral(){
        // Retire before any published state/receipt callback can release held
        // question/context work. The app callback synchronously enqueues the
        // original retirement before performing its own optional cleanup.
        if let flight{flight.retired=true;flight.task?.cancel()}
        selected="general";let old=activation;activation=nil
        if let old{onRetire(old)}
        receipts.disable()
        publish(isBusy ? .cancelling:.general,message:isBusy ? "General is selected. Finishing the previous preference operation…":"General follows the current question automatically.")
    }
    public func cancel(){if let flight{cancelOperation(flight.id)}}
    public func cancel(intentID:UUID){guard let flight,flight.intentID==intentID else{return};cancelOperation(flight.id)}
    private func cancelOperation(_ id:UUID){
        guard let flight,flight.id==id,!flight.retired else{return}
        flight.retired=true;flight.task?.cancel()
        publish(.cancelling,message:"Finishing the cancelled preference operation…")
    }
    public func waitForQuiescence()async{
        while let owned=flight{_ = await owned.task?.result;await Task.yield()}
    }
    private func wait(_ owned:Flight)async throws{
        let id=owned.id
        try await withTaskCancellationHandler{try await owned.task?.value}onCancel:{Task{@MainActor [weak self] in self?.cancelOperation(id)}}
        try Task.checkCancellation()
    }
    private func perform(intentID:UUID?=nil,isCurrent:@escaping @MainActor ()->Bool={true},stage:ResponsePreferencesStage,
                         work:@escaping @Sendable ()throws->ResponsePreferencesCatalog?,
                         apply:@escaping @MainActor (ResponsePreferencesCatalog?)throws->Void)async throws{
        try Task.checkCancellation();guard flight==nil else{throw ResponsePreferencesError.busy}
        guard isCurrent() else{throw CancellationError()}
        let owned=Flight(intentID:intentID,isCurrent:isCurrent);flight=owned
        owned.task=Task{[self,owned] in
            do{
                try checkCurrent()
                // This unstructured synchronous call has an actual receipt even
                // if the surrounding actor task is cancelled while it is held.
                let result=try await Task.detached(priority:.userInitiated,operation:work).value
                try checkCurrent();try apply(result);try checkCurrent()
                if flight === owned{
                    flight=nil
                    publish(activation==nil ? .general:.ready,message:activation==nil ? "General follows the current question automatically.":"New questions use this response guide.")
                }
            }catch{
                let failure:any Error = error is CancellationError ? CancellationError():(error as? ResponsePreferencesError ?? .unavailable)
                if flight === owned{
                    flight=nil
                    publish(error is CancellationError ? .cancelled:.unavailable,message:error is CancellationError ? "Preference operation cancelled.":(failure as? LocalizedError)?.errorDescription ?? "Response preferences are unavailable.")
                }
                throw failure
            }
        }
        publish(stage,message:stage == .saving ? "Saving response guide…":"Opening response guides…")
        try await wait(owned)
    }
    public func open()async throws{
        guard flight==nil else{throw ResponsePreferencesError.busy}
        let receipt=receipts.read(),store=storage
        try await perform(stage:.loading,work:{try store.exists() ? ResponsePreferencesCatalog.decode(store.load()):nil},apply:{[self] value in
            guard receipts.read()==receipt else{throw CancellationError()}
            if receipt.enabled{
                guard let value else{throw ResponsePreferencesError.missing}
                guard value.revision==receipt.revision else{throw ResponsePreferencesError.receiptMismatch}
                try activate(value,record:false)
            }else{
                let value=value ?? .empty()
                try activate(try ResponsePreferencesCatalog(revision:value.revision,selected:"general",guides:value.guides),record:false)
            }
            catalogExists=value != nil
        })
    }
    public func prepareForExplicitAction(intentID:UUID,isCurrent:@escaping @MainActor ()->Bool)async throws{
        try Task.checkCancellation();guard isCurrent() else{throw CancellationError()}
        if let flight{
            guard flight.intentID==intentID,!flight.retired else{throw ResponsePreferencesError.busy}
            try await wait(flight);return
        }
        let receipt=receipts.read()
        guard receipt.enabled else{
            selected="general";let old=activation;activation=nil
            if let old{onRetire(old)}
            publish(.general,message:"General follows the current question automatically.");return
        }
        guard receipt.revision != nil else{throw ResponsePreferencesError.receiptMismatch}
        if let catalog,catalogExists,catalog.revision==receipt.revision,selected==catalog.selected{return}
        let store=storage
        try await perform(intentID:intentID,isCurrent:isCurrent,stage:.loading,work:{try store.exists() ? ResponsePreferencesCatalog.decode(store.load()):nil},apply:{[self] value in
            guard receipts.read()==receipt else{throw CancellationError()}
            guard let value else{throw ResponsePreferencesError.missing}
            guard value.revision==receipt.revision else{throw ResponsePreferencesError.receiptMismatch}
            try activate(value,record:false)
        })
    }
    public func useBuiltin(_ focus:ResponseGuideFocus)async throws{
        if focus == .automatic{useGeneral();return}
        let store=storage
        try await perform(stage:.saving,work:{
            let exists=try store.exists(),old=try exists ? ResponsePreferencesCatalog.decode(store.load()):.empty()
            let value=try ResponsePreferencesCatalog(selected:focus.rawValue,guides:old.guides)
            try store.save(value.encoded(),createKey:!exists);return value
        },apply:{[self] value in guard let value else{throw ResponsePreferencesError.invalidCatalog};try activate(value,record:true)})
    }
    public func saveAndUse(_ guide:ResponseGuide,expectedCatalogRevision:UUID?)async throws{
        guard catalog?.revision==expectedCatalogRevision else{throw ResponsePreferencesError.stale}
        let store=storage,expectedMissing = !catalogExists
        try await perform(stage:.saving,work:{
            let exists=try store.exists(),old=try exists ? ResponsePreferencesCatalog.decode(store.load()):.empty()
            if exists{guard !expectedMissing,old.revision==expectedCatalogRevision else{throw ResponsePreferencesError.stale}}
            else if !expectedMissing{throw ResponsePreferencesError.stale}
            var guides=old.guides
            if let index=guides.firstIndex(where:{$0.id==guide.id}){guides[index]=guide}else{guides.append(guide)}
            let value=try ResponsePreferencesCatalog(selected:guide.id.uuidString.lowercased(),guides:guides)
            try store.save(value.encoded(),createKey:!exists);return value
        },apply:{[self] value in guard let value else{throw ResponsePreferencesError.invalidCatalog};try activate(value,record:true)})
    }
    public func delete(id:UUID,expectedCatalogRevision:UUID)async throws{
        guard flight==nil else{throw ResponsePreferencesError.busy}
        guard catalog?.revision==expectedCatalogRevision,catalog?.guides.contains(where:{$0.id==id})==true else{throw ResponsePreferencesError.stale}
        if selected==id.uuidString.lowercased(){useGeneral()}
        let selection=selected,store=storage
        try await perform(stage:.saving,work:{
            guard try store.exists() else{throw ResponsePreferencesError.missing}
            let old=try ResponsePreferencesCatalog.decode(store.load())
            guard old.revision==expectedCatalogRevision else{throw ResponsePreferencesError.stale}
            let value=try ResponsePreferencesCatalog(selected:selection,guides:old.guides.filter{$0.id != id})
            try store.save(value.encoded(),createKey:false);return value
        },apply:{[self] value in
            guard let value else{throw ResponsePreferencesError.invalidCatalog}
            try activate(value,record:value.selected != "general")
        })
    }
}
