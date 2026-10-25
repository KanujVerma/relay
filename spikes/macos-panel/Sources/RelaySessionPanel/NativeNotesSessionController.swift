import Dispatch
import Foundation

public enum NotesSessionError:Error,Sendable {case unavailable(String),retired}

final class NotesPending<Value:Sendable>:@unchecked Sendable {
    private let lock=NSLock()
    private var result:Result<Value,any Error>?,waiter:CheckedContinuation<Value,any Error>?
    func value()async throws->Value {
        try await withCheckedThrowingContinuation{continuation in
            let ready=lock.withLock{()->Result<Value,any Error>? in
                if let result{return result}
                guard waiter==nil else{return .failure(PanelBridgeError.malformed)}
                waiter=continuation;return nil
            }
            if let ready{continuation.resume(with:ready)}
        }
    }
    func finish(_ outcome:Result<Value,any Error>){
        let pending=lock.withLock{()->CheckedContinuation<Value,any Error>? in
            guard result==nil else{return nil};result=outcome;let value=waiter;waiter=nil;return value
        }
        pending?.resume(with:outcome)
    }
}

struct NotesScopeCommand:Sendable,Equatable {
    let scopeID:UUID,epoch:UInt64,operationID:UUID,action:String
    func json()throws->Data{try NotesEncoding.json(["schemaVersion":1,"kind":"notes_scope_request","scopeID":scopeID.uuidString.lowercased(),
        "scopeEpoch":epoch,"operationID":operationID.uuidString.lowercased(),"action":action])}
    func matches(_ reply:NotesScopeResponseData)->Bool{reply.scopeID==scopeID && reply.scopeEpoch==epoch && reply.operationID==operationID && reply.action==action}
}
enum NotesEncoding {
    static func json(_ value:[String:Any])throws->Data{
        let raw=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes]);_=try StrictJSON.decode(raw);return raw
    }
    static func frame(_ raw:Data)->Data{var size=UInt32(raw.count).bigEndian;var value=withUnsafeBytes(of:&size){Data($0)};value.append(raw);return value}
}

/// The source admission pointer is captured on MainActor. Writer predicates
/// read only these thread-safe denial gates, never actor state or callbacks.
final class NotesNativeGate:@unchecked Sendable {
    private let lock=NSLock(),sourceGate:HistoryAdmission
    private let helper:HelperTransport,close:Data
    private let deadline:UInt64
    private var retired=false,opened=false,closeSent=false,cancel:Data?
    init(sourceGate:HistoryAdmission,helper:HelperTransport,close:Data,deadline:UInt64){self.sourceGate=sourceGate;self.helper=helper;self.close=close;self.deadline=deadline}
    var allowed:Bool{lock.withLock{!retired} && sourceGate.allowed && DispatchTime.now().uptimeNanoseconds<deadline}
    func reserveOpen()->Bool{lock.withLock{guard !retired,sourceGate.allowed,DispatchTime.now().uptimeNanoseconds<deadline,!opened else{return false};opened=true;return true}}
    func reserveRequest(cancel:Data)->Bool{lock.withLock{guard !retired,sourceGate.allowed,DispatchTime.now().uptimeNanoseconds<deadline,opened,self.cancel==nil else{return false};self.cancel=cancel;return true}}
    var wasOpened:Bool{lock.withLock{opened}}
    func retire(){send(retiring:true)}
    func closeNormally(){send(retiring:false)}
    private func send(retiring:Bool){
        let frames:[Data]=lock.withLock{
            if retiring{retired=true}
            guard opened,!closeSent else{return []};closeSent=true
            return retiring ? (cancel.map{[$0,close]} ?? [close]):[close]
        }
        // Never acquire helper/writer ownership while holding this gate lock.
        do{for frame in frames{try helper.sendJSON(frame)}}catch{helper.stop()}
    }
}

