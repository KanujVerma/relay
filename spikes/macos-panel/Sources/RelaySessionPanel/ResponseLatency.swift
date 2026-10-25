import Foundation
import RelayNativeSession
import RelayContextComposition

/// Optional, descriptive helper telemetry. Invalid telemetry is discarded; it
/// cannot authorize or reject an otherwise valid answer decision.
public struct HelperDecisionTiming:Sendable,Equatable {
    public let helperReceivedAt:UInt64
    public let generationStartedAt:UInt64?
    public let transportStartedAt:UInt64?
    public let firstTextAt:UInt64?
    public let responseCompletedAt:UInt64?
    public let validationFinishedAt:UInt64?
    public let helperEmittedAt:UInt64
    public let transportOutcome:String?
    init(_ node:JSONNode)throws{
        let o=try node.object(["schemaVersion","helperReceivedUptimeNanoseconds","generationStartedUptimeNanoseconds",
            "transportStartedUptimeNanoseconds","firstTextUptimeNanoseconds","responseCompletedUptimeNanoseconds",
            "validationFinishedUptimeNanoseconds","helperEmittedUptimeNanoseconds","transportOutcome"])
        guard try o["schemaVersion"]!.uint()==1 else{throw PanelBridgeError.malformed}
        helperReceivedAt=try o["helperReceivedUptimeNanoseconds"]!.uint()
        helperEmittedAt=try o["helperEmittedUptimeNanoseconds"]!.uint()
        func optional(_ key:String)throws->UInt64?{o[key]!.isNull ? nil:try o[key]!.uint()}
        generationStartedAt=try optional("generationStartedUptimeNanoseconds")
        transportStartedAt=try optional("transportStartedUptimeNanoseconds")
        firstTextAt=try optional("firstTextUptimeNanoseconds")
        responseCompletedAt=try optional("responseCompletedUptimeNanoseconds")
        validationFinishedAt=try optional("validationFinishedUptimeNanoseconds")
        transportOutcome=o["transportOutcome"]!.isNull ? nil:try o["transportOutcome"]!.string(16)
        guard helperEmittedAt>=helperReceivedAt,helperEmittedAt-helperReceivedAt<=60_000_000_000,
            transportOutcome==nil || ["completed","failed","cancelled"].contains(transportOutcome!) else{throw PanelBridgeError.malformed}
        var prior=helperReceivedAt
        for mark in [generationStartedAt,transportStartedAt,firstTextAt,responseCompletedAt,validationFinishedAt].compactMap({$0}){
            guard mark>=prior,mark<=helperEmittedAt else{throw PanelBridgeError.malformed};prior=mark
        }
        guard transportStartedAt==nil || generationStartedAt != nil,
            firstTextAt==nil || transportOutcome != nil,
            responseCompletedAt==nil || transportOutcome != nil,
            transportOutcome != "completed" || responseCompletedAt != nil else{throw PanelBridgeError.malformed}
    }
}

/// Copies contain only original request IDs, stage times and fixed outcomes.
/// No transcript, answer, personal context, provider token or screen data.
public struct ResponseLatencySample:Sendable {
    public let requestID:UUID
    fileprivate let binding:PanelRequestBinding
    public fileprivate(set) var speechEndedAt:UInt64?
    public fileprivate(set) var endpointEmittedAt:UInt64?
    public fileprivate(set) var asrFinalizedAt:UInt64?
    public fileprivate(set) var nativeASRReceivedAt:UInt64?
    public fileprivate(set) var nativeEOUEmittedAt:UInt64?
    public fileprivate(set) var panelBoundAt:UInt64?
    /// Enqueued to the existing bounded native writer, not proof of pipe IO.
    public fileprivate(set) var helperForwardedAt:UInt64?
    public fileprivate(set) var helperFrameReceivedAt:UInt64?
    public fileprivate(set) var helper:HelperDecisionTiming?
    public fileprivate(set) var panelCommittedAt:UInt64?
    public fileprivate(set) var modelAvailableAt:UInt64?
    /// Observed visible, non-miniaturized window; never a paint/usefulness claim.
    public fileprivate(set) var windowVisibleAt:UInt64?
    public fileprivate(set) var retiredAt:UInt64?
    public fileprivate(set) var outcome="observed"
    public fileprivate(set) var answerKind:String?
    fileprivate var replacement:UInt64=0
    fileprivate init(_ binding:PanelRequestBinding){self.binding=binding;requestID=binding.requestID}
}

