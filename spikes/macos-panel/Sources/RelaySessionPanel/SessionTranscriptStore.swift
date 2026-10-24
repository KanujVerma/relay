import Combine
import Foundation
import RelayNativeSession

public enum TranscriptSource:UInt32,Sendable {case microphone=1,selectedAppAudio=2
    public var label:String{self == .microphone ? "Microphone":"Selected app audio"}
}
public enum SessionActivityPhase:Sendable {case idle,listening,paused,unavailable}
public enum SourceActivity:Sendable {case silent,speechDetected,transcribing,unavailable}
public struct SessionTranscriptRow:Identifiable,Sendable,Equatable {
    public let id:String
    public let activityID:UInt64
    public let source:TranscriptSource
    public let startUptimeNanoseconds:UInt64
    public let endUptimeNanoseconds:UInt64
    public let text:String
}
public struct SessionActivitySnapshot:Sendable,Equatable {
    public fileprivate(set) var sessionID:UUID?
    public fileprivate(set) var revision:UInt64=0
    public fileprivate(set) var phase:SessionActivityPhase = .idle
    public fileprivate(set) var rows:[SessionTranscriptRow]=[]
    public fileprivate(set) var omittedRowCount:UInt64=0
    public fileprivate(set) var microphone:SourceActivity = .silent
    public fileprivate(set) var selectedAudio:SourceActivity = .silent
}

