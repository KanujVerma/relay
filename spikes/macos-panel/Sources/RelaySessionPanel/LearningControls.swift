import Foundation

/// One exact content-free row in learning_rule. Consent revision changes only
/// for explicit controls, never when ordinary source observations are added.
public struct LearningControlRecord:Codable,Equatable,Sendable {
    public let revision:UUID,enabled:Bool,suppressedRuleIDs:Set<String>
    public init(revision:UUID,enabled:Bool,suppressedRuleIDs:Set<String>){self.revision=revision;self.enabled=enabled;self.suppressedRuleIDs=suppressedRuleIDs}
    static var knownRuleIDs:Set<String>{Set(LearningScope.allCases.flatMap{scope in LearningAdjustment.allCases.map{scope.rawValue+":"+$0.rawValue}})}
    func validate()throws{guard suppressedRuleIDs.count<=9,suppressedRuleIDs.isSubset(of:Self.knownRuleIDs) else{throw HistoryError.invalid}}
    private enum CodingKeys:String,CodingKey{case schemaVersion,kind,revision,enabled,suppressedRuleIDs}
    public init(from decoder:any Decoder)throws{
        let c=try decoder.container(keyedBy:CodingKeys.self)
        guard try c.decode(Int.self,forKey:.schemaVersion)==1,try c.decode(String.self,forKey:.kind)=="learning_control" else{throw HistoryError.invalid}
        let ids=try c.decode([String].self,forKey:.suppressedRuleIDs)
        guard ids==ids.sorted(),Set(ids).count==ids.count else{throw HistoryError.invalid}
        revision=try c.decode(UUID.self,forKey:.revision);enabled=try c.decode(Bool.self,forKey:.enabled);suppressedRuleIDs=Set(ids);try validate()
    }
    public func encode(to encoder:any Encoder)throws{
        var c=encoder.container(keyedBy:CodingKeys.self)
        try c.encode(1,forKey:.schemaVersion);try c.encode("learning_control",forKey:.kind);try c.encode(revision,forKey:.revision)
        try c.encode(enabled,forKey:.enabled);try c.encode(suppressedRuleIDs.sorted(),forKey:.suppressedRuleIDs)
    }
}
/// Persisted denial intent contains no source IDs, quotes or private facts.
public struct LearningPendingControl:Codable,Equatable,Sendable {
    public let target:LearningControlRecord,expectedRevision:UUID?,clearExamples:Bool
    public var revision:UUID{target.revision}
    init(target:LearningControlRecord,expectedRevision:UUID?,clearExamples:Bool){self.target=target;self.expectedRevision=expectedRevision;self.clearExamples=clearExamples}
    func validate()throws{try target.validate()}
    public func applying(to archive:LearningArchive)throws->LearningArchive{
        try validate();try archive.validate()
        if archive.control?.revision==revision{
            guard archive.control==target,!clearExamples || archive.episodes.isEmpty else{throw HistoryError.stale};return archive
        }
        guard archive.control?.revision==expectedRevision else{throw HistoryError.stale}
        let episodes=clearExamples ? []:archive.episodes
        return LearningArchive(episodes:episodes,rules:try LearningDerivation.rebuild(episodes,suppressed:target.suppressedRuleIDs),control:target)
    }
}
public struct LearningControlReceipt:Codable,Equatable,Sendable {
    public let revision:UUID?,enabled:Bool,pending:LearningPendingControl?
    public init(revision:UUID?,enabled:Bool,pending:LearningPendingControl?){self.revision=revision;self.enabled=enabled;self.pending=pending}
    func validate()throws{
        if let pending{try pending.validate();guard !enabled,revision==pending.revision else{throw HistoryError.invalid}}
        else if enabled,revision==nil{throw HistoryError.invalid}
    }
    func matches(_ control:LearningControlRecord?)->Bool{pending==nil && revision==control?.revision && enabled==control?.enabled}
}
@MainActor public protocol LearningControlPreferences:AnyObject {
    func read()throws->LearningControlReceipt
    func deny(_ pending:LearningPendingControl)throws->LearningControlReceipt
    func commit(_ control:LearningControlRecord)throws->LearningControlReceipt
}

/// These read views never authorize a store write or a native request. Only the
/// existing History owner can issue the actual post-flight receipt in the app.
public struct LearningPersistenceScope:Sendable,Equatable {
    public let workspaceEpoch:UUID,recordID:UUID?,expiresAt:TimeInterval?
    init(workspaceEpoch:UUID,recordID:UUID?,expiresAt:TimeInterval?){self.workspaceEpoch=workspaceEpoch;self.recordID=recordID;self.expiresAt=expiresAt}
}
public struct LearningArchiveReceipt:Sendable {
    public let workspaceEpoch:UUID,archive:LearningArchive
    init(workspaceEpoch:UUID,archive:LearningArchive){self.workspaceEpoch=workspaceEpoch;self.archive=archive}
}
@MainActor public struct LearningPersistencePorts {
    let scope:@MainActor ()->LearningPersistenceScope?
    let load:@MainActor ()async throws->LearningArchiveReceipt
    let mutate:@MainActor (LearningMutation)async throws->LearningArchiveReceipt
    public init(scope:@escaping @MainActor ()->LearningPersistenceScope?,load:@escaping @MainActor ()async throws->LearningArchiveReceipt,
                mutate:@escaping @MainActor (LearningMutation)async throws->LearningArchiveReceipt){self.scope=scope;self.load=load;self.mutate=mutate}
}
public enum LearningSourceRetirement:Sendable {
    case workspace(workspaceEpoch:UUID)
    case record(workspaceEpoch:UUID,recordID:UUID)
    case source(workspaceEpoch:UUID,recordID:UUID,captureID:String,source:TranscriptSource)
    var workspaceEpoch:UUID{switch self{case .workspace(let epoch),.record(let epoch,_),.source(let epoch,_,_,_):epoch}}
}
