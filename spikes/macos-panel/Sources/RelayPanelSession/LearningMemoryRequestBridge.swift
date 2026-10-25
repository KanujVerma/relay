import Foundation
import RelaySessionPanel
import RelayContextComposition

/// Read-only optional request data. It never issues or restores a native lease.
@MainActor final class LearningMemoryRequestBridge {
    private final class Record {
        let binding:PanelRequestBinding,revision:UUID,lifetime:UUID
        var snapshot:LearningProjectionSnapshot?,offered=false,retired=false
        init(_ binding:PanelRequestBinding,_ snapshot:LearningProjectionSnapshot){self.binding=binding;self.snapshot=snapshot;revision=snapshot.revision;lifetime=snapshot.lifetimeEpoch}
    }
    private let capture:@MainActor (String)->LearningProjectionSnapshot?
    private let owns:@MainActor (LearningProjectionSnapshot)->Bool
    private let send:@MainActor (Data)throws->Void
    private let isCurrent:@MainActor ()->Bool
    private var records:[UUID:Record]=[:]
    private var scope:(UUID,UInt64)?
    private var closed=false,blocked=false
    init(capture:@escaping @MainActor (String)->LearningProjectionSnapshot?,owns:@escaping @MainActor (LearningProjectionSnapshot)->Bool,
         send:@escaping @MainActor (Data)throws->Void,isCurrent:@escaping @MainActor ()->Bool){self.capture=capture;self.owns=owns;self.send=send;self.isCurrent=isCurrent}
    func freeze(_ binding:PanelRequestBinding,question:String)throws{
        guard !blocked else{throw PanelBridgeError.closed};guard !closed,isCurrent() else{return}
        if let original=records[binding.requestID]{guard original.binding==binding else{throw PanelBridgeError.malformed};return}
        guard let value=capture(question) else{return}
        if let scope{guard scope.0==binding.lease.captureSessionID,scope.1==binding.lease.sessionEpoch else{throw PanelBridgeError.closed}}
        else{scope=(binding.lease.captureSessionID,binding.lease.sessionEpoch)}
        records=records.filter{!$0.value.retired};guard records.count<8 else{throw PanelBridgeError.overflow}
        records[binding.requestID]=Record(binding,value)
    }
    func sendOffer(for binding:PanelRequestBinding)throws{
        guard !blocked else{throw PanelBridgeError.closed}
        guard !closed,isCurrent(),let record=records[binding.requestID],record.binding==binding,!record.offered,!record.retired,
              let original=record.snapshot,owns(original) else{return}
        guard var value=try JSONSerialization.jsonObject(with:original.payload.encodedPayload()) as? [String:Any] else{throw PanelBridgeError.malformed}
        value.merge(["schemaVersion":1,"kind":"learning_memory","captureSessionID":binding.lease.captureSessionID.uuidString.lowercased(),
            "sessionEpoch":binding.lease.sessionEpoch,"presentationGeneration":binding.lease.presentationGeneration,
            "requestID":binding.requestID.uuidString.lowercased(),"eventSequence":binding.eventSequence,"memoryRevision":original.revision.uuidString.lowercased()]){_,new in new}
        do{try send(JSONSerialization.data(withJSONObject:value));record.offered=true}catch{block();throw error}
    }
    func permits(_ binding:PanelRequestBinding,revision:UUID?)->Bool{
        guard !blocked,!closed,isCurrent() else{return false};guard let revision else{return true}
        guard let record=records[binding.requestID],record.binding==binding,record.revision==revision,record.offered,!record.retired,let original=record.snapshot else{return false}
        return owns(original)
    }
    func lifetime(for binding:PanelRequestBinding)->UUID?{guard let r=records[binding.requestID],r.binding==binding else{return nil};return r.lifetime}
    func revision(for binding:PanelRequestBinding)->UUID?{guard let r=records[binding.requestID],r.binding==binding else{return nil};return r.revision}
    func explanation(for binding:PanelRequestBinding,revision:UUID)->String?{
        guard permits(binding,revision:revision),let value=records[binding.requestID]?.snapshot?.payload else{return nil}
        if !value.adjustments.isEmpty{return "From \(value.supportIDs.count) similar replies across \(value.sourceRecordIDs.count) saved meetings. This may suit you; Undo stops applying it."}
        return value.supportIDs.isEmpty ? "Using current meeting context.":"Using source examples from saved meetings."
    }
    func retire(lifetime:UUID)throws{
        guard !closed,isCurrent(),let scope else{return}
        let matching=records.values.filter{$0.lifetime==lifetime && !$0.retired}
        for record in matching{
            let value:[String:Any]=["schemaVersion":1,"kind":"learning_memory_retired","captureSessionID":scope.0.uuidString.lowercased(),
                "sessionEpoch":scope.1,"memoryRevision":record.revision.uuidString.lowercased()]
            do{try send(JSONSerialization.data(withJSONObject:value));record.retired=true;record.snapshot=nil}catch{block();throw error}
        }
    }
    func retireNative(_ binding:PanelRequestBinding){guard let r=records[binding.requestID],r.binding==binding else{return};r.retired=true;r.snapshot=nil}
    private func block(){blocked=true;for r in records.values{r.retired=true;r.snapshot=nil}}
    func close(){closed=true;records=[:]}
}
