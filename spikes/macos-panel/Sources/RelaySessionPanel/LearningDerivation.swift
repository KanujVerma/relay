import Foundation

public struct LearningRule:Codable,Equatable,Sendable,Identifiable {
    public let id:String,scope:LearningScope,adjustment:LearningAdjustment
    public let supportIDs:[UUID],sessionCount:Int,expiresAt:TimeInterval?,suppressed:Bool
    public var label:String{adjustment.label}
    public var why:String{suppressed ? "Undone. Existing examples cannot reactivate this adjustment.":"Tentative: \(supportIDs.count) possible-uptake examples across \(sessionCount) saved sessions. Reading, correctness and outcomes are unknown."}
}
public struct LearningArchive:Equatable,Sendable {
    public let episodes:[LearningEpisode],rules:[LearningRule]
    private let withinCapacity:Bool,structurallyValid:Bool
    /// Construct on the owned store/reflection path, outside live requests.
    /// This cache validates data shape/derivation, never retained-source rights.
    public init(episodes:[LearningEpisode]=[],rules:[LearningRule]=[]){
        self.episodes=episodes;self.rules=rules
        withinCapacity=episodes.count<=LearningBounds.episodes && rules.count<=LearningBounds.rules
            && ((try? HistoryJSON.encode(episodes).count) ?? Int.max)<=LearningBounds.retainedBytes
        structurallyValid=withinCapacity && Set(episodes.map(\.id)).count==episodes.count && Set(rules.map(\.id)).count==rules.count
            && (try? LearningDerivation.rebuild(episodes,suppressed:Set(rules.filter(\.suppressed).map(\.id))))==rules
    }
    func validate()throws{
        guard withinCapacity else{throw HistoryError.capacity}
        guard structurallyValid else{throw HistoryError.invalid}
    }
}
public enum LearningMutation:Sendable {case save(LearningEpisode),suppress(String),reset}
public struct LearningExample:Equatable,Sendable {
    public let sourceID:String,text:String
    var wire:[String:Any]{["sourceID":sourceID,"text":text]}
}
public struct LearningRequestProjection:Sendable {
    public let scope:LearningScope
    public internal(set) var evidenceGap=false
    public internal(set) var continuity:[LearningQuote]=[],adjustments:[LearningAdjustment]=[],preparation:[LearningExample]=[],examples:[LearningExample]=[]
    public internal(set) var supportIDs:[UUID]=[]
    public internal(set) var sourceRecordIDs:Set<UUID>=[]
    public internal(set) var expiresAt:TimeInterval?
    public var isEmpty:Bool{continuity.isEmpty && adjustments.isEmpty && preparation.isEmpty && examples.isEmpty && !evidenceGap}
    public func encodedPayload()throws->Data{
        let value:[String:Any]=["scope":scope.rawValue,"evidenceGap":evidenceGap,"continuity":continuity.map(\.wire),"adjustments":adjustments.map(\.rawValue),"preparation":preparation.map(\.wire),"examples":examples.map(\.wire),"supportIDs":supportIDs.map{$0.uuidString.lowercased()}]
        let data=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
        guard data.count<=LearningBounds.projectionBytes,continuity.count<=2,adjustments.count<=2,preparation.count<=2,examples.count<=2,supportIDs.count<=8 else{throw HistoryError.capacity}
        return data
    }
    mutating func bound(){
        continuity=Array(continuity.prefix(2));adjustments=Array(adjustments.prefix(2));preparation=Array(preparation.prefix(2));examples=Array(examples.prefix(2));supportIDs=Array(supportIDs.prefix(8))
        while (try? encodedPayload())==nil{
            if !examples.isEmpty{examples.removeLast()}
            else if !preparation.isEmpty{preparation.removeLast()}
            else if !continuity.isEmpty{continuity.removeLast();evidenceGap=true}
            else{supportIDs=[];adjustments=[];break}
        }
    }
}
/// Deterministic reflection only. It derives presentation candidates from
/// original observed records and makes zero provider/model calls.
public enum LearningDerivation {
    public static func rebuild(_ episodes:[LearningEpisode],suppressed:Set<String>)throws->[LearningRule]{
        guard episodes.count<=LearningBounds.episodes,Set(episodes.map(\.id)).count==episodes.count,suppressed.count<=LearningBounds.rules else{throw HistoryError.capacity}
        for episode in episodes{try episode.validate();guard episode.recordID != nil,episode.expiresAt != nil else{throw HistoryError.invalid}}
        var rules:[LearningRule]=[],known:Set<String>=[]
        for scope in LearningScope.allCases{for adjustment in LearningAdjustment.allCases{
            let id=scope.rawValue+":"+adjustment.rawValue;known.insert(id)
            let support=episodes.filter{$0.scope==scope && $0.adjustments.contains(adjustment)}
            let sessions=Set(support.compactMap(\.recordID)).count,undone=suppressed.contains(id)
            if (support.count>=3 && sessions>=2) || undone{
                rules.append(LearningRule(id:id,scope:scope,adjustment:adjustment,supportIDs:support.map(\.id).sorted{$0.uuidString<$1.uuidString},sessionCount:sessions,expiresAt:support.compactMap(\.expiresAt).min(),suppressed:undone))
            }
        }}
        guard suppressed.isSubset(of:known),rules.count<=LearningBounds.rules else{throw HistoryError.invalid}
        return rules.sorted{$0.id<$1.id}
    }
    public static func project(_ archive:LearningArchive,question:String,now:TimeInterval)->LearningRequestProjection{
        let scope=LearningScope.matching(question),tokens=LearningText.tokens(question)
        var result=LearningRequestProjection(scope:scope)
        guard now.isFinite,(try? archive.validate()) != nil else{return result}
        let episodes=archive.episodes.filter{$0.scope==scope && ($0.expiresAt ?? 0)>now}
        let episodeIDs=Set(episodes.map(\.id))
        let rules=archive.rules.filter{!$0.suppressed && $0.scope==scope && ($0.expiresAt ?? 0)>now && Set($0.supportIDs).isSubset(of:episodeIDs)}
        result.adjustments=Array(rules.prefix(2).map(\.adjustment))
        let ruleSupports=Set(rules.flatMap(\.supportIDs))
        let eligible=episodes.filter{ruleSupports.contains($0.id)}.sorted{a,b in
            let left=LearningText.tokens(a.question.text).intersection(tokens).count,right=LearningText.tokens(b.question.text).intersection(tokens).count
            return left==right ? a.id.uuidString<b.id.uuidString:left>right
        }
        if let example=eligible.first{
            result.examples=[LearningExample(sourceID:example.reply.id,text:LearningText.bounded(example.reply.text,350))]
        }
        var supports=Set<UUID>()
        for rule in rules{supports.formUnion(rule.supportIDs)}
        for episode in episodes where episode.signal.temporallyEligible && episode.signal.flags.allSatisfy({$0=="asr_confidence_unknown"}){
            let remote=episode.continuation
            guard remote.text.contains("?"),!LearningText.tokens(episode.question.text+" "+remote.text).isDisjoint(with:tokens) else{continue}
            if !result.preparation.contains(where:{$0.text==remote.text}){
                result.preparation.append(LearningExample(sourceID:remote.id,text:LearningText.bounded(remote.text,350)))
            }
            supports.insert(episode.id);if result.preparation.count==2{break}
        }
        result.supportIDs=Array(supports).sorted{$0.uuidString<$1.uuidString}
        let used=episodes.filter{supports.contains($0.id)}
        result.sourceRecordIDs=Set(used.compactMap(\.recordID));result.expiresAt=used.compactMap(\.expiresAt).min()
        result.bound();return result
    }
}
