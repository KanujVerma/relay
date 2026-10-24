import Foundation

public struct LearningRule:Codable,Equatable,Sendable,Identifiable {
    public let id:String,scope:LearningScope,adjustment:LearningAdjustment
    public let supportIDs:[UUID],sessionCount:Int,expiresAt:TimeInterval?,suppressed:Bool
    public var label:String{adjustment.label}
    public var why:String{suppressed ? "Undone. Existing examples cannot reactivate this adjustment.":"Tentative: \(supportIDs.count) possible-uptake examples across \(sessionCount) saved sessions. Reading, correctness and outcomes are unknown."}
}
public struct LearningArchive:Equatable,Sendable {
    public let episodes:[LearningEpisode],rules:[LearningRule]
    public let control:LearningControlRecord?
    private let withinCapacity:Bool,structurallyValid:Bool
    /// Construct on the owned store/reflection path, outside live requests.
    /// This cache validates data shape/derivation, never retained-source rights.
    public init(episodes:[LearningEpisode]=[],rules:[LearningRule]=[],control:LearningControlRecord?=nil){
        self.episodes=episodes;self.rules=rules;self.control=control
        withinCapacity=episodes.count<=LearningBounds.episodes && rules.count<=LearningBounds.rules
            && ((try? HistoryJSON.encode(episodes).count) ?? Int.max)<=LearningBounds.retainedBytes
        let validControl=control.map{(try? $0.validate()) != nil && ($0.enabled || episodes.isEmpty)} ?? true
        structurallyValid=withinCapacity && validControl && Set(episodes.map(\.id)).count==episodes.count && Set(rules.map(\.id)).count==rules.count
            && (try? LearningDerivation.rebuild(episodes,suppressed:control?.suppressedRuleIDs ?? Set(rules.filter(\.suppressed).map(\.id))))==rules
    }
    func validate()throws{
        guard withinCapacity else{throw HistoryError.capacity}
        guard structurallyValid else{throw HistoryError.invalid}
    }
}
public enum LearningMutation:Sendable {case save(LearningEpisode),suppress(String),reset,control(LearningPendingControl)}
public struct LearningExample:Equatable,Sendable {
    public let sourceID:String,text:String,excerpt:Bool
    init(sourceID:String,text:String,bytes:Int=350){self.sourceID=sourceID;self.text=LearningText.bounded(text,bytes);excerpt=text.utf8.count>bytes}
    var wire:[String:Any]{["sourceID":sourceID,"text":text,"excerpt":excerpt]}
}
public struct LearningRequestProjection:Sendable {
    public let scope:LearningScope
    public internal(set) var evidenceGap=false
    public internal(set) var continuity:[LearningQuote]=[],adjustments:[LearningAdjustment]=[],preparation:[LearningExample]=[],examples:[LearningExample]=[]
    public internal(set) var interactions:[LearningInteractionProjection]=[]
    public internal(set) var supportIDs:[UUID]=[]
    public internal(set) var sourceRecordIDs:Set<UUID>=[]
    public internal(set) var expiresAt:TimeInterval?
    var cohortSupportIDs:Set<UUID>=[],supportEpisodes:[LearningEpisode]=[]
    public var isEmpty:Bool{continuity.isEmpty && interactions.isEmpty && adjustments.isEmpty && preparation.isEmpty && examples.isEmpty && !evidenceGap}
    public func encodedPayload()throws->Data{
        let value:[String:Any]=["scope":scope.rawValue,"evidenceGap":evidenceGap,"continuity":continuity.map(\.wire),"interactions":interactions.map(\.wire),"adjustments":adjustments.map(\.rawValue),"preparation":preparation.map(\.wire),"examples":examples.map(\.wire),"supportIDs":supportIDs.map{$0.uuidString.lowercased()}]
        let data=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
        guard data.count<=LearningBounds.projectionBytes,continuity.count<=2,interactions.count<=1,adjustments.count<=2,preparation.count<=2,examples.count<=2,supportIDs.count<=8 else{throw HistoryError.capacity}
        return data
    }
    mutating func bound(){
        continuity=Array(continuity.prefix(2));interactions=Array(interactions.prefix(1));adjustments=Array(adjustments.prefix(2));preparation=Array(preparation.prefix(2));examples=Array(examples.prefix(2));refreshDependencies()
        while (try? encodedPayload())==nil{
            if !examples.isEmpty{examples.removeLast()}
            else if !preparation.isEmpty{preparation.removeLast()}
            else if continuity.count>1{continuity.removeLast();evidenceGap=true}
            else if !interactions.isEmpty{interactions=[];evidenceGap=true}
            else if !continuity.isEmpty{continuity.removeLast();evidenceGap=true}
            else{supportIDs=[];adjustments=[];break}
            refreshDependencies()
        }
    }
    private mutating func refreshDependencies(){
        var needed=adjustments.isEmpty ? Set<UUID>():cohortSupportIDs
        for episode in supportEpisodes where examples.contains(where:{$0.sourceID==episode.reply.id})
            || preparation.contains(where:{$0.sourceID==episode.continuation.id}) || interactions.contains(where:{$0.episodeID==episode.id}){needed.insert(episode.id)}
        supportIDs=needed.sorted{$0.uuidString<$1.uuidString}
        let used=supportEpisodes.filter{needed.contains($0.id)}
        sourceRecordIDs=Set(used.compactMap(\.recordID));expiresAt=used.compactMap(\.expiresAt).min()
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
        let ranked=episodes.sorted{a,b in
            let left=LearningText.tokens(a.question.text).intersection(tokens).count,right=LearningText.tokens(b.question.text).intersection(tokens).count
            return left==right ? a.id.uuidString<b.id.uuidString:left>right
        }
        var cohort:Set<UUID>=[]
        for rule in archive.rules where !rule.suppressed && rule.scope==scope{
            let candidates=ranked.filter{rule.supportIDs.contains($0.id)}
            guard candidates.count>=3,let first=candidates.first,
                  let second=candidates.first(where:{$0.recordID != first.recordID}),
                  let third=candidates.first(where:{$0.id != first.id && $0.id != second.id}) else{continue}
            cohort.formUnion([first.id,second.id,third.id]);result.adjustments.append(rule.adjustment)
            if result.adjustments.count==2{break}
        }
        result.cohortSupportIDs=cohort
        let eligible=ranked.filter{cohort.contains($0.id)}
        if let example=eligible.first{
            result.examples=[LearningExample(sourceID:example.reply.id,text:example.reply.text)]
        }
        var preparationSupport:Set<UUID>=[]
        for episode in ranked where episode.signal.temporallyEligible && episode.signal.flags.allSatisfy({$0=="asr_confidence_unknown"}){
            let remote=episode.continuation
            guard remote.text.contains("?"),!LearningText.tokens(episode.question.text+" "+remote.text).isDisjoint(with:tokens) else{continue}
            if !result.preparation.contains(where:{$0.text==remote.text}){
                result.preparation.append(LearningExample(sourceID:remote.id,text:remote.text));preparationSupport.insert(episode.id)
            }
            if result.preparation.count==2{break}
        }
        let needed=cohort.union(preparationSupport)
        result.supportEpisodes=ranked.filter{needed.contains($0.id)}
        if let episode=result.supportEpisodes.first(where:{!LearningText.tokens($0.question.text+" "+$0.continuation.text).isDisjoint(with:tokens)}){result.interactions=[LearningInteractionProjection(episode)]}
        result.bound();return result
    }
}
