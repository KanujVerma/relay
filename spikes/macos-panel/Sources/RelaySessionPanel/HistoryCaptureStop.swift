import Foundation
import RelayNativeSession

/// Original native cleanup receipt, retained as evidence only. A false receipt
/// or missing receipt never becomes an end from a UI flag, timer or logical
/// record end. This type cannot issue capture/request authority.
public struct HistoryCaptureStop:Sendable,Equatable,Codable{
    public let observedWallTime:TimeInterval
    let originalEventJSON:Data
    private struct Evidence{
        let session:UUID,epoch:UInt64,sequence:UInt64,emitted:UInt64,quiesced:Bool
        let reason:SessionReason
    }
    init(_ event:NativeSessionEvent,now:TimeInterval)throws{
        observedWallTime=now;originalEventJSON=try HistoryJSON.encode(event)
        _=try evidence()
    }
    var reason:SessionReason?{try? evidence().reason}
    public var quiesced:Bool{(try? evidence().quiesced)==true}
    public var eventSequence:HistoryCounter?{(try? evidence()).map{HistoryCounter($0.sequence)}}
    public var emittedUptimeNanoseconds:HistoryCounter?{(try? evidence()).map{HistoryCounter($0.emitted)}}
    func validate(for capture:HistoryCapture)throws{
        let original=try evidence()
        guard original.session==capture.captureSessionID,original.epoch==capture.sessionEpoch.value,
              original.sequence>capture.startedEventSequence.value,original.emitted>=capture.startedUptimeNanoseconds.value else{throw HistoryError.invalid}
    }
    func follows(_ final:HistoryFinal)throws{
        let original=try evidence()
        let fields=try StrictJSON.decode(final.originalEventJSON).object(["schemaVersion","captureSessionID","sessionEpoch","eventSequence","presentationGeneration","kind","sourceCode","streamGeneration","emittedUptimeNanoseconds","payload","requestID"])
        guard let emitted=fields["emittedUptimeNanoseconds"],final.eventSequence.value<original.sequence,
              try emitted.uint(false)<=original.emitted else{throw HistoryError.invalid}
    }
    private func evidence()throws->Evidence{
        guard observedWallTime.isFinite,originalEventJSON.count<=1024 else{throw HistoryError.invalid}
        let o=try StrictJSON.decode(originalEventJSON).object(["schemaVersion","captureSessionID","sessionEpoch","eventSequence","presentationGeneration","kind","sourceCode","streamGeneration","emittedUptimeNanoseconds","payload","requestID"])
        func number(_ key:String)throws->UInt64{guard let value=o[key] else{throw HistoryError.invalid};return try value.uint(false)}
        guard try number("schemaVersion")==1,case .string("stopped")=o["kind"],
              case .string(let id)=o["captureSessionID"],let session=UUID(uuidString:id),
              o["sourceCode"]?.isNull==true,o["streamGeneration"]?.isNull==true,o["requestID"]?.isNull==true,
              let payload=o["payload"] else{throw HistoryError.invalid}
        let p=try payload.object(["reasonCode","quiesced"])
        guard case .string(let code)=p["reasonCode"],let reason=SessionReason(rawValue:code),
              case .bool(let quiesced)=p["quiesced"] else{throw HistoryError.invalid}
        let epoch=try number("sessionEpoch"),sequence=try number("eventSequence"),emitted=try number("emittedUptimeNanoseconds")
        _=try number("presentationGeneration")
        guard epoch>0,sequence>1 else{throw HistoryError.invalid}
        return Evidence(session:session,epoch:epoch,sequence:sequence,emitted:emitted,quiesced:quiesced,reason:reason)
    }
}
