import Foundation
import RelayNativeSession

public enum HistoryError:Error,Sendable{case unavailable,missing,invalid,capacity,stale,closed,inUse}
public enum HistoryBounds {
    public static let snapshot=8*1024*1024,softSnapshot=7*1024*1024
    public static let records=100,rows=1024,text=256*1024,note=8*1024,title=120,captures=64
    public static let pending=128,pendingBytes=256*1024,pageRows=64,pageBytes=64*1024
    public static let retention:TimeInterval=30*24*60*60
}
/// SQLite INTEGER and JSON floating-point decoders cannot represent UInt64's
/// full domain. Stored/exported counters have one canonical decimal encoding.
public struct HistoryCounter:Sendable,Equatable,Codable,CustomStringConvertible {
    public let value:UInt64
    public init(_ value:UInt64){self.value=value}
    public var description:String{String(value)}
    public init(from decoder:any Decoder)throws{
        let c=try decoder.singleValueContainer(),s=try c.decode(String.self)
        guard let n=UInt64(s),String(n)==s else{throw HistoryError.invalid};value=n
    }
    public func encode(to encoder:any Encoder)throws{var c=encoder.singleValueContainer();try c.encode(description)}
    var sortBytes:Data{var n=value.bigEndian;return withUnsafeBytes(of:&n){Data($0)}}
}
public enum HistoryRecordState:String,Codable,Sendable{case recording,paused,completed,partial,interrupted}
public enum HistoryGap:String,Codable,Sendable,CaseIterable{
    case sourceUnavailable,sequenceGap,capacity,storageFailure,savingStopped,interrupted,captureFailure,sourceDeleted,invalidObservation,unfinishedSpeech,captureEndUnknown
    public var label:String{switch self{
    case .sourceUnavailable:"An audio source became unavailable"
    case .sequenceGap:"Some audio events were missing"
    case .capacity:"History reached its storage limit"
    case .storageFailure:"History could not save more text"
    case .savingStopped:"Saving was turned off"
    case .interrupted:"The session did not finish normally"
    case .captureFailure:"Audio did not finish normally"
    case .sourceDeleted:"Source text was deleted"
    case .invalidObservation:"A transcript observation was rejected"
    case .unfinishedSpeech:"Speech was still being processed when audio stopped"
    case .captureEndUnknown:"Capture cleanup end was not recorded"
    }}
}
public struct HistoryRecord:Sendable,Equatable,Codable,Identifiable {
    public let id:UUID
    public internal(set) var revision:Int64
    public let createdAt:TimeInterval
    public let expiresAt:TimeInterval
    public internal(set) var endedAt:TimeInterval?
    public internal(set) var state:HistoryRecordState
    public internal(set) var title:String
    public internal(set) var note:String
    public internal(set) var gaps:[HistoryGap]
    public internal(set) var blockedSources:[TranscriptSource]
    func validate()throws{
        guard revision>0,createdAt.isFinite,expiresAt.isFinite,expiresAt==createdAt+HistoryBounds.retention,
              endedAt.map({$0.isFinite}) ?? true,
              !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,title.utf8.count<=HistoryBounds.title,
              !title.unicodeScalars.contains(where:{disallowedTextScalar($0)}),note.utf8.count<=HistoryBounds.note,
              !note.unicodeScalars.contains(where:{disallowedTextScalar($0,code:true)}),
              Set(gaps).count==gaps.count,Set(blockedSources).count==blockedSources.count else{throw HistoryError.invalid}
        if state == .completed{guard gaps.isEmpty,endedAt != nil else{throw HistoryError.invalid}}
    }
}
public struct HistoryCapture:Sendable,Equatable,Codable,Identifiable {
    public let id:String
    public let captureSessionID:UUID
    public let sessionEpoch:HistoryCounter
    public let startedEventSequence:HistoryCounter
    public let startedUptimeNanoseconds:HistoryCounter
    public let observedWallTime:TimeInterval
    public private(set) var selectedBundleID:String?
    public private(set) var microphoneEnabled:Bool
    public private(set) var redactedSources:[TranscriptSource]
    public internal(set) var stop:HistoryCaptureStop?
    public var observedEndUptimeNanoseconds:HistoryCounter?{stop?.quiesced==true ? stop?.emittedUptimeNanoseconds:nil}
    init(_ event:NativeSessionEvent,now:TimeInterval)throws{
        guard event.kind == .sessionStarted,event.sessionEpoch>0,event.eventSequence==1,
              case .bool(let microphone)=event.payload["microphoneEnabled"] else{throw HistoryError.invalid}
        let bundle:String?
        switch event.payload["selectedBundleID"]{
        case .string(let s):guard !s.isEmpty,s.utf8.count<=180 else{throw HistoryError.invalid};bundle=s
        case .null:bundle=nil
        default:throw HistoryError.invalid
        }
        captureSessionID=event.captureSessionID;sessionEpoch=HistoryCounter(event.sessionEpoch)
        id=Self.identity(event.captureSessionID,event.sessionEpoch)
        startedEventSequence=HistoryCounter(event.eventSequence);startedUptimeNanoseconds=HistoryCounter(event.emittedUptimeNanoseconds)
        observedWallTime=now;selectedBundleID=bundle;microphoneEnabled=microphone;redactedSources=[];stop=nil
    }
    func redacting(_ sources:[TranscriptSource])->HistoryCapture{
        var c=self
        for source in sources{
            if source == .microphone{c.microphoneEnabled=false}else{c.selectedBundleID=nil}
            if !c.redactedSources.contains(source){c.redactedSources.append(source)}
        }
        return c
    }
    static func identity(_ session:UUID,_ epoch:UInt64)->String{session.uuidString.lowercased()+":"+String(epoch)}
    func validate()throws{
        guard id==Self.identity(captureSessionID,sessionEpoch.value),sessionEpoch.value>0,startedEventSequence.value==1,
              observedWallTime.isFinite,selectedBundleID.map({!$0.isEmpty && $0.utf8.count<=180}) ?? true,
              Set(redactedSources).count==redactedSources.count,
              !redactedSources.contains(.microphone) || !microphoneEnabled,
              !redactedSources.contains(.selectedAppAudio) || selectedBundleID==nil,
              microphoneEnabled || selectedBundleID != nil || !redactedSources.isEmpty else{throw HistoryError.invalid}
        try stop?.validate(for:self)
    }
}
public struct HistoryFinal:Sendable,Equatable,Codable,Identifiable {
    public let id:String
    public let captureSessionID:UUID
    public let sessionEpoch:HistoryCounter,eventSequence:HistoryCounter,streamGeneration:HistoryCounter
    public let activityID:HistoryCounter,segmentID:HistoryCounter,revision:HistoryCounter
    public let source:TranscriptSource
    public let startUptimeNanoseconds:HistoryCounter,endUptimeNanoseconds:HistoryCounter
    public let text:String
    /// Exact original native envelope, encrypted inside the snapshot. This is
    /// evidence for display/export, never a replayable request or answer lease.
    let originalEventJSON:Data
    var captureID:String{HistoryCapture.identity(captureSessionID,sessionEpoch.value)}
    init(_ event:NativeSessionEvent,row:SessionTranscriptRow)throws{
        guard let generation=event.streamGeneration,case .object(let inner)=event.payload["event"],
              case .uint(let segment)=inner["segmentID"],case .uint(let rev)=inner["revision"] else{throw HistoryError.invalid}
        captureSessionID=event.captureSessionID;sessionEpoch=HistoryCounter(event.sessionEpoch)
        eventSequence=HistoryCounter(event.eventSequence);streamGeneration=HistoryCounter(generation)
        activityID=HistoryCounter(row.activityID);segmentID=HistoryCounter(segment);revision=HistoryCounter(rev)
        source=row.source;startUptimeNanoseconds=HistoryCounter(row.startUptimeNanoseconds);endUptimeNanoseconds=HistoryCounter(row.endUptimeNanoseconds)
        text=row.text;id="\(event.captureSessionID.uuidString.lowercased()):\(event.sessionEpoch):\(source.rawValue):\(generation):\(segment)"
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];originalEventJSON=try encoder.encode(event)
        try validate()
    }
    func validate()throws{
        guard id=="\(captureSessionID.uuidString.lowercased()):\(sessionEpoch):\(source.rawValue):\(streamGeneration):\(segmentID)",
              sessionEpoch.value>0,eventSequence.value>1,streamGeneration.value>0,activityID.value>0,segmentID.value>0,revision.value==1,
              startUptimeNanoseconds.value<=endUptimeNanoseconds.value,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              text.unicodeScalars.count<=1200,text.utf8.count<=4800,!text.contains("\0") else{throw HistoryError.invalid}
        let o=try StrictJSON.decode(originalEventJSON).object(["schemaVersion","captureSessionID","sessionEpoch","eventSequence","presentationGeneration","kind","sourceCode","streamGeneration","emittedUptimeNanoseconds","payload","requestID"])
        func number(_ fields:[String:JSONNode],_ key:String)throws->UInt64{
            guard let value=fields[key] else{throw HistoryError.invalid};return try value.uint(false)
        }
        guard try number(o,"schemaVersion")==1,case .string(let uuid)=o["captureSessionID"],UUID(uuidString:uuid)==captureSessionID,
              try number(o,"sessionEpoch")==sessionEpoch.value,try number(o,"eventSequence")==eventSequence.value,
              try number(o,"sourceCode")==UInt64(source.rawValue),try number(o,"streamGeneration")==streamGeneration.value,
              case .string("eou")=o["kind"],let payloadNode=o["payload"] else{throw HistoryError.invalid}
        _=try number(o,"presentationGeneration")
        if let request=o["requestID"],!request.isNull{
            guard case .string(let id)=request,UUID(uuidString:id) != nil else{throw HistoryError.invalid}
        }
        let payload=try payloadNode.object(["event","activityID","firstInputSequence","lastInputSequence","activityClosed","lastSpeechInputSequence"])
        guard let innerNode=payload["event"],case .bool(true)=payload["activityClosed"],
              try number(payload,"activityID")==activityID.value,
              try number(payload,"firstInputSequence")<=number(payload,"lastInputSequence"),
              try number(payload,"lastInputSequence")==number(payload,"lastSpeechInputSequence") else{throw HistoryError.invalid}
        let inner=try innerNode.object(["version","status","sourceCode","streamGeneration","segmentID","revision","startHostTime","endHostTime","finalizedUptimeNanoseconds","receivedUptimeNanoseconds","text","confidence","timebase"])
        guard try number(inner,"version")==1,case .string("final")=inner["status"],
              try number(inner,"sourceCode")==UInt64(source.rawValue),try number(inner,"streamGeneration")==streamGeneration.value,
              try number(inner,"segmentID")==segmentID.value,try number(inner,"revision")==revision.value,
              case .string(let originalText)=inner["text"],originalText==text,
              let confidence=inner["confidence"],let clockNode=inner["timebase"] else{throw HistoryError.invalid}
        if !confidence.isNull{guard try confidence.uint(false)<=1 else{throw HistoryError.invalid}}
        let clock=try clockNode.object(["hostTicksAtAnchor","uptimeNsAtAnchor","nsNumer","nsDenom"])
        let anchor=try number(clock,"uptimeNsAtAnchor")
        let calibration=NativeClockCalibration(hostTicksAtAnchor:try number(clock,"hostTicksAtAnchor"),uptimeNsAtAnchor:anchor,
            nsNumer:try number(clock,"nsNumer"),nsDenom:try number(clock,"nsDenom"))
        let start=try calibration.uptimeNanoseconds(forHostTicks:number(inner,"startHostTime"))
        let end=try calibration.uptimeNanoseconds(forHostTicks:number(inner,"endHostTime"))
        let finalized=try number(inner,"finalizedUptimeNanoseconds"),received=try number(inner,"receivedUptimeNanoseconds")
        // Exactly the existing live transcript bounds, additionally matching
        // the stored projection to its own original calibrated evidence.
        guard start==startUptimeNanoseconds.value,end==endUptimeNanoseconds.value,start<=end,
              end<=finalized,finalized<=received,try received<=number(o,"emittedUptimeNanoseconds"),
              end-start<=120_000_000_000,finalized-end<=30_000_000_000,
              (finalized>=anchor ? finalized-anchor:anchor-finalized)<=600_000_000_000 else{throw HistoryError.invalid}
    }
}
/// Only the existing validator in this module can construct this wrapper. An
/// app/helper JSON object cannot issue it. Public consumers may observe it.
public struct ValidatedTranscriptObservation:Sendable {
    public let event:NativeSessionEvent
    public let final:HistoryFinal?
    public let sequenceGap:Bool
    init(event:NativeSessionEvent,final:HistoryFinal?=nil,sequenceGap:Bool=false){self.event=event;self.final=final;self.sequenceGap=sequenceGap}
}
public struct HistoryDetail:Sendable,Equatable {
    public let record:HistoryRecord
    public let captures:[HistoryCapture]
    public let rows:[HistoryFinal]
    public let nextOffset:Int?
    public let totalRows:Int
}
public struct HistoryPage:Sendable,Equatable {
    public let records:[HistoryRecord]
    public let nextOffset:Int?
}
enum HistoryJSON {
    static func encode<T:Encodable>(_ value:T)throws->Data{let e=JSONEncoder();e.outputFormatting=[.sortedKeys];return try e.encode(value)}
    static func decode<T:Codable>(_ type:T.Type,_ data:Data)throws->T{
        let value=try JSONDecoder().decode(type,from:data)
        guard try encode(value)==data else{throw HistoryError.invalid};return value
    }
}
