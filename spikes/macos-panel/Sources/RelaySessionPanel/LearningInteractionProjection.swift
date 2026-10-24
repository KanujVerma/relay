import Foundation

public struct LearningProjectedSpeech:Sendable {
    public let sourceID:String,text:String,excerpt:Bool
    init(_ original:HistoryFinal,bytes:Int){sourceID=original.id;text=LearningText.bounded(original.text,bytes);excerpt=original.text.utf8.count>bytes}
    var wire:[String:Any]{["sourceID":sourceID,"text":text,"excerpt":excerpt]}
}
public struct LearningProjectedSuggestion:Sendable {
    public let requestID:UUID,cardHash:String,text:String,excerpt:Bool
    public let replacement:HistoryCounter,availableAt:HistoryCounter,windowVisible:Bool,guideRevision:UUID?
    init(_ original:LearningAvailableSuggestion){
        requestID=original.requestID;cardHash=original.cardHash;replacement=original.replacement;availableAt=original.availableAt
        text=LearningText.bounded(original.text,160);windowVisible=original.windowVisible;guideRevision=original.guideRevision
        // Full detail is retained for identity, never as exposed uptake text.
        excerpt=original.text.utf8.count>160 || original.detail != nil
    }
    var wire:[String:Any]{["requestID":requestID.uuidString.lowercased(),"cardHash":cardHash,"replacement":replacement.value,"text":text,
        "availableAt":availableAt.value,"windowVisible":windowVisible,"guideRevision":guideRevision.map{$0.uuidString.lowercased() as Any} ?? NSNull(),"excerpt":excerpt]}
}
/// Distinct inert records. No assistant/remote text can masquerade as a quote
/// from the microphone; no record claims attention, skill or an outcome.
public struct LearningInteractionProjection:Sendable {
    public let episodeID:UUID,question:LearningProjectedSpeech,suggestion:LearningProjectedSuggestion,reply:LearningProjectedSpeech,continuation:LearningProjectedSpeech
    public let signal:LearningSignal
    init(_ episode:LearningEpisode){
        episodeID=episode.id;question=LearningProjectedSpeech(episode.question,bytes:120);suggestion=LearningProjectedSuggestion(episode.suggestion)
        reply=LearningProjectedSpeech(episode.reply,bytes:160);continuation=LearningProjectedSpeech(episode.continuation,bytes:120);signal=episode.signal
    }
    var wire:[String:Any]{["episodeID":episodeID.uuidString.lowercased(),"question":question.wire,"suggestion":suggestion.wire,"reply":reply.wire,"continuation":continuation.wire,
        "temporallyEligible":signal.temporallyEligible,"possibleUptake":signal.possibleUptake,"distinctiveOverlap":signal.distinctiveOverlap,"ambiguity":signal.flags]}
}
