import Foundation
import CryptoKit
import RelayContextComposition

public enum LearningBounds {
    public static let liveEpisodes=8,liveBytes=32*1024,quotes=16,quoteBytes=4096
    public static let episodes=100,retainedBytes=1024*1024,rules=32,projectionBytes=2048
}
public enum LearningScope:String,Codable,Sendable,CaseIterable {
    case technical,recruiter,other
    public static func matching(_ question:String)->Self{
        let words=LearningText.tokens(question)
        if !words.isDisjoint(with:["code","coding","sql","python","algorithm","queue","queues","query","database","system","design","function","latency","retention","join","nulls"]){return .technical}
        if !words.isDisjoint(with:["recruiter","career","background","yourself","interview","experience","project","team","strength","weakness"]){return .recruiter}
        return .other
    }
}
public enum LearningAdjustment:String,Codable,Sendable,CaseIterable {
    case conciseLead="concise_lead",stepwise,exampleFirst="example_first"
    public var label:String{switch self{case .conciseLead:"Short answer, then one reason";case .stepwise:"Explain in short steps";case .exampleFirst:"Start with a relevant example"}}
}
public enum LearningQuoteKind:String,Codable,Sendable {case spokenConstraint="spoken_constraint",unresolvedFollowup="unresolved_followup",interaction}
public struct LearningQuote:Codable,Equatable,Sendable {
    public let sourceID:String,captureID:String,text:String
    public let source:TranscriptSource,kind:LearningQuoteKind
    public let start:HistoryCounter,end:HistoryCounter
    init(_ final:HistoryFinal,kind:LearningQuoteKind,text:String?=nil){
        sourceID=final.id;captureID=final.captureID;source=final.source;start=final.startUptimeNanoseconds;end=final.endUptimeNanoseconds
        self.kind=kind;self.text=LearningText.bounded(text ?? final.text,700)
    }
    func validate()throws{
        guard !sourceID.isEmpty,sourceID.utf8.count<=180,!captureID.isEmpty,captureID.utf8.count<=80,
              start.value<=end.value,LearningText.valid(text,700) else{throw HistoryError.invalid}
    }
    var wire:[String:Any]{["sourceID":sourceID,"kind":kind.rawValue,"text":text]}
}
/// This records availability, never attention. Construction remains inside the
/// native learner called by the Model's drained current-card publication seam.
public struct LearningAvailableSuggestion:Codable,Equatable,Sendable {
    public let requestID:UUID,captureSessionID:UUID
    public let sessionEpoch:HistoryCounter,presentationGeneration:HistoryCounter,eventSequence:HistoryCounter,replacement:HistoryCounter,availableAt:HistoryCounter
    public let cardHash:String,text:String,guideRevision:UUID?
    public let windowVisible:Bool
    init(binding:PanelRequestBinding,replacement:UInt64,text:String,guideRevision:UUID?,visible:Bool,at:UInt64){
        requestID=binding.requestID;captureSessionID=binding.lease.captureSessionID;sessionEpoch=HistoryCounter(binding.lease.sessionEpoch)
        presentationGeneration=HistoryCounter(binding.lease.presentationGeneration);eventSequence=HistoryCounter(binding.eventSequence)
        self.replacement=HistoryCounter(replacement);availableAt=HistoryCounter(at);self.text=text;self.guideRevision=guideRevision;windowVisible=visible
        cardHash=SHA256.hash(data:Data(text.utf8)).map{String(format:"%02x",$0)}.joined()
    }
    func validate()throws{
        guard sessionEpoch.value>0,presentationGeneration.value>0,eventSequence.value>0,replacement.value>0,
              LearningText.valid(text,1024),cardHash==SHA256.hash(data:Data(text.utf8)).map({String(format:"%02x",$0)}).joined() else{throw HistoryError.invalid}
    }
}
public struct LearningSignal:Codable,Equatable,Sendable {
    public let temporallyEligible:Bool,possibleUptake:Bool,distinctiveOverlap:Int
    public let flags:[String]
    public var eligibleForStyle:Bool{temporallyEligible && possibleUptake && flags.allSatisfy{$0=="asr_confidence_unknown"}}
}
public struct LearningEpisode:Codable,Equatable,Sendable,Identifiable {
    public var id:UUID{suggestion.requestID}
    public let suggestion:LearningAvailableSuggestion
    public let question:HistoryFinal,reply:HistoryFinal,continuation:HistoryFinal
    public let scope:LearningScope,signal:LearningSignal
    public private(set) var recordID:UUID?
    public private(set) var expiresAt:TimeInterval?
    init(suggestion:LearningAvailableSuggestion,question:HistoryFinal,reply:HistoryFinal,continuation:HistoryFinal,flags:[String]){
        self.suggestion=suggestion;self.question=question;self.reply=reply;self.continuation=continuation;scope=LearningScope.matching(question.text)
        var observedFlags=Set(flags)
        if !suggestion.windowVisible{observedFlags.insert("hidden_card")}
        if reply.startUptimeNanoseconds.value<suggestion.availableAt.value{observedFlags.insert("speech_before_available")}
        if continuation.startUptimeNanoseconds.value<reply.endUptimeNanoseconds.value{observedFlags.insert("overlap")}
        if LearningText.words(reply.text)==LearningText.words(question.text) || LearningText.words(reply.text)==LearningText.words(continuation.text){observedFlags.insert("possible_echo")}
        for source in [question,reply,continuation]{
            if let wire=try? JSONSerialization.jsonObject(with:source.originalEventJSON) as? [String:Any],
               let payload=wire["payload"] as? [String:Any],let inner=payload["event"] as? [String:Any]{
                if inner["confidence"] is NSNull{observedFlags.insert("asr_confidence_unknown")}
                else if let confidence=inner["confidence"] as? NSNumber,confidence.intValue==0{observedFlags.insert("asr_uncertain")}
            }
        }
        let questionWire=(try? JSONSerialization.jsonObject(with:question.originalEventJSON)) as? [String:Any]
        let emitted=(questionWire?["emittedUptimeNanoseconds"] as? NSNumber)?.uint64Value ?? UInt64.max
        let overlap=LearningText.tokens(suggestion.text).intersection(LearningText.tokens(reply.text)).count
        let eligible=question.endUptimeNanoseconds.value<=suggestion.availableAt.value
            && emitted<=suggestion.availableAt.value
            && reply.startUptimeNanoseconds.value>=suggestion.availableAt.value
            && continuation.startUptimeNanoseconds.value>=reply.endUptimeNanoseconds.value
            && continuation.endUptimeNanoseconds.value>=suggestion.availableAt.value
            && continuation.endUptimeNanoseconds.value-suggestion.availableAt.value<=120_000_000_000
        signal=LearningSignal(temporallyEligible:eligible,possibleUptake:eligible && overlap>=2,distinctiveOverlap:overlap,flags:observedFlags.sorted())
    }
    public func retained(recordID:UUID,expiresAt:TimeInterval)throws->LearningEpisode{
        guard expiresAt.isFinite else{throw HistoryError.invalid};var value=self;value.recordID=recordID;value.expiresAt=expiresAt;try value.validate();return value
    }
    func validate()throws{
        try suggestion.validate();try question.validate();try reply.validate();try continuation.validate()
        guard question.source == .selectedAppAudio,reply.source == .microphone,continuation.source == .selectedAppAudio,
              question.captureSessionID==suggestion.captureSessionID,question.captureID==reply.captureID,reply.captureID==continuation.captureID,
              question.sessionEpoch==suggestion.sessionEpoch,question.eventSequence==suggestion.eventSequence,
              Set([question.id,reply.id,continuation.id]).count==3,signal.distinctiveOverlap>=0,signal.distinctiveOverlap<=1024,
              Set(signal.flags).count==signal.flags.count,signal.flags.allSatisfy({["hidden_card","speech_before_available","overlap","possible_echo","asr_confidence_unknown","asr_uncertain","late_final","remote_before_reply_final","competing_card"].contains($0)}),
              (recordID==nil)==(expiresAt==nil),expiresAt.map({$0.isFinite}) ?? true else{throw HistoryError.invalid}
        let rebuilt=LearningEpisode(suggestion:suggestion,question:question,reply:reply,continuation:continuation,flags:signal.flags)
        guard rebuilt.signal==signal,scope==rebuilt.scope else{throw HistoryError.invalid}
    }
    public var adjustments:[LearningAdjustment]{
        guard signal.eligibleForStyle else{return []}
        let spoken=reply.text.lowercased(),spokenWords=LearningText.words(spoken),suggestedWords=LearningText.words(suggestion.text)
        var values:[LearningAdjustment]=[]
        if spokenWords.count>=6,spokenWords.count*4<=suggestedWords.count*3{values.append(.conciseLead)}
        if ["first","then","finally","next"].filter({spokenWords.contains($0)}).count>=2{values.append(.stepwise)}
        if spoken.hasPrefix("for example") || spoken.hasPrefix("an example"){values.append(.exampleFirst)}
        return values
    }
}
enum LearningText {
    static let stop:Set<String>=["about","after","also","before","could","does","every","from","have","into","just","only","should","that","their","then","there","these","they","this","those","through","what","when","where","which","with","would"]
    static func words(_ text:String)->[String]{text.lowercased().components(separatedBy:CharacterSet.alphanumerics.inverted).filter{!$0.isEmpty}}
    static func tokens(_ text:String)->Set<String>{Set(words(text).filter{$0.count>=4 && !stop.contains($0)})}
    static func bounded(_ text:String,_ bytes:Int)->String{var result="",size=0;for scalar in text.unicodeScalars{let n=scalar.utf8.count;guard size+n<=bytes else{break};result.unicodeScalars.append(scalar);size+=n};return result}
    static func valid(_ text:String,_ limit:Int)->Bool{!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && text.utf8.count<=limit && !text.unicodeScalars.contains{disallowedTextScalar($0,code:true)}}
}