/// Bounded ephemeral read view of original native finals. Never authorizes an
/// answer, infers a speaker, persists a transcript or changes personal memory.
@MainActor public final class SessionTranscriptStore:ObservableObject {
    @Published public private(set) var snapshot=SessionActivitySnapshot()
    private struct Activity {let start:[String:WireValue];var end:[String:WireValue]?}
    private var activities:[String:Activity]=[:]
    private var epoch:UInt64=0;private var sequence:UInt64=0;private var sealed=true
    private var bytes=0
    public init(){}
    public func pause(){sealed=true;activities.removeAll();snapshot.phase = .paused;changed()}
    public func end(){sealed=true;activities.removeAll();snapshot.rows=[];bytes=0;snapshot.omittedRowCount=0;snapshot.phase = .idle;changed()}
    private func changed(){snapshot.revision &+= 1}
    private func activity(_ source:TranscriptSource,_ state:SourceActivity){
        if source == .microphone{snapshot.microphone=state}else{snapshot.selectedAudio=state}
    }
    private func purge(_ source:TranscriptSource){
        snapshot.rows.removeAll{$0.source==source};bytes=snapshot.rows.reduce(0){$0+$1.text.utf8.count}
    }
    public func observe(_ event:NativeSessionEvent) {
        if event.kind == .sessionStarted {
            guard event.eventSequence==1,event.sessionEpoch>0,event.captureSessionID != snapshot.sessionID else{return}
            snapshot=SessionActivitySnapshot(sessionID:event.captureSessionID,phase:.listening)
            epoch=event.sessionEpoch;sequence=1;sealed=false;activities.removeAll();bytes=0;changed();return
        }
        guard snapshot.sessionID==event.captureSessionID,epoch==event.sessionEpoch,event.eventSequence>sequence else{return}
        if sealed {
            // Preserve the original scope/high-water mark while ignoring late
            // additions. Denial-only privacy removal still applies after Pause.
            sequence=event.eventSequence
            guard [.sourceUnavailable,.discontinuity].contains(event.kind),
                  let code=event.sourceCode,let source=TranscriptSource(rawValue:code),event.streamGeneration != nil,
                  event.payload==["reasonCode":.string("consent_revoked")] else{return}
            purge(source);activity(source,.unavailable);changed();return
        }
        guard sequence<UInt64.max,event.eventSequence==sequence+1 else{
            activities.removeAll();snapshot.phase = .unavailable;sealed=true;changed();return
        }
        sequence=event.eventSequence
        if [.stopping,.stopped].contains(event.kind){end();return}
        guard let code=event.sourceCode,let source=TranscriptSource(rawValue:code),let generation=event.streamGeneration else{return}
        let p=event.payload
        if [.sourceUnavailable,.discontinuity].contains(event.kind){
            activities=activities.filter{!$0.key.hasPrefix("\(code):")};activity(source,.unavailable)
            if p["reasonCode"] == .string("consent_revoked") {
                purge(source)
            }
            changed();return
        }
        guard let id=number(p["activityID"]) else{return}
        let key="\(code):\(generation):\(id)"
        switch event.kind {
        case .speechStarted:
            guard activities[key]==nil,activities.count<64,number(p["startHostTime"]) != nil else{return}
            activities[key]=Activity(start:p);activity(source,.speechDetected);changed()
        case .speechEnded:
            guard var original=activities[key],original.end==nil else{return}
            original.end=p;activities[key]=original;activity(source,.transcribing);changed()
        case .eou:
            guard let original=activities.removeValue(forKey:key),let end=original.end,
                  let row=validated(event,source:source,generation:generation,id:id,original:original.start,end:end) else{return}
            guard !snapshot.rows.contains(where:{$0.id==row.id}) else{return}
            snapshot.rows.append(row);snapshot.rows.sort{($0.startUptimeNanoseconds,$0.id)<($1.startUptimeNanoseconds,$1.id)}
            bytes+=row.text.utf8.count
            while snapshot.rows.count>64 || bytes>65_536 {
                bytes-=snapshot.rows.removeFirst().text.utf8.count;snapshot.omittedRowCount &+= 1
            }
            activity(source,.silent);changed()
        default:break
        }
    }
    private func number(_ value:WireValue?)->UInt64?{if case .uint(let value)=value{return value};return nil}
    private func validated(_ event:NativeSessionEvent,source:TranscriptSource,generation:UInt64,id:UInt64,
                           original:[String:WireValue],end:[String:WireValue])->SessionTranscriptRow? {
        let p=event.payload
        guard Set(p.keys)==["event","activityID","firstInputSequence","lastInputSequence","activityClosed","lastSpeechInputSequence"],
              Set(original.keys)==["activityID","startHostTime","detectedUptimeNanoseconds","timebase"],
              Set(end.keys)==["activityID","endHostTime","lastSpeechInputSequence","timebase"],
              case .object(let inner)=p["event"],
              Set(inner.keys)==["version","status","sourceCode","streamGeneration","segmentID","revision","startHostTime","endHostTime",
                "finalizedUptimeNanoseconds","receivedUptimeNanoseconds","text","confidence","timebase"],
              inner["confidence"] == .null || number(inner["confidence"]).map({$0<=1}) == true,
              p["activityClosed"] == .bool(true),
              p["lastInputSequence"]==p["lastSpeechInputSequence"],p["lastInputSequence"]==end["lastSpeechInputSequence"],
              let first=number(p["firstInputSequence"]),let last=number(p["lastInputSequence"]),first<=last,
              inner["version"] == .uint(1),inner["status"] == .string("final"),inner["sourceCode"] == .uint(UInt64(source.rawValue)),
              inner["streamGeneration"] == .uint(generation),inner["revision"] == .uint(1),
              let segment=number(inner["segmentID"]),segment>0,
              inner["startHostTime"]==original["startHostTime"],inner["endHostTime"]==end["endHostTime"],
              inner["timebase"]==original["timebase"],inner["timebase"]==end["timebase"],
              case .string(let text)=inner["text"],!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              text.unicodeScalars.count<=1200,text.utf8.count<=4800,!text.contains("\0"),
              case .object(let clock)=inner["timebase"],Set(clock.keys)==["hostTicksAtAnchor","uptimeNsAtAnchor","nsNumer","nsDenom"],
              let ticks=number(clock["hostTicksAtAnchor"]),
              let uptime=number(clock["uptimeNsAtAnchor"]),let numer=number(clock["nsNumer"]),let denom=number(clock["nsDenom"]),
              let start=number(inner["startHostTime"]),let finish=number(inner["endHostTime"]),
              let finalized=number(inner["finalizedUptimeNanoseconds"]),let received=number(inner["receivedUptimeNanoseconds"]) else{return nil}
        let calibration=NativeClockCalibration(hostTicksAtAnchor:ticks,uptimeNsAtAnchor:uptime,nsNumer:numer,nsDenom:denom)
        guard let startNs=try? calibration.uptimeNanoseconds(forHostTicks:start),
              let endNs=try? calibration.uptimeNanoseconds(forHostTicks:finish),startNs<=endNs,
              endNs<=finalized,finalized<=received,received<=event.emittedUptimeNanoseconds,
              endNs-startNs<=120_000_000_000,finalized-endNs<=30_000_000_000,
              (finalized>=uptime ? finalized-uptime:uptime-finalized)<=600_000_000_000 else{return nil}
        return SessionTranscriptRow(id:"\(event.captureSessionID):\(source.rawValue):\(generation):\(segment)",
            activityID:id,source:source,startUptimeNanoseconds:startNs,endUptimeNanoseconds:endNs,text:text)
    }
}
