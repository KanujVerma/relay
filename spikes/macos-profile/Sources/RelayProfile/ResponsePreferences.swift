import Foundation

public enum ResponsePreferencesError:Error,Sendable,Equatable,LocalizedError {
    case invalidCatalog,invalidGuide,busy,missing,unavailable,stale,receiptMismatch
    public var errorDescription:String?{
        switch self{
        case .invalidCatalog:"The saved response guides are invalid. Open Responses or use General."
        case .invalidGuide:"Use a name up to 64 UTF-8 bytes and guidance up to 2,048 bytes, without hidden control characters."
        case .busy:"Wait for the current preference operation to finish."
        case .missing:"Saved response guides are missing. Open Responses or use General."
        case .unavailable:"Response guides could not be loaded or saved. Retry in Responses or use General."
        case .stale:"The saved guides changed. Reopen Responses; the current draft was kept."
        case .receiptMismatch:"The last preference save was not activated. Reopen Responses or use General."
        }
    }
}
func preferenceDisallowedScalar(_ scalar:Unicode.Scalar,multiline:Bool=false)->Bool {
    if multiline && [9,10].contains(scalar.value){return false}
    switch scalar.properties.generalCategory{case .control,.format,.surrogate,.lineSeparator,.paragraphSeparator:return true;default:return false}
}
public enum ResponseGuideFocus:String,CaseIterable,Sendable {case automatic,coding,feature}
public struct ResponseGuide:Sendable,Equatable,Identifiable {
    public let id:UUID,name:String,focus:ResponseGuideFocus,guidance:String
    public init(id:UUID=UUID(),name:String,focus:ResponseGuideFocus,guidance:String)throws {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf8.count<=64,
              !name.unicodeScalars.contains(where:{preferenceDisallowedScalar($0)}),
              !guidance.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,guidance.utf8.count<=2048,
              !guidance.unicodeScalars.contains(where:{preferenceDisallowedScalar($0,multiline:true)})
        else{throw ResponsePreferencesError.invalidGuide}
        self.id=id;self.name=name;self.focus=focus;self.guidance=guidance
    }
}
public struct ResponsePreferencesCatalog:Sendable,Equatable {
    public let revision:UUID,selected:String,guides:[ResponseGuide]
    private init(validated revision:UUID,selected:String,guides:[ResponseGuide]){self.revision=revision;self.selected=selected;self.guides=guides}
    public init(revision:UUID=UUID(),selected:String="general",guides:[ResponseGuide]=[])throws {
        guard guides.count<=8,Set(guides.map(\.id)).count==guides.count,
              ["general","coding","feature"].contains(selected) || guides.contains(where:{$0.id.uuidString.lowercased()==selected})
        else{throw ResponsePreferencesError.invalidCatalog}
        self.init(validated:revision,selected:selected,guides:guides)
        _=try encoded()
    }
    static func empty()->Self{.init(validated:UUID(),selected:"general",guides:[])}
    public func encoded()throws->Data {
        let data=try JSONSerialization.data(withJSONObject:["schemaVersion":1,"catalogRevision":revision.uuidString.lowercased(),"selected":selected,
            "guides":guides.map{["id":$0.id.uuidString.lowercased(),"name":$0.name,"focus":$0.focus.rawValue,"guidance":$0.guidance]}] as [String:Any],options:[.sortedKeys,.withoutEscapingSlashes])
        guard data.count<=32768 else{throw ResponsePreferencesError.invalidCatalog};return data
    }
    public static func decode(_ data:Data)throws->Self {
        let o=try PreferenceJSON.decode(data).object(["schemaVersion","catalogRevision","selected","guides"])
        guard try o["schemaVersion"]!.uint()==1,let revision=UUID(uuidString:try o["catalogRevision"]!.string(36)) else{throw ResponsePreferencesError.invalidCatalog}
        let guides=try o["guides"]!.array(8).map{node in
            let g=try node.object(["id","name","focus","guidance"])
            guard let id=UUID(uuidString:try g["id"]!.string(36)),let focus=ResponseGuideFocus(rawValue:try g["focus"]!.string()),case .string(let guidance)=g["guidance"]!
            else{throw ResponsePreferencesError.invalidCatalog}
            return try ResponseGuide(id:id,name:try g["name"]!.string(64),focus:focus,guidance:guidance)
        }
        return try Self(revision:revision,selected:try o["selected"]!.string(36),guides:guides)
    }
    func activation()->ResponsePreferenceSnapshot? {
        if selected=="general"{return nil}
        if selected=="coding"{return .init(selection:selected,name:"Coding discussion",focus:.coding,guidance:"Prefer supplied input contracts, invariants and boundary cases. Follow the current coding stage and engineer feedback; provide implementation only when requested.")}
        if selected=="feature"{return .init(selection:selected,name:"Feature discussion",focus:.feature,guidance:"Prefer the current users, requirements, workflow, tradeoffs or validation stage. Do not skip ahead to a complete design when the current question asks for one step.")}
        guard let guide=guides.first(where:{$0.id.uuidString.lowercased()==selected}) else{return nil}
        return .init(selection:selected,name:guide.name,focus:guide.focus,guidance:guide.guidance)
    }
}
/// Immutable native-issued preference data, never source/account authority.
public final class ResponsePreferenceSnapshot:Sendable {
    public let revision=UUID()
    public let selection:String,displayName:String,focus:ResponseGuideFocus,guidance:String
    init(selection:String,name:String,focus:ResponseGuideFocus,guidance:String){self.selection=selection;displayName=name;self.focus=focus;self.guidance=guidance}
    func sameGuide(as other:ResponsePreferenceSnapshot)->Bool{selection==other.selection && displayName==other.displayName && focus==other.focus && guidance==other.guidance}
}
public struct ResponsePreferencesReceipt:Sendable,Equatable {
    public let enabled:Bool,revision:UUID?
    public init(enabled:Bool,revision:UUID?){self.enabled=enabled;self.revision=revision}
}
@MainActor public protocol ResponsePreferencesReceiptStore:AnyObject {
    func read()->ResponsePreferencesReceipt
    func commit(_ revision:UUID)
    func disable()
}
@MainActor public final class UserDefaultsResponsePreferencesReceipts:ResponsePreferencesReceiptStore {
    private let defaults:()->UserDefaults
    public init(defaults:@escaping ()->UserDefaults={.standard}){self.defaults=defaults}
    public func read()->ResponsePreferencesReceipt{let d=defaults();return .init(enabled:d.bool(forKey:"useSavedResponsePreferences"),revision:d.string(forKey:"committedResponsePreferencesRevision").flatMap(UUID.init(uuidString:)))}
    public func commit(_ revision:UUID){let d=defaults();d.set(revision.uuidString.lowercased(),forKey:"committedResponsePreferencesRevision");d.set(true,forKey:"useSavedResponsePreferences")}
    public func disable(){defaults().set(false,forKey:"useSavedResponsePreferences")}
}
/// Resolve Application Support and construct the inert vault only on explicit IO.
public final class DefaultResponsePreferencesStorage:ProtectedSnapshotStorage,@unchecked Sendable {
    private let lock=NSLock();private var vault:ProtectedSnapshotVault?
    public init(){}
    private func storage()throws->ProtectedSnapshotVault {
        try lock.withLock{
            if let vault{return vault}
            guard let support=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first else{throw ResponsePreferencesError.unavailable}
            let created=ProtectedSnapshotVault(directory:support.appendingPathComponent("Relay/ResponsePreferences"),purpose:.responsePreferences,keys:KeychainProfileKey(purpose:.responsePreferences))
            vault=created;return created
        }
    }
    public func exists()throws->Bool{try storage().exists()}
    public func load()throws->Data{try storage().load()}
    public func save(_ payload:Data,createKey:Bool)throws{try storage().save(payload,createKey:createKey)}
}
