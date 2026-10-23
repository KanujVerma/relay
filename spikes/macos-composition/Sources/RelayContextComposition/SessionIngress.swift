import Foundation
import RelayNativeSession

/// One native ingress order for real audio events and explicit Help requests.
public enum SessionIngress: Sendable, Equatable {
    case audio(NativeSessionEvent)
    case manual(NativeManualHelpRequest)
    public var binding: PanelRequestBinding? {
        switch self {
        case .audio(let event): PanelRequestBinding(event)
        case .manual(let request): PanelRequestBinding(lease:request.lease,requestID:request.requestID,eventSequence:request.anchorEventSequence)
        }
    }
    public func encodedByteCount() throws -> Int {
        switch self {
        case .audio(let event): try event.encodedFrame().count
        case .manual(let request): try request.encodedJSON().count+4
        }
    }
    var invalidatesOptionalWork: Bool {
        guard case .audio(let event)=self else { return false }
        return (event.sourceCode == 2 && event.kind == .speechStarted)
            || [.sessionStarted,.stopping,.stopped,.sourceUnavailable,.discontinuity].contains(event.kind)
    }
}
