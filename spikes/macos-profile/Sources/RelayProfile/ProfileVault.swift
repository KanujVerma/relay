import CryptoKit
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

/// Fixed namespaces keep credentials and Personal Brain keys independent.
public enum KeychainKeyPurpose:Sendable {
    case profile,chatGPTCredentials
    fileprivate var service:String{self == .profile ? "com.relay.profile.v1":"com.relay.chatgpt-auth.v1"}
    fileprivate var account:String{self == .profile ? "local-profile-aes256":"local-chatgpt-aes256"}
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
        self.client = client
        self.random = random
        self.purpose=purpose
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

/// Whole-payload AES-GCM protects claims, evidence, source digests, role and
/// review metadata. Plaintext stays in process memory and inherited pipes.
/// This does not promise secure erase, backup removal or same-user isolation.
public final class ProfileVault: @unchecked Sendable {
    public static let maxPayloadBytes = 8 * 1024 * 1024
    private static let header = Data("RELAYPROFILE1\n".utf8)
    private let directory: URL
    private let keys: any ProfileKeyProvider
    private let lock = NSLock()
    public init(directory: URL, keys: any ProfileKeyProvider = KeychainProfileKey()) {
        self.directory = directory
        self.keys = keys
    }
    private var file: URL { directory.appendingPathComponent("profile.relayvault") }

    public func exists() throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        try checkDirectory(create: false)
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        try checkFile()
        return true
    }

    private func checkDirectory(create: Bool) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path), create {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        }
        let attributes = try manager.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
        else { throw ProfileError.invalidLocation }
        // Existing directories may contain other data; do not chmod those.
        guard (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700
        else { throw ProfileError.invalidLocation }
    }

    private func checkFile() throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.referenceCount] as? NSNumber)?.intValue == 1,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              let size = attributes[.size] as? NSNumber,
              size.intValue <= Self.maxPayloadBytes + 128
        else { throw ProfileError.invalidLocation }
    }

    public func load() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        try checkDirectory(create: false)
        try checkFile()
        let encrypted = try Data(contentsOf: file)
        guard encrypted.starts(with: Self.header) else { throw ProfileError.corruptVault }
        let rawKey = try keys.key(createIfMissing: false)
        guard rawKey.count == 32 else { throw ProfileError.invalidKey }
        do {
            let box = try AES.GCM.SealedBox(combined: encrypted.dropFirst(Self.header.count))
            let payload = try AES.GCM.open(box, using: SymmetricKey(data: rawKey), authenticating: Self.header)
            guard !payload.isEmpty, payload.count <= Self.maxPayloadBytes else { throw ProfileError.invalidPayload }
            return payload
        } catch { throw ProfileError.corruptVault }
    }

    public func save(_ payload: Data, createKey: Bool = false) throws {
        lock.lock(); defer { lock.unlock() }
        guard !payload.isEmpty, payload.count <= Self.maxPayloadBytes else { throw ProfileError.invalidPayload }
        try checkDirectory(create: true)
        let existing = FileManager.default.fileExists(atPath: file.path)
        if existing {
            guard !createKey else { throw ProfileError.invalidLocation }
            try checkFile()
        } else if !createKey {
            throw ProfileError.invalidLocation
        }
        let rawKey = try keys.key(createIfMissing: createKey)
        guard rawKey.count == 32 else { throw ProfileError.invalidKey }
        let box = try AES.GCM.seal(payload, using: SymmetricKey(data: rawKey), authenticating: Self.header)
        guard let combined = box.combined else { throw ProfileError.invalidPayload }
        let ciphertext = Self.header + combined
        // Only ciphertext reaches the temporary file. Atomic replacement means
        // a failed save leaves the prior complete snapshot available.
        try ciphertext.write(to: file, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
