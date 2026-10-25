import Foundation

public enum AccountAction: String, Sendable {
    case status, connect, cancel, select, models
    case enablePlan = "enable_plan", signOut = "sign_out", acknowledgePlanNotice = "acknowledge_plan_notice"
}
public enum AccountStatus: String, Sendable { case pending, ready, signedOut = "signed_out", locked, reauthRequired = "reauth_required", planDisabled = "plan_disabled", busy, cancelled, unavailable, error }
public enum AccountReason: String, Sendable {
    case currentStatus = "current_status", connected, planPermissionMissing = "plan_permission_missing"
    case reauthenticationRequired = "reauthentication_required", storageLocked = "storage_locked", storageUnavailable = "storage_unavailable"
    case authorizationPending = "authorization_pending", authorizationDeclined = "authorization_declined", authorizationFailed = "authorization_failed", authorizationCancelled = "authorization_cancelled"
    case accountSelected = "account_selected", signedOut = "signed_out", remoteRevocationUnconfirmed = "remote_revocation_unconfirmed"
    case catalogUpdated = "catalog_updated", catalogUnavailable = "catalog_unavailable", operationBusy = "operation_busy", protocolRejected = "protocol_rejected"
}
public enum AccountPlanState: String, Sendable { case granted, notGranted = "not_granted", unknown }
public enum AccountSessionState: String, Sendable { case available, signedOut = "signed_out", reauthRequired = "reauth_required", signingOut = "signing_out" }
public enum AccountCatalogState: String, Sendable { case unloaded, loading, current, unavailable }

public struct AccountModel: Sendable, Equatable, Identifiable {
    public var id: String { slug }
    public let slug: String
    public let displayName: String
    init(_ node: AccountJSONNode) throws {
        let value = try node.object(["slug", "displayName"])
        slug = try value["slug"]!.string(128); displayName = try value["displayName"]!.string(160)
        guard slug.utf8.allSatisfy({ $0 < 128 }), !slug.contains(where: \.isWhitespace),
              !displayName.trimmingCharacters(in: .whitespaces).isEmpty else { throw AccountError.malformed }
    }
}
public struct AccountRegistration: Sendable, Equatable, Identifiable {
    public var id: UUID { registrationID }
    public let registrationID: UUID
    public let label: String
    public let email: String?
    public let identityState: String
    public let planUsageState: AccountPlanState
    public let sessionState: AccountSessionState
    public let lastValidatedAt: UInt64
    public let planNoticeAcknowledged: Bool
    init(_ node: AccountJSONNode) throws {
        let value = try node.object(["registrationID", "label", "email", "identityState", "planUsageState", "sessionState", "lastValidatedAt", "planNoticeAcknowledged"])
        registrationID = try accountUUID(value["registrationID"]!)
        label = try value["label"]!.string(80); email = value["email"]!.isNull ? nil : try value["email"]!.string(254)
        identityState = try value["identityState"]!.string()
        guard identityState == "validated_at_sign_in", !label.trimmingCharacters(in: .whitespaces).isEmpty,
              let plan = AccountPlanState(rawValue: try value["planUsageState"]!.string()),
              let state = AccountSessionState(rawValue: try value["sessionState"]!.string()) else { throw AccountError.malformed }
        planUsageState = plan; sessionState = state
        lastValidatedAt = try value["lastValidatedAt"]!.uint(); planNoticeAcknowledged = try value["planNoticeAcknowledged"]!.boolean()
    }
}
public struct AccountSnapshot: Sendable, Equatable {
    public let revision: UInt64
    public let activeRegistrationID: UUID?
    public let registrations: [AccountRegistration]
    public let models: [AccountModel]
    public let catalogState: AccountCatalogState
    public var activeRegistration: AccountRegistration? { registrations.first { $0.id == activeRegistrationID } }
    init(_ node: AccountJSONNode) throws {
        let value = try node.object(["revision", "activeRegistrationID", "registrations", "models", "catalogState"])
        revision = try value["revision"]!.uint(false)
        activeRegistrationID = value["activeRegistrationID"]!.isNull ? nil : try accountUUID(value["activeRegistrationID"]!)
        registrations = try value["registrations"]!.array(8).map(AccountRegistration.init)
        models = try value["models"]!.array(32).map(AccountModel.init)
        guard let state = AccountCatalogState(rawValue: try value["catalogState"]!.string()) else { throw AccountError.malformed }
        catalogState = state
        guard Set(registrations.map(\.id)).count == registrations.count, Set(models.map(\.id)).count == models.count,
              activeRegistrationID == nil || registrations.contains(where: { $0.id == activeRegistrationID }) else { throw AccountError.malformed }
        guard state == .current || models.isEmpty else { throw AccountError.malformed }
    }
}