struct NotesNativeRequest:Sendable {
    let scopeID:UUID,epoch:UInt64,operationID:UUID,requestID:UUID,transferID:UUID
    let source:HistoryNotesSource,sourceData:HistoryNotesSourceData
    var base:[String:Any]{["schemaVersion":1,"scopeID":scopeID.uuidString.lowercased(),"scopeEpoch":epoch,
        "requestID":requestID.uuidString.lowercased(),"requestSequence":1,"transferID":transferID.uuidString.lowercased(),
        "recordID":sourceData.recordID.uuidString.lowercased(),"recordRevision":String(sourceData.recordRevision),"sourceDigest":sourceData.sourceDigest]}
    func generate()throws->Data{var v=base;v["kind"]="notes_generate";return try NotesEncoding.json(v)}
    func cancel()throws->Data{var v=base;v["kind"]="notes_cancel";v["reasonCode"]="cancelled";return try NotesEncoding.json(v)}
    func begin()throws->Data{var v=base;v["kind"]="notes_source_begin";v["selectionKind"]=sourceData.selection.kind
        v["rowCount"]=sourceData.rows.count;v["totalBytes"]=sourceData.rawBytes.count;return try NotesEncoding.json(v)}
    func chunk(_ index:Int,_ bytes:Data)throws->Data{try NotesEncoding.json(["schemaVersion":1,"kind":"notes_source_chunk",
        "scopeID":scopeID.uuidString.lowercased(),"scopeEpoch":epoch,"requestID":requestID.uuidString.lowercased(),
        "transferID":transferID.uuidString.lowercased(),"index":index,"data":bytes.base64EncodedString()])}
    func end(_ count:Int)throws->Data{try NotesEncoding.json(["schemaVersion":1,"kind":"notes_source_end",
        "scopeID":scopeID.uuidString.lowercased(),"scopeEpoch":epoch,"requestID":requestID.uuidString.lowercased(),
        "transferID":transferID.uuidString.lowercased(),"chunkCount":count,"totalBytes":sourceData.rawBytes.count,"sourceDigest":sourceData.sourceDigest])}
    func matches(_ value:NotesResultData)->Bool{value.scopeID==scopeID && value.scopeEpoch==epoch && value.requestID==requestID
        && value.transferID==transferID && value.requestSequence==1 && value.recordID==sourceData.recordID
        && value.recordRevision==sourceData.recordRevision && value.sourceDigest==sourceData.sourceDigest}
}

/// No public initializer or serialization. Only actual registered helper IO can
/// issue one. A separate current History source and Store CAS remain required.
public final class NotesCompletedOperation:@unchecked Sendable,CustomStringConvertible {
    let source:HistoryNotesSource,output:HistoryNotesOutputData,modelID:String,generation:HistoryNotesGenerationData
    let sourceData:HistoryNotesSourceData,gate:NotesNativeGate,helper:HelperTransport
    private let lock=NSLock()
    private var claimed=false,committed:HistoryNotesCommitOutcome?
    /// An actual positive Store return, not an inference or painting grant.
    public var actualCommittedOutcome:HistoryNotesCommitOutcome?{lock.withLock{committed}}
    public var description:String{"NotesCompletedOperation(<private>)"}
    init(result:NotesResultData,request:NotesNativeRequest,helper:HelperTransport,gate:NotesNativeGate,model:String)throws{
        guard result.status=="completed",let output=result.notes,request.matches(result),gate.allowed else{throw NotesSessionError.retired}
        source=request.source;sourceData=request.sourceData;self.output=output;modelID=model;self.gate=gate;self.helper=helper
        generation=HistoryNotesGenerationData(scopeID:request.scopeID,scopeEpoch:request.epoch,operationID:request.operationID,
            requestID:request.requestID,requestSequence:1,transferID:request.transferID,completedAt:try HistoryNotesDocuments.timestamp(Date()))
    }
    @MainActor func claim(using history:SessionHistoryCoordinator)throws{
        guard gate.allowed,helper.notesPublicationAllowed,history.ownsNotesSource(source),gate.allowed,helper.notesPublicationAllowed else{throw HistoryError.stale}
        try lock.withLock{guard !claimed else{throw HistoryError.stale};claimed=true}
    }
    var saveAdmission:Bool{gate.allowed && helper.notesPublicationAllowed}
    func recordActualSave(_ outcome:HistoryNotesCommitOutcome){
        guard outcome.receipt.operationID==generation.operationID,outcome.receipt.recordID==sourceData.recordID,
              outcome.receipt.sourceRecordRevision==sourceData.recordRevision,outcome.document.generation==generation,
              outcome.document.modelID==modelID else{return}
        // Actual save already returned positively. This cannot throw or invoke
        // actor callbacks before the one History flight publishes its result.
        lock.withLock{if committed==nil{committed=outcome}}
    }
}

