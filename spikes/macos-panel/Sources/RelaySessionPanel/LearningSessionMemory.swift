import Foundation
import RelayNativeSession
import RelayContextComposition

/// Ephemeral source data only. No IO, model calls, biography or native request
/// authority. The original validated observer and Model own the two producers.
@MainActor public final class LearningSessionMemory {
    public private(set) var episodes:[LearningEpisode]=[]
    public private(set) var evidenceGap=false
    public var onEpisode:(@MainActor (LearningEpisode)->Void)?
    private var scope:(UUID,UInt64)?,sealed=true
    private var finals:[HistoryFinal]=[],quotes:[LearningQuote]=[]
    private struct Pending {let available:LearningAvailableSuggestion,question:HistoryFinal;var reply:HistoryFinal?;var flags:[String]}
    private var pending:Pending?
    private var issued:Set<UUID>=[]
    public init(){}
    public func pause(){sealed=true;pending=nil;finals=[]}
    public func end(){scope=nil;sealed=true;pending=nil;finals=[];quotes=[];episodes=[];issued=[];evidenceGap=false}
    public func removeSource(captureID:String,source:TranscriptSource){
        pending=nil;finals.removeAll{$0.captureID==captureID && $0.source==source}
        quotes.removeAll{$0.captureID==captureID && $0.source==source}
        episodes.removeAll{episode in [episode.question,episode.reply,episode.continuation].contains{$0.captureID==captureID && $0.source==source}}
        evidenceGap=true
    }
    public func observe(_ observation:ValidatedTranscriptObservation){
        let event=observation.event
        if event.kind == .sessionStarted{
            guard event.eventSequence==1,event.sessionEpoch>0 else{return}
            // A resumed capture keeps inert meeting quotes, never old admission.
            scope=(event.captureSessionID,event.sessionEpoch);sealed=false;pending=nil;finals=[];issued=[];return
        }
        guard let scope,scope.0==event.captureSessionID,scope.1==event.sessionEpoch else{return}
        if observation.sequenceGap{pending=nil;sealed=true;evidenceGap=true;return}
        if [.sourceUnavailable,.discontinuity].contains(event.kind){
            pending=nil;evidenceGap=true
            if event.payload["reasonCode"] == .string("consent_revoked"),let code=event.sourceCode,let source=TranscriptSource(rawValue:code){removeSource(captureID:HistoryCapture.identity(scope.0,scope.1),source:source)}
            return
        }
        if [.stopping,.stopped].contains(event.kind){pause();return}
        guard !sealed,let final=observation.final else{return}
        guard !finals.contains(where:{$0.id==final.id}) else{return}
        let late=finals.contains{$0.endUptimeNanoseconds.value>final.endUptimeNanoseconds.value}
        finals.append(final)
        while finals.count>64 || finals.reduce(0,{$0+$1.text.utf8.count})>32*1024{finals.removeFirst();evidenceGap=true}
        let lower=final.text.lowercased()
        let unresolved=["still need","need to clarify","unresolved","what about","clarify","not yet","follow up","follow-up"].contains{lower.contains($0)}
        let constraint=["decided","agreed","must","require","constraint","assume","only","will use","we chose","let's use"].contains{lower.contains($0)}
        if unresolved || constraint{
            quotes.append(LearningQuote(final,kind:unresolved ? .unresolvedFollowup:.spokenConstraint))
            while quotes.count>LearningBounds.quotes || quotes.reduce(0,{$0+$1.text.utf8.count})>LearningBounds.quoteBytes{quotes.removeFirst();evidenceGap=true}
        }
        guard var original=pending else{return}
        if late{original.flags.append("late_final")}
        if final.id==original.question.id{return}
        if final.source == .microphone{
            if original.reply != nil{original.flags.append("overlap")}
            if final.startUptimeNanoseconds.value<original.available.availableAt.value{original.flags.append("speech_before_available")}
            original.reply=final;pending=original;return
        }
        guard let reply=original.reply else{original.flags.append("remote_before_reply_final");pending=original;return}
        if final.startUptimeNanoseconds.value<reply.endUptimeNanoseconds.value{original.flags.append("overlap")}
        if LearningText.words(reply.text)==LearningText.words(original.question.text) || LearningText.words(reply.text)==LearningText.words(final.text){original.flags.append("possible_echo")}
        var flags=original.flags
        for source in [original.question,reply,final]{
            if let wire=try? JSONSerialization.jsonObject(with:source.originalEventJSON) as? [String:Any],
               let payload=wire["payload"] as? [String:Any],let inner=payload["event"] as? [String:Any]{
                if inner["confidence"] is NSNull{flags.append("asr_confidence_unknown")}
                else if let confidence=inner["confidence"] as? NSNumber,confidence.intValue==0{flags.append("asr_uncertain")}
            }
        }
        let episode=LearningEpisode(suggestion:original.available,question:original.question,reply:reply,continuation:final,flags:Array(Set(flags)).sorted())
        pending=nil
        guard (try? episode.validate()) != nil else{evidenceGap=true;return}
        episodes.append(episode)
        while episodes.count>LearningBounds.liveEpisodes || ((try? HistoryJSON.encode(episodes).count) ?? Int.max)>LearningBounds.liveBytes{episodes.removeFirst();evidenceGap=true}
        onEpisode?(episode)
    }
    public func available(binding:PanelRequestBinding,replacement:UInt64,lead:String,points:[String],guideRevision:UUID?,visible:Bool,at:UInt64){
        guard !sealed,let scope,scope.0==binding.lease.captureSessionID,scope.1==binding.lease.sessionEpoch,
              !issued.contains(binding.requestID),issued.count<512,
              let question=finals.last(where:{$0.source == .selectedAppAudio && $0.eventSequence.value==binding.eventSequence}),
              question.endUptimeNanoseconds.value<=at,
              let original=try? JSONSerialization.jsonObject(with:question.originalEventJSON) as? [String:Any],
              let emitted=original["emittedUptimeNanoseconds"] as? NSNumber,emitted.uint64Value<=at else{return}
        let text=([lead]+points).joined(separator:"\n")
        guard LearningText.valid(text,1024),replacement>0 else{return}
        issued.insert(binding.requestID)
        var flags=visible ? []:["hidden_card"]
        if pending != nil{evidenceGap=true;flags.append("competing_card")}
        pending=Pending(available:LearningAvailableSuggestion(binding:binding,replacement:replacement,text:text,guideRevision:guideRevision,visible:visible,at:at),question:question,flags:flags)
    }
    public func projection(question:String)->[LearningQuote]{
        let tokens=LearningText.tokens(question)
        let ranked=quotes.enumerated().filter{!LearningText.tokens($0.element.text).isDisjoint(with:tokens)}.sorted{a,b in
            let left=LearningText.tokens(a.element.text).intersection(tokens).count,right=LearningText.tokens(b.element.text).intersection(tokens).count
            return left==right ? a.offset>b.offset:left>right
        }
        var result=ranked.prefix(2).map(\.element)
        if result.count<2{
            let candidates=finals.enumerated().filter{!LearningText.tokens($0.element.text).isDisjoint(with:tokens)}.sorted{a,b in
                let left=LearningText.tokens(a.element.text).intersection(tokens).count,right=LearningText.tokens(b.element.text).intersection(tokens).count
                return left==right ? a.offset>b.offset:left>right
            }
            for candidate in candidates where !result.contains(where:{$0.sourceID==candidate.element.id}){
                result.append(LearningQuote(candidate.element,kind:.interaction));if result.count==2{break}
            }
        }
        if result.count<2{
            for episode in episodes.reversed() where !LearningText.tokens(episode.question.text).isDisjoint(with:tokens){
                let text="Original question: \(episode.question.text)\nActually spoken: \(episode.reply.text)\nRemote continuation, outcome unknown: \(episode.continuation.text)"
                result.append(LearningQuote(episode.reply,kind:.interaction,text:text));if result.count==2{break}
            }
        }
        return result
    }
}