/// This is public last-check metadata, never an inference authority object.
public struct AccountResponse: Sendable, Equatable {
    public let requestID: UUID
    public let action: AccountAction
    public let revision: UInt64
    public let status: AccountStatus
    public let reason: AccountReason
    public let snapshot: AccountSnapshot
    public var isTerminal: Bool { revision == 2 }
    public init(data: Data) throws {
        let value = try AccountJSON.decode(data).object(["schemaVersion", "kind", "requestID", "action", "resultRevision", "status", "reasonCode", "snapshot"])
        guard try value["schemaVersion"]!.uint() == 1, try value["kind"]!.string() == "account_response",
              let action = AccountAction(rawValue: try value["action"]!.string()),
              let status = AccountStatus(rawValue: try value["status"]!.string()),
              let reason = AccountReason(rawValue: try value["reasonCode"]!.string()) else { throw AccountError.malformed }
        requestID = try accountUUID(value["requestID"]!); revision = try value["resultRevision"]!.uint()
        self.action = action; self.status = status; self.reason = reason
        snapshot = try AccountSnapshot(value["snapshot"]!)
        if revision == 1 {
            guard status == .pending, reason == .authorizationPending, action != .status else { throw AccountError.malformed }
        } else {
            guard revision == 2, status != .pending, reason != .authorizationPending else { throw AccountError.malformed }
        }
        if status == .ready {
            guard snapshot.activeRegistration?.sessionState == .available,
                  snapshot.activeRegistration?.planUsageState == .granted else { throw AccountError.malformed }
        }
        switch reason {
        case .connected: guard action == .connect || action == .enablePlan else { throw AccountError.malformed }
        case .accountSelected: guard action == .select else { throw AccountError.malformed }
        case .signedOut, .remoteRevocationUnconfirmed: guard action == .signOut, status == .signedOut else { throw AccountError.malformed }
        case .catalogUpdated, .catalogUnavailable: guard action == .models else { throw AccountError.malformed }
        case .currentStatus: guard action == .status || action == .acknowledgePlanNotice else { throw AccountError.malformed }
        case .operationBusy: guard status == .busy else { throw AccountError.malformed }
        case .authorizationCancelled: guard status == .cancelled else { throw AccountError.malformed }
        default: break
        }
    }
}

public struct AccountRequest: Sendable, Equatable {
    public let id: UUID
    public let action: AccountAction
    public let registrationID: UUID?
    public let targetRequestID: UUID?
    public init(id: UUID = UUID(), action: AccountAction, registrationID: UUID? = nil, targetRequestID: UUID? = nil) throws {
        switch action {
        case .status, .models: guard registrationID == nil, targetRequestID == nil else { throw AccountError.malformed }
        case .connect: guard targetRequestID == nil else { throw AccountError.malformed }
        case .cancel: guard registrationID == nil, targetRequestID != nil else { throw AccountError.malformed }
        default: guard registrationID != nil, targetRequestID == nil else { throw AccountError.malformed }
        }
        self.id = id; self.action = action; self.registrationID = registrationID; self.targetRequestID = targetRequestID
    }
    public func data() throws -> Data {
        var payload: [String: Any] = [:]
        if action == .connect { payload["registrationID"] = registrationID?.uuidString.lowercased() as Any? ?? NSNull() }
        else if let registrationID { payload["registrationID"] = registrationID.uuidString.lowercased() }
        if let targetRequestID { payload["targetRequestID"] = targetRequestID.uuidString.lowercased() }
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "kind": "account_request", "requestID": id.uuidString.lowercased(), "action": action.rawValue, "payload": payload], options: [.sortedKeys])
    }
}

func accountUUID(_ node: AccountJSONNode) throws -> UUID {
    let value = try node.string(36)
    guard let id = UUID(uuidString: value), id.uuidString.lowercased() == value.lowercased() else { throw AccountError.malformed }
    return id
}