/// A bounded diagnostic join only. Product admission, currentness, visibility
/// receipts and publication never consult this recorder or its stored binding.
@MainActor public final class ResponseLatencyRecorder {
    public private(set) var samples:[ResponseLatencySample]=[]
    private var current:PanelRequestBinding?
    private var lastEnd:(session:UUID,epoch:UInt64,generation:UInt64?,activity:UInt64,at:UInt64)?
    public init(){}
    private func index(_ binding:PanelRequestBinding)->Int?{samples.firstIndex{$0.binding==binding}}
    private func ensure(_ binding:PanelRequestBinding)->Int{
        if let i=index(binding){return i}
        if samples.count==32{samples.removeFirst()}
        samples.append(ResponseLatencySample(binding));return samples.count-1
    }
    public func observeNative(_ event:NativeSessionEvent){
        guard event.sourceCode==2 else{return}
        if event.kind == .speechStarted{lastEnd=nil;return}
        if event.kind == .speechEnded,let activity=event.payload["activityID"]?.latencyUInt{
            lastEnd=(event.captureSessionID,event.sessionEpoch,event.streamGeneration,activity,event.emittedUptimeNanoseconds);return
        }
        guard let binding=PanelRequestBinding(event) else{return}
        let i=ensure(binding)
        samples[i].nativeEOUEmittedAt=event.emittedUptimeNanoseconds
        if let end=lastEnd,end.session==event.captureSessionID,end.epoch==event.sessionEpoch,
            end.generation==event.streamGeneration,end.activity==event.payload["activityID"]?.latencyUInt{
            samples[i].endpointEmittedAt=end.at
        }
        guard let inner=event.payload["event"]?.latencyObject else{return}
        samples[i].asrFinalizedAt=inner["finalizedUptimeNanoseconds"]?.latencyUInt
        samples[i].nativeASRReceivedAt=inner["receivedUptimeNanoseconds"]?.latencyUInt
        if let ticks=inner["endHostTime"]?.latencyUInt,let clock=inner["timebase"]?.latencyObject,
            let host=clock["hostTicksAtAnchor"]?.latencyUInt,let uptime=clock["uptimeNsAtAnchor"]?.latencyUInt,
            let numer=clock["nsNumer"]?.latencyUInt,let denom=clock["nsDenom"]?.latencyUInt{
            samples[i].speechEndedAt=try? NativeClockCalibration(hostTicksAtAnchor:host,uptimeNsAtAnchor:uptime,
                nsNumer:numer,nsDenom:denom).uptimeNanoseconds(forHostTicks:ticks)
        }
    }
    func begin(_ binding:PanelRequestBinding){
        if current != binding{retire(outcome:"retired")}
        current=binding;let i=ensure(binding)
        samples[i].panelBoundAt=DispatchTime.now().uptimeNanoseconds;samples[i].outcome="pending"
    }
    public func recordForwarded(binding:PanelRequestBinding,at:UInt64){
        guard current==binding,let i=index(binding),samples[i].helperForwardedAt==nil else{return}
        samples[i].helperForwardedAt=at
    }
    public func recordHelperReceived(binding:PanelRequestBinding,at:UInt64){
        guard current==binding,let i=index(binding),samples[i].helperFrameReceivedAt==nil else{return}
        samples[i].helperFrameReceivedAt=at
    }
    func accepted(_ decision:SessionAnswerDecision,binding:PanelRequestBinding,replacement:UInt64){
        guard current==binding,let i=index(binding) else{return}
        samples[i].helper=decision.timing;samples[i].outcome=decision.disposition;samples[i].replacement=replacement
        if decision.disposition != "pending"{
            let now=DispatchTime.now().uptimeNanoseconds
            if samples[i].helperFrameReceivedAt==nil{samples[i].helperFrameReceivedAt=now}
            samples[i].panelCommittedAt=now;samples[i].answerKind=decision.answerKind
        }
    }
    public func recordAvailable(binding:PanelRequestBinding,replacement:UInt64,availableAt:UInt64,visible:Bool){
        guard current==binding,let i=index(binding),samples[i].outcome=="answer",samples[i].replacement==replacement,
            let committed=samples[i].panelCommittedAt,availableAt>=committed,
            availableAt>=(samples[i].modelAvailableAt ?? committed) else{return}
        if samples[i].modelAvailableAt==nil{samples[i].modelAvailableAt=availableAt}
        if visible,samples[i].windowVisibleAt==nil{samples[i].windowVisibleAt=availableAt}
    }
    func retire(outcome:String){
        if let current,let i=index(current){
            samples[i].retiredAt=DispatchTime.now().uptimeNanoseconds
            if ["observed","pending"].contains(samples[i].outcome) || (samples[i].outcome=="answer" && samples[i].modelAvailableAt==nil){
                samples[i].outcome=outcome
            }
        }
        current=nil
    }
}

private extension WireValue {
    var latencyUInt:UInt64?{if case .uint(let n)=self{return n};return nil}
    var latencyObject:[String:WireValue]?{if case .object(let o)=self{return o};return nil}
}
