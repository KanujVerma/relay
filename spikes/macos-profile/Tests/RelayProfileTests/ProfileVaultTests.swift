import XCTest
import Security
@testable import RelayProfile

private struct FixtureKey: ProfileKeyProvider {
    let value: Data
    func key(createIfMissing: Bool) throws -> Data { value }
}

private final class FixtureSecurity: SecurityItemClient, @unchecked Sendable {
    var status: OSStatus = errSecItemNotFound
    var value: Data?
    var queries: [[String: Any]] = []
    func copy(_ query: [String: Any]) -> (OSStatus, Data?) {
        queries.append(query)
        return (status, value)
    }
    func add(_ query: [String: Any]) -> OSStatus {
        queries.append(query)
        return errSecSuccess
    }
}

final class ProfileVaultTests: XCTestCase {
    func testChatGPTKeyUsesSeparateFixedNamespaceAndProfileDefaultRemainsUnchanged() throws {
        let accountSecurity=FixtureSecurity()
        let account=KeychainProfileKey(purpose:.chatGPTCredentials,client:accountSecurity,random:{Data(repeating:4,count:32)})
        XCTAssertTrue(accountSecurity.queries.isEmpty)
        _=try account.key(createIfMissing:true)
        XCTAssertTrue(accountSecurity.queries.allSatisfy{
            $0[kSecAttrService as String] as? String == "com.relay.chatgpt-auth.v1"
                && $0[kSecAttrAccount as String] as? String == "local-chatgpt-aes256"
        })
        let profileSecurity=FixtureSecurity()
        _=try KeychainProfileKey(client:profileSecurity,random:{Data(repeating:5,count:32)}).key(createIfMissing:true)
        XCTAssertTrue(profileSecurity.queries.allSatisfy{
            $0[kSecAttrService as String] as? String == "com.relay.profile.v1"
                && $0[kSecAttrAccount as String] as? String == "local-profile-aes256"
        })
    }
    func testLockedChatGPTKeyNeverCreatesOrFallsBackToTheProfileKey() throws {
        let security=FixtureSecurity();security.status=errSecInteractionNotAllowed
        let account=KeychainProfileKey(purpose:.chatGPTCredentials,client:security,random:{XCTFail("must not create a key");return Data()})
        XCTAssertThrowsError(try account.key(createIfMissing:true))
        XCTAssertEqual(security.queries.count,1)
        XCTAssertEqual(security.queries[0][kSecAttrService as String] as? String,"com.relay.chatgpt-auth.v1")
    }
    func testFullPayloadAndMetadataAreEncryptedAndTamperingFailsClosed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = ProfileVault(directory: directory, keys: FixtureKey(value: Data(repeating: 7, count: 32)))
        let payload = Data("SQLite format 3\0private-claim;private-source;private-role;private-label".utf8)
        try vault.save(payload, createKey: true)
        let file = directory.appendingPathComponent("profile.relayvault")
        let encrypted = try Data(contentsOf: file)
        XCTAssertNil(encrypted.range(of: Data("private-claim".utf8)))
        XCTAssertNil(encrypted.range(of: Data("private-source".utf8)))
        XCTAssertNil(encrypted.range(of: Data("private-role".utf8)))
        XCTAssertEqual(try vault.load(), payload)
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        var corrupted = encrypted
        corrupted[corrupted.count - 1] ^= 1
        try corrupted.write(to: file)
        XCTAssertThrowsError(try vault.load())
        XCTAssertEqual(try Data(contentsOf: file), corrupted)
    }

    func testWrongKeyAndInvalidSizeDoNotReplaceExistingVault() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = ProfileVault(directory: directory, keys: FixtureKey(value: Data(repeating: 1, count: 32)))
        try vault.save(Data("synthetic ledger".utf8), createKey: true)
        let original = try Data(contentsOf: directory.appendingPathComponent("profile.relayvault"))
        let wrong = ProfileVault(directory: directory, keys: FixtureKey(value: Data(repeating: 2, count: 32)))
        XCTAssertThrowsError(try wrong.load())
        XCTAssertThrowsError(try vault.save(Data(), createKey: false))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("profile.relayvault")), original)
    }

    func testKeychainFailureIsNotTreatedAsMissingAndExistingKeyIsNeverRotated() throws {
        let security = FixtureSecurity()
        let provider = KeychainProfileKey(client: security, random: { Data(repeating: 3, count: 32) })
        security.status = errSecInteractionNotAllowed
        XCTAssertThrowsError(try provider.key(createIfMissing: true))
        XCTAssertEqual(security.queries.count, 1)
        security.queries = []
        security.status = errSecSuccess
        security.value = Data(repeating: 9, count: 32)
        XCTAssertEqual(try provider.key(createIfMissing: true), Data(repeating: 9, count: 32))
        XCTAssertEqual(security.queries.count, 1)
    }

    func testCreatedKeyIsDeviceLocalNonSynchronizingAndNoLookupOnConstruction() throws {
        let security = FixtureSecurity()
        let provider = KeychainProfileKey(client: security, random: { Data(repeating: 3, count: 32) })
        XCTAssertTrue(security.queries.isEmpty)
        XCTAssertEqual(try provider.key(createIfMissing: true), Data(repeating: 3, count: 32))
        XCTAssertEqual(security.queries.count, 2)
        let query = security.queries[1]
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(query[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
    }

    func testSymlinkVaultDirectoryIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let vault = ProfileVault(directory: link, keys: FixtureKey(value: Data(repeating: 1, count: 32)))
        XCTAssertThrowsError(try vault.save(Data("synthetic".utf8), createKey: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("profile.relayvault").path))
    }
}