/// One original source, one scope and one generation. Constructor is inert.
@MainActor public final class NativeNotesSessionController {
    private let history:SessionHistoryCoordinator,source:HistoryNotesSource,helper:HelperTransport
    private let deadline:UInt64,isCurrent:@MainActor ()->Bool,onProgress:@MainActor (GeneratedMeetingNotesPhase)->Void
    private let opening:NotesScopeCommand,closing:NotesScopeCommand,gate:NotesNativeGate
    private var task:Task<NotesCompletedOperation,Error>?
    public private(set) var isQuiesced=true
    public init(history:SessionHistoryCoordinator,source:HistoryNotesSource,helper:HelperTransport,
                deadline:UInt64=DispatchTime.now().uptimeNanoseconds+30_000_000_000,
                isCurrent:@escaping @MainActor ()->Bool,onProgress:@escaping @MainActor (GeneratedMeetingNotesPhase)->Void={_ in}){
        self.history=history;self.source=source;self.helper=helper;self.deadline=deadline;self.isCurrent=isCurrent;self.onProgress=onProgress
        let scope=UUID();opening=NotesScopeCommand(scopeID:scope,epoch:1,operationID:source.intentID,action:"open")
        closing=NotesScopeCommand(scopeID:scope,epoch:1,operationID:UUID(),action:"close")
        // Fixed bounded mechanical fields, so construction cannot fail or do IO.
        gate=NotesNativeGate(sourceGate:source.gate,helper:helper,close:try! closing.json(),deadline:deadline)
    }
    private var current:Bool{
        guard gate.allowed,DispatchTime.now().uptimeNanoseconds<deadline,history.ownsNotesSource(source),isCurrent() else{return false}
        guard history.ownsNotesSource(source) else{return false};return gate.allowed
    }
    private func check()throws{try Task.checkCancellation();guard current else{throw NotesSessionError.retired};try Task.checkCancellation()}
    public func generate()async throws->NotesCompletedOperation{
        do{try Task.checkCancellation()}catch{cancel();throw error}
        if task==nil{task=Task{try await self.execute()}}
        let original=task!,gate=self.gate
        do{
            return try await withTaskCancellationHandler(operation:{
                let value=try await original.value
                try Task.checkCancellation();guard current,helper.notesPublicationAllowed else{throw NotesSessionError.retired}
                try Task.checkCancellation();return value
            },onCancel:{gate.retire();original.cancel()})
        }catch{gate.retire();original.cancel();_=await original.result;throw error}
    }
    public func sourceRetired(_ original:HistoryNotesSource){if original === source{cancel()}}
    public func cancel(){gate.retire();task?.cancel()}
    public func waitForQuiescence()async{if let task{_=await task.result}}
    private func execute()async throws->NotesCompletedOperation{
        var closePending:NotesPending<NotesScopeResponseData>?
        var candidate:NotesCompletedOperation?,failure:(any Error)?
        do{
            try check();guard helper.notesConfiguredModel != nil else{throw NotesSessionError.unavailable("inference_disabled")}
            onProgress(.preparing);try check()
            let waits=try helper.openNotes(opening,closing:closing,gate:gate,deadline:deadline)
            closePending=waits.1;isQuiesced=false
            let opened=try await waits.0.value()
            guard opened.status=="ready" else{throw NotesSessionError.unavailable(opened.reasonCode)}
            try check()
            let request=NotesNativeRequest(scopeID:opening.scopeID,epoch:opening.epoch,operationID:source.intentID,
                requestID:UUID(),transferID:UUID(),source:source,sourceData:source.data)
            let transferDeadline=min(deadline,DispatchTime.now().uptimeNanoseconds+5_000_000_000),gate=self.gate
            try await helper.sendJSONAwaitingWrite(request.begin(),deadline:transferDeadline,isCurrent:{gate.allowed});try check()
            var count=0
            for offset in stride(from:0,to:source.data.rawBytes.count,by:8192){
                try check();let bytes=source.data.rawBytes.subdata(in:offset..<min(offset+8192,source.data.rawBytes.count))
                try await helper.sendJSONAwaitingWrite(request.chunk(count,bytes),deadline:transferDeadline,isCurrent:{gate.allowed});count+=1;try check()
            }
            try await helper.sendJSONAwaitingWrite(request.end(count),deadline:transferDeadline,isCurrent:{gate.allowed});try check()
            onProgress(.generating);try check()
            let pending=try helper.generateNotes(request,gate:gate,deadline:deadline)
            candidate=try await pending.value();try check()
        }catch{failure=error;gate.retire()}
        if gate.wasOpened{
            gate.closeNormally()
            do{
                guard let closePending else{throw PanelBridgeError.closed};let reply=try await closePending.value()
                guard reply.status=="closed",reply.quiesced==true else{throw PanelBridgeError.closed}
                isQuiesced=true
            }catch{
                gate.retire();await helper.shutdownAndWait();isQuiesced=true
                if failure==nil{failure=NotesSessionError.unavailable("transport_closed")}
            }
        }
        if let failure{throw failure};try check()
        guard let candidate else{throw NotesSessionError.unavailable("request_unavailable")};return candidate
    }
}
