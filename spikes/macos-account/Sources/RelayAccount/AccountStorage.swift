import Darwin
import Foundation
import RelayProfile

public enum AccountError: Error, Sendable { case malformed, overflow, closed, timedOut, storage, locked, unavailable, rejected }

public enum AccountBootstrapPurpose: String, Sendable { case accountControl = "account_control", oauthSession = "oauth_session" }

/// Native-only pipe material. Never Codable, published status or diagnostics.
public struct AccountSecretBootstrap: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let purpose: AccountBootstrapPurpose
    public let registrationID: UUID?
    public let generation: UUID
    private let key: Data
    private let directory: URL
    init(purpose: AccountBootstrapPurpose, key: Data, directory: URL, registrationID: UUID?, generation: UUID) {
        self.purpose = purpose; self.key = key; self.directory = directory
        self.registrationID = registrationID; self.generation = generation
    }
    public var description: String { "AccountSecretBootstrap(redacted)" }
    public var debugDescription: String { description }
    /// A private inherited stdin frame, never argv/env, a file, RPC or a log.
    public func frame() throws -> Data {
        guard key.count == 32, purpose != .oauthSession || registrationID != nil else { throw AccountError.malformed }
        let value: [String: Any] = ["schemaVersion": 1, "kind": "account_secret_bootstrap", "purpose": purpose.rawValue,
            "key": key.base64EncodedString(), "vaultDirectory": directory.path,
            "registrationID": registrationID?.uuidString.lowercased() as Any? ?? NSNull(), "accountGeneration": generation.uuidString.lowercased()]
        return try accountFrame(JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    }
}

/// The app supplies its fixed ApplicationSupport/Relay parent, not a user-
/// chosen arbitrary vault. Construction is inert. Unknown paths are not healed.
public struct AccountStorage: Sendable {
    private let sharedDirectory: URL
    private let keys: any ProfileKeyProvider
    public init(sharedDirectory: URL, keys: any ProfileKeyProvider = KeychainProfileKey(purpose: .chatGPTCredentials)) {
        self.sharedDirectory = sharedDirectory; self.keys = keys
    }
    private func ownedDirectory(_ url: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/") else { throw AccountError.storage }
        let manager = FileManager.default
        var info = stat()
        if lstat(url.path, &info) != 0 {
            guard errno == ENOENT else { throw AccountError.storage }
            // No recursive mkdir: an unknown intermediate parent must not be
            // silently created with a permissive mode, or permission-repaired.
            do { try manager.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
            catch { throw AccountError.storage }
            guard lstat(url.path, &info) == 0 else { throw AccountError.storage }
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid(), (info.st_mode & 0o7777) == 0o700 else { throw AccountError.storage }
    }
    func bootstrap(purpose: AccountBootstrapPurpose, registrationID: UUID?, generation: UUID, createKey: Bool) throws -> AccountSecretBootstrap {
        try ownedDirectory(sharedDirectory)
        let directory = sharedDirectory.appendingPathComponent("Accounts", isDirectory: true)
        try ownedDirectory(directory)
        let key: Data
        var existing = stat()
        let credentialExists = lstat(directory.appendingPathComponent("credentials.relayvault").path, &existing) == 0
        guard credentialExists || errno == ENOENT else { throw AccountError.storage }
        do { key = try keys.key(createIfMissing: createKey && !credentialExists) }
        catch { throw AccountError.locked }
        guard key.count == 32 else { throw AccountError.locked }
        return AccountSecretBootstrap(purpose: purpose, key: key, directory: directory, registrationID: registrationID, generation: generation)
    }
    public func controlBootstrap(generation: UUID, createKey: Bool) throws -> AccountSecretBootstrap {
        try bootstrap(purpose: .accountControl, registrationID: nil, generation: generation, createKey: createKey)
    }
}

func accountFrame(_ data: Data) throws -> Data {
    guard !data.isEmpty, data.count <= 16384 else { throw AccountError.overflow }
    _ = try AccountJSON.decode(data)
    var count = UInt32(data.count).bigEndian
    return withUnsafeBytes(of: &count) { Data($0) } + data
}
