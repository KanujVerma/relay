import Foundation
import Security

public enum ProfileError: Error, Sendable {
    case unavailable, invalidKey, invalidPayload, invalidLocation, corruptVault, transport, rejected
}

public protocol ProfileKeyProvider: Sendable {
    func key(createIfMissing: Bool) throws -> Data
}

public protocol SecurityItemClient: Sendable {
    func copy(_ query: [String: Any]) -> (OSStatus, Data?)
    func add(_ query: [String: Any]) -> OSStatus
}

public struct SystemSecurityItems: SecurityItemClient {
    public init() {}
    public func copy(_ query: [String: Any]) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }
    public func add(_ query: [String: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }
}

/// Fixed namespaces. The profile and credential identities match accepted
/// account storage728e929; history and response preferences are separate
/// approved local domains.
public enum KeychainKeyPurpose:Sendable {
    case profile,chatGPTCredentials,history,responsePreferences
    fileprivate var service:String {
        switch self {case .profile:"com.relay.profile.v1";case .chatGPTCredentials:"com.relay.chatgpt-auth.v1";case .history:"com.relay.history.v1";case .responsePreferences:"com.relay.response-preferences.v1"}
    }
    fileprivate var account:String {
        switch self {case .profile:"local-profile-aes256";case .chatGPTCredentials:"local-chatgpt-aes256";case .history:"local-history-aes256";case .responsePreferences:"local-response-preferences-aes256"}
    }
}
/// Construction does not access Keychain. Only an explicit native open action
/// calls key(). No generic-password enumeration, cloud sync or automatic reset.
public struct KeychainProfileKey: ProfileKeyProvider {
    private let purpose:KeychainKeyPurpose
    private let client: any SecurityItemClient
    private let random: @Sendable () throws -> Data
    public init(purpose:KeychainKeyPurpose = .profile,client: any SecurityItemClient = SystemSecurityItems(),
                random: @escaping @Sendable () throws -> Data = {
                    var bytes = [UInt8](repeating: 0, count: 32)
                    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess
                    else { throw ProfileError.unavailable }
                    return Data(bytes)
                }) {
        self.purpose=purpose
        self.client = client
        self.random = random
    }
    public func key(createIfMissing: Bool) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: purpose.service,
            kSecAttrAccount as String: purpose.account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        let (status, existing) = client.copy(query)
        if status == errSecSuccess {
            guard let existing, existing.count == 32 else { throw ProfileError.invalidKey }
            return existing
        }
        guard status == errSecItemNotFound, createIfMissing else { throw ProfileError.unavailable }
        let bytes = try random()
        guard bytes.count == 32 else { throw ProfileError.invalidKey }
        query.removeValue(forKey: kSecReturnData as String)
        query.removeValue(forKey: kSecMatchLimit as String)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecValueData as String] = bytes
        // A duplicate from another owner is an error, never a key replacement.
        guard client.add(query) == errSecSuccess else { throw ProfileError.unavailable }
        return bytes
    }
}

/// Source-compatible profile facade. Its filename, authenticated header,
/// maximum and default key namespace remain identical to the original vault.
public final class ProfileVault:ProtectedSnapshotStorage,@unchecked Sendable {
    public static let maxPayloadBytes=ProtectedSnapshotVault.maxPayloadBytes
    private let snapshot:ProtectedSnapshotVault
    public init(directory:URL,keys:any ProfileKeyProvider=KeychainProfileKey()) {
        snapshot=ProtectedSnapshotVault(directory:directory,purpose:.profile,keys:keys)
    }
    public func exists()throws->Bool{try snapshot.exists()}
    public func load()throws->Data{try snapshot.load()}
    public func save(_ payload:Data,createKey:Bool=false)throws{try snapshot.save(payload,createKey:createKey)}
}
