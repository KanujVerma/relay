import Foundation
import RelayProfile
import RelaySessionPanel
import RelayContextComposition

/// Optional request data only. Callers independently keep the actual original
/// conversation/helper/native lease gates; this object never issues a request.
@MainActor final class ResponsePreferencesRequestBridge {
    private final class Record {
        let binding:PanelRequestBinding,revision:UUID,name:String
        var snapshot:ResponsePreferenceSnapshot?
        var offered=false,retired=false
        init(_ binding:PanelRequestBinding,_ snapshot:ResponsePreferenceSnapshot){
            self.binding=binding;self.snapshot=snapshot;revision=snapshot.revision;name=snapshot.displayName
        }
    }
    private let capture:@MainActor ()->ResponsePreferenceSnapshot?
    private let owns:@MainActor (ResponsePreferenceSnapshot)->Bool
    private let send:@MainActor (Data)throws->Void
    private let isCurrent:@MainActor ()->Bool
    private var records:[UUID:Record]=[:]
    private var scope:(UUID,UInt64)?
    private var blocked=false,closed=false
    init(capture:@escaping @MainActor ()->ResponsePreferenceSnapshot?,owns:@escaping @MainActor (ResponsePreferenceSnapshot)->Bool,
         send:@escaping @MainActor (Data)throws->Void,isCurrent:@escaping @MainActor ()->Bool){
        self.capture=capture;self.owns=owns;self.send=send;self.isCurrent=isCurrent
    }
    func freeze(_ binding:PanelRequestBinding)throws {
        guard !blocked else{throw PanelBridgeError.closed}
        guard !closed,isCurrent() else{return}
        if let old=records[binding.requestID]{guard old.binding==binding else{throw PanelBridgeError.malformed};return}
        guard let snapshot=capture() else{return}
        if let scope{guard scope.0==binding.lease.captureSessionID,scope.1==binding.lease.sessionEpoch else{throw PanelBridgeError.closed}}
        else{scope=(binding.lease.captureSessionID,binding.lease.sessionEpoch)}
        records=records.filter{!$0.value.retired}
        guard records.count<8 else{throw PanelBridgeError.overflow}
        records[binding.requestID]=Record(binding,snapshot)
    }
    func sendOffer(for binding:PanelRequestBinding)throws {
        guard !blocked else{throw PanelBridgeError.closed}
        guard !closed,isCurrent(),let record=records[binding.requestID],record.binding==binding,
              !record.retired,!record.offered,let original=record.snapshot,owns(original) else{return}
        let value:[String:Any] = ["schemaVersion":1,"kind":"response_preferences",
            "captureSessionID":binding.lease.captureSessionID.uuidString.lowercased(),"sessionEpoch":binding.lease.sessionEpoch,
            "presentationGeneration":binding.lease.presentationGeneration,"requestID":binding.requestID.uuidString.lowercased(),
            "eventSequence":binding.eventSequence,"preferencesRevision":original.revision.uuidString.lowercased(),
            "focus":original.focus.rawValue,"guidance":original.guidance]
        do{try send(JSONSerialization.data(withJSONObject:value));record.offered=true}
        catch{block();throw error}
    }
    func permits(_ binding:PanelRequestBinding,revision:UUID?)->Bool {
        guard !blocked,!closed,isCurrent() else{return false}
        guard let revision else{return true}
        guard let record=records[binding.requestID],record.binding==binding,record.revision==revision,
              record.offered,!record.retired,let original=record.snapshot else{return false}
        return owns(original)
    }
    func capturedRevision(for binding:PanelRequestBinding)->UUID?{
        guard let record=records[binding.requestID],record.binding==binding else{return nil};return record.revision
    }
    func displayName(for binding:PanelRequestBinding,revision:UUID)->String? {
        guard permits(binding,revision:revision) else{return nil};return records[binding.requestID]?.name
    }
    func retire(_ original:ResponsePreferenceSnapshot)throws {
        guard !closed,isCurrent(),let scope else{return}
        let matching=records.values.filter{$0.revision==original.revision}
        guard !matching.isEmpty else{return}
        let value:[String:Any] = ["schemaVersion":1,"kind":"response_preferences_retired",
            "captureSessionID":scope.0.uuidString.lowercased(),"sessionEpoch":scope.1,
            "preferencesRevision":original.revision.uuidString.lowercased()]
        do{
            // This enqueue precedes every local cleanup/publication callback.
            try send(JSONSerialization.data(withJSONObject:value))
            for record in matching{record.retired=true;record.snapshot=nil}
        }catch{block();throw error}
    }
    func retireNative(_ binding:PanelRequestBinding){
        guard let record=records[binding.requestID],record.binding==binding else{return}
        record.retired=true;record.snapshot=nil
    }
    private func block(){
        blocked=true
        for record in records.values{record.retired=true;record.snapshot=nil}
    }
    func close(){closed=true;records.removeAll()}
}
