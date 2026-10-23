import Foundation

/// Lossless unsigned counters and explicit nulls; never JSONSerialization's
/// floating-point conversion of native identifiers.
public enum WireValue: Sendable, Equatable, Encodable {
    case uint(UInt64), string(String), bool(Bool), null, object([String: WireValue]), array([WireValue])
    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .uint(let v): try value.encode(v)
        case .string(let v): try value.encode(v)
        case .bool(let v): try value.encode(v)
        case .null: try value.encodeNil()
        case .object(let v): try value.encode(v)
        case .array(let v): try value.encode(v)
        }
    }
}
public enum SessionEventKind: String, Sendable, Codable {
    case sessionStarted = "session_started", speechStarted = "speech_started", speechEnded = "speech_ended", eou
    case sourceUnavailable = "source_unavailable", discontinuity, stopping, stopped
}
public enum SessionReason: String, Sendable, Codable {
    case userStop = "user_stop", consentRevoked = "consent_revoked"
    case selectedAppUnavailable = "selected_app_unavailable", captureError = "capture_error"
    case deviceChanged = "device_changed", sequenceGap = "sequence_gap", queueOverflow = "queue_overflow"
    case modelUnavailable = "model_unavailable", vadUnavailable = "vad_unavailable", asrUnavailable = "asr_unavailable"
    case clockInvalid = "clock_invalid", transportClosed = "transport_closed", shutdownTimeout = "shutdown_timeout"
}
public struct NativeSessionEvent: Sendable, Equatable, Encodable {
    public let captureSessionID: UUID
    public let sessionEpoch: UInt64
    public let eventSequence: UInt64
    public let presentationGeneration: UInt64
    public let kind: SessionEventKind
    public let sourceCode: UInt32?
    public let streamGeneration: UInt64?
    public let emittedUptimeNanoseconds: UInt64
    public let payload: [String: WireValue]
    public let requestID: UUID?
    public var lease: PresentationLease {
        PresentationLease(captureSessionID: captureSessionID, sessionEpoch: sessionEpoch,
                          presentationGeneration: presentationGeneration)
    }
    public init(captureSessionID: UUID, sessionEpoch: UInt64, eventSequence: UInt64,
                presentationGeneration: UInt64, kind: SessionEventKind, sourceCode: UInt32?,
                streamGeneration: UInt64?, emittedUptimeNanoseconds: UInt64, payload: [String: WireValue], requestID: UUID? = nil) {
        self.captureSessionID = captureSessionID; self.sessionEpoch = sessionEpoch
        self.eventSequence = eventSequence; self.presentationGeneration = presentationGeneration
        self.kind = kind; self.sourceCode = sourceCode; self.streamGeneration = streamGeneration
        self.emittedUptimeNanoseconds = emittedUptimeNanoseconds; self.payload = payload; self.requestID = requestID
    }
    public func encode(to encoder: any Encoder) throws {
        try WireValue.object([
            "requestID": requestID.map { .string($0.uuidString.lowercased()) } ?? .null,
            "schemaVersion": .uint(1), "captureSessionID": .string(captureSessionID.uuidString.lowercased()),
            "sessionEpoch": .uint(sessionEpoch), "eventSequence": .uint(eventSequence),
            "presentationGeneration": .uint(presentationGeneration), "kind": .string(kind.rawValue),
            "sourceCode": sourceCode.map { .uint(UInt64($0)) } ?? .null,
            "streamGeneration": streamGeneration.map(WireValue.uint) ?? .null,
            "emittedUptimeNanoseconds": .uint(emittedUptimeNanoseconds), "payload": .object(payload)
        ]).encode(to: encoder)
    }
    public func encodedFrame(maximumBytes: Int = 16_384) throws -> Data {
        let json = try JSONEncoder().encode(self)
        guard !json.isEmpty, json.count <= maximumBytes, json.count <= Int(UInt32.max) else {
            throw NativeSessionError.frameTooLarge
        }
        var length = UInt32(json.count).bigEndian
        var framed = withUnsafeBytes(of: &length) { Data($0) }
        framed.append(json)
        return framed
    }
}
