import Foundation
import RelayProfile
import XCTest
@testable import RelayAccount

private final class SyntheticKeys: ProfileKeyProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var flags: [Bool] = []
    let fail: Bool
    init(fail: Bool = false) { self.fail = fail }
    var count: Int { lock.withLock { calls } }
    var createFlags: [Bool] { lock.withLock { flags } }
    func key(createIfMissing: Bool) throws -> Data {
        lock.withLock { calls += 1; flags.append(createIfMissing) }
        if fail { throw ProfileError.unavailable }
        return Data(repeating: 17, count: 32)
    }
}

final class AccountFoundationTests: XCTestCase {
    func testAccountFirstCreatesOnlyOwnedDirectoriesAndProfileCanOpenAfterward() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let root = temporary.appendingPathComponent("Relay"), keys = SyntheticKeys()
        let storage = AccountStorage(sharedDirectory: root, keys: keys)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path)); XCTAssertEqual(keys.count, 0)
        let bootstrap = try storage.controlBootstrap(generation: UUID(), createKey: true)
        for url in [root, root.appendingPathComponent("Accounts")] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        }
        XCTAssertEqual(keys.count, 1)
        XCTAssertFalse(String(describing: bootstrap).contains(Data(repeating: 17, count: 32).base64EncodedString()))
        XCTAssertEqual(String(reflecting: bootstrap), "AccountSecretBootstrap(redacted)")
        let frame = try bootstrap.frame(), length = frame.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        XCTAssertEqual(length, frame.count - 4)
        let payload = try JSONSerialization.jsonObject(with: frame.dropFirst(4)) as! [String: Any]
        XCTAssertEqual(payload["purpose"] as? String, "account_control")
        XCTAssertEqual(payload.count, 7)
        // A later speech cache and the normal Personal Brain vault share only
        // the fixed parent, never account keys, consent or profile contents.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("SpeechModels"), withIntermediateDirectories: false)
        let profile = ProfileVault(directory: root, keys: SyntheticKeys())
        let personal = Data("synthetic confirmed profile fixture".utf8)
        try profile.save(personal, createKey: true)
        XCTAssertEqual(try profile.load(), personal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Accounts").path))
    }

    func testUnknownPermissionsSymlinkAndLockedKeyAreNeverRepairedOrReplaced() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let root = temporary.appendingPathComponent("Relay"), keys = SyntheticKeys()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
        XCTAssertThrowsError(try AccountStorage(sharedDirectory: root, keys: keys).controlBootstrap(generation: UUID(), createKey: true))
        XCTAssertEqual(keys.count, 0)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber)?.intValue, 0o755)
        let link = temporary.appendingPathComponent("Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertThrowsError(try AccountStorage(sharedDirectory: link, keys: keys).controlBootstrap(generation: UUID(), createKey: true))
        let missing = temporary.appendingPathComponent("FreshRelay"), locked = SyntheticKeys(fail: true)
        XCTAssertThrowsError(try AccountStorage(sharedDirectory: missing, keys: locked).controlBootstrap(generation: UUID(), createKey: true))
        XCTAssertEqual(locked.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.appendingPathComponent("Accounts/credentials.relayvault").path))
    }

    func testExistingCiphertextNeverAuthorizesCreationOfAReplacementMissingKey() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let root = temporary.appendingPathComponent("Relay"), keys = SyntheticKeys()
        let storage = AccountStorage(sharedDirectory: root, keys: keys)
        _ = try storage.controlBootstrap(generation: UUID(), createKey: true)
        let file = root.appendingPathComponent("Accounts/credentials.relayvault")
        let sentinel = Data("synthetic encrypted-file stand-in, never decoded by native".utf8)
        try sentinel.write(to: file); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let locked = SyntheticKeys(fail: true)
        XCTAssertThrowsError(try AccountStorage(sharedDirectory: root, keys: locked).controlBootstrap(generation: UUID(), createKey: true))
        XCTAssertEqual(locked.createFlags, [false]); XCTAssertEqual(try Data(contentsOf: file), sentinel)
    }

    func testStrictAccountResponseRejectsDuplicateExtraBooleanCountersAndFalseReady() throws {
        let request = UUID(), registration = UUID()
        let row: [String: Any] = ["registrationID": registration.uuidString.lowercased(), "label": "Synthetic account",
            "email": "synthetic@example.test", "identityState": "validated_at_sign_in", "planUsageState": "granted",
            "sessionState": "available", "lastValidatedAt": 1, "planNoticeAcknowledged": false]
        let snapshot: [String: Any] = ["revision": 3, "activeRegistrationID": registration.uuidString.lowercased(), "registrations": [row],
            "models": [["slug": "synthetic-first", "displayName": "First"], ["slug": "synthetic-second", "displayName": "Second"]], "catalogState": "current"]
        var value: [String: Any] = ["schemaVersion": 1, "kind": "account_response", "requestID": request.uuidString.lowercased(), "action": "connect",
            "resultRevision": 2, "status": "ready", "reasonCode": "connected", "snapshot": snapshot]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        let response = try AccountResponse(data: data)
        XCTAssertEqual(response.requestID, request); XCTAssertEqual(response.snapshot.models.map(\.slug), ["synthetic-first", "synthetic-second"])
        XCTAssertEqual(response.snapshot.registrations.first?.identityState, "validated_at_sign_in")
        let duplicate = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"schemaVersion\":1")
        XCTAssertThrowsError(try AccountResponse(data: Data(duplicate.utf8)))
        for changes in [["schemaVersion": true], ["resultRevision": 2.0], ["authorized": true], ["reasonCode": "raw_provider_error"]] as [[String: Any]] {
            var bad = value; changes.forEach { bad[$0.key] = $0.value }
            // JSONSerialization collapses 2.0 to 2, so preserve this counter's
            // actual decimal bytes independently below.
            if changes["resultRevision"] != nil { continue }
            XCTAssertThrowsError(try AccountResponse(data: JSONSerialization.data(withJSONObject: bad)))
        }
        XCTAssertThrowsError(try AccountResponse(data: Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"resultRevision\":2", with: "\"resultRevision\":2.0").utf8)))
        var missing = snapshot; missing["activeRegistrationID"] = NSNull(); value["snapshot"] = missing
        XCTAssertThrowsError(try AccountResponse(data: JSONSerialization.data(withJSONObject: value)))
    }
}
