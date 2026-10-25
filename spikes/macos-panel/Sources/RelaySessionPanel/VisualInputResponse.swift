import Foundation

public enum VisualInputAction:String,Sendable { case verify,disable,status }
public enum VisualInputStatus:String,Sendable { case checking,verified,disabled,unverified,cancelled,unavailable,busy }
public enum VisualInputReason:String,Sendable {
    case checking,probeVerified="probe_verified",probeUnverified="probe_unverified",probeCancelled="probe_cancelled"
    case userDisabled="user_disabled",currentStatus="current_status",inferenceDisabled="inference_disabled"
    case sessionActive="session_active",answerInProgress="answer_in_progress",probeInProgress="probe_in_progress"
}

/// A typed reflection of helper-owned status, never an image capability or an
/// account identity. Only the backend's private receipt/permit grants upload.
public struct VisualInputResponse:Sendable,Equatable {
    public let requestID:UUID
    public let action:VisualInputAction
    public let revision:UInt64
    public let status:VisualInputStatus
    public let reason:VisualInputReason
    public let model:String?
    public var isTerminal:Bool { revision==2 }
    public init(data:Data)throws {
        let value=try StrictJSON.decode(data).object(["schemaVersion","kind","requestID","action","resultRevision","status","reasonCode","model"])
        guard try value["schemaVersion"]!.uint()==1,try value["kind"]!.string()=="visual_input_response",
              let id=UUID(uuidString:try value["requestID"]!.string()),
              let action=VisualInputAction(rawValue:try value["action"]!.string()),
              let status=VisualInputStatus(rawValue:try value["status"]!.string()),
              let reason=VisualInputReason(rawValue:try value["reasonCode"]!.string()) else { throw PanelBridgeError.malformed }
        let revision=try value["resultRevision"]!.uint()
        let model=value["model"]!.isNull ? nil:try value["model"]!.string(160)
        if revision==1 {
            guard action == .verify,status == .checking,reason == .checking else { throw PanelBridgeError.malformed }
        } else {
            guard revision==2,status != .checking else { throw PanelBridgeError.malformed }
            switch reason {
            case .checking:throw PanelBridgeError.malformed
            case .probeVerified:guard action == .verify,status == .verified,model != nil else { throw PanelBridgeError.malformed }
            case .probeUnverified:guard action == .verify,status == .unverified else { throw PanelBridgeError.malformed }
            case .probeCancelled:guard action == .verify,status == .cancelled else { throw PanelBridgeError.malformed }
            case .userDisabled:guard action == .disable,status == .disabled else { throw PanelBridgeError.malformed }
            case .currentStatus:guard action == .status else { throw PanelBridgeError.malformed }
            case .inferenceDisabled:guard action == .verify,status == .unavailable else { throw PanelBridgeError.malformed }
            case .sessionActive,.answerInProgress:guard action == .verify,status == .busy else { throw PanelBridgeError.malformed }
            case .probeInProgress:guard action != .disable,status == .busy else { throw PanelBridgeError.malformed }
            }
            if status == .verified,model==nil { throw PanelBridgeError.malformed }
        }
        self.requestID=id;self.action=action;self.revision=revision;self.status=status;self.reason=reason;self.model=model
    }
}
