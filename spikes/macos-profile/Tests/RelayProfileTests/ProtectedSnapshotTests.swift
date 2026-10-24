import CryptoKit
import Foundation
import Security
import XCTest
@testable import RelayProfile

private final class SnapshotFixtureKey:ProfileKeyProvider,@unchecked Sendable {
    private let lock=NSLock()
    private var calls:[Bool]=[]
    let bytes=Data(repeating:29,count:32)
    func key(createIfMissing:Bool)throws->Data{lock.withLock{calls.append(createIfMissing)};return bytes}
    var requests:[Bool]{lock.withLock{calls}}
}
private final class SnapshotSecurity:SecurityItemClient,@unchecked Sendable {
    var queries:[[String:Any]]=[]
    var status:OSStatus=errSecItemNotFound
    func copy(_ query:[String:Any])->(OSStatus,Data?){queries.append(query);return(status,nil)}
    func add(_ query:[String:Any])->OSStatus{queries.append(query);return errSecSuccess}
}

final class ProtectedSnapshotTests:XCTestCase {
    private func root()throws->URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("relay-history-vault-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        addTeardownBlock{try? FileManager.default.removeItem(at:url)}
        return url
    }
    func testFixedKeyPurposesPreserveProfileAndCredentialsAndSeparateHistory()throws {
        for (purpose,service,account) in [(KeychainKeyPurpose.profile,"com.relay.profile.v1","local-profile-aes256"),
            (.chatGPTCredentials,"com.relay.chatgpt-auth.v1","local-chatgpt-aes256"),
            (.history,"com.relay.history.v1","local-history-aes256")] {
            let items=SnapshotSecurity()
            let provider=KeychainProfileKey(purpose:purpose,client:items,random:{Data(repeating:3,count:32)})
            XCTAssertTrue(items.queries.isEmpty)
            _=try provider.key(createIfMissing:true)
            XCTAssertEqual(items.queries.count,2)
            for q in items.queries{
                XCTAssertEqual(q[kSecAttrService as String] as? String,service)
                XCTAssertEqual(q[kSecAttrAccount as String] as? String,account)
                XCTAssertEqual(q[kSecAttrSynchronizable as String] as? Bool,false)
            }
            items.queries=[];items.status=errSecInteractionNotAllowed
            XCTAssertThrowsError(try provider.key(createIfMissing:true))
            XCTAssertEqual(items.queries.count,1)
        }
    }
    func testHistoryCreationIsExplicitCiphertextOnlyAndExistingLoadNeverCreates()throws {
        let root=try root(),directory=root.appendingPathComponent("Relay/History"),keys=SnapshotFixtureKey()
        let vault=ProtectedSnapshotVault(directory:directory,purpose:.history,keys:keys)
        XCTAssertTrue(keys.requests.isEmpty);XCTAssertFalse(FileManager.default.fileExists(atPath:directory.path))
        XCTAssertFalse(try vault.exists());XCTAssertThrowsError(try vault.load())
        XCTAssertTrue(keys.requests.isEmpty);XCTAssertFalse(FileManager.default.fileExists(atPath:directory.path))
        let payload=Data("fictional transcript and private title".utf8)
        try vault.save(payload,createKey:true)
        let file=directory.appendingPathComponent("history.relayvault"),cipher=try Data(contentsOf:file)
        XCTAssertTrue(cipher.starts(with:Data("RELAYHISTORY1\n".utf8)))
        XCTAssertNil(cipher.range(of:payload));XCTAssertEqual(try vault.load(),payload)
        XCTAssertEqual(keys.requests,[true,false])
        for url in [directory.deletingLastPathComponent(),directory] {
            let a=try FileManager.default.attributesOfItem(atPath:url.path)
            XCTAssertEqual((a[.posixPermissions] as? NSNumber)?.intValue,0o700)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:directory.path),["history.relayvault"])
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:file.path)[.posixPermissions] as? NSNumber)?.intValue,0o600)
        XCTAssertThrowsError(try vault.save(Data(),createKey:false));XCTAssertEqual(try Data(contentsOf:file),cipher)
    }
    func testExistingProfileFormatAndDefaultAPIStillLoadLegacyBytes()throws {
        let root=try root(),keys=SnapshotFixtureKey(),payload=Data("fictional legacy profile snapshot".utf8)
        let header=Data("RELAYPROFILE1\n".utf8)
        let box=try AES.GCM.seal(payload,using:SymmetricKey(data:keys.bytes),authenticating:header)
        let file=root.appendingPathComponent("profile.relayvault")
        try (header+box.combined!).write(to:file);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
        let profile=ProfileVault(directory:root,keys:keys)
        XCTAssertEqual(try profile.load(),payload)
        try profile.save(Data("new fictional profile".utf8))
        XCTAssertTrue(try Data(contentsOf:file).starts(with:header))
        XCTAssertEqual(try ProtectedSnapshotVault(directory:root,purpose:.profile,keys:keys).load(),Data("new fictional profile".utf8))
        XCTAssertEqual(ProfileVault.maxPayloadBytes,8*1024*1024)
    }
    func testCrossDomainCiphertextAndUnsafeHistoryParentAreRejectedWithoutHealing()throws {
        let root=try root(),keys=SnapshotFixtureKey(),relay=root.appendingPathComponent("Relay")
        try FileManager.default.createDirectory(at:relay,withIntermediateDirectories:false,attributes:[.posixPermissions:0o755])
        let vault=ProtectedSnapshotVault(directory:relay.appendingPathComponent("History"),purpose:.history,keys:keys)
        XCTAssertThrowsError(try vault.save(Data("fictional".utf8),createKey:true));XCTAssertTrue(keys.requests.isEmpty)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:relay.path)[.posixPermissions] as? NSNumber)?.intValue,0o755)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:relay.path)
        try vault.save(Data("fictional".utf8),createKey:true)
        let profile=ProfileVault(directory:root,keys:keys);try profile.save(Data("profile".utf8),createKey:true)
        let file=relay.appendingPathComponent("History/history.relayvault")
        try Data(contentsOf:root.appendingPathComponent("profile.relayvault")).write(to:file)
        let before=keys.requests
        XCTAssertThrowsError(try vault.load());XCTAssertEqual(keys.requests,before)
    }
    func testHistoryRejectsSymlinkParentAndHardlinkedCiphertext()throws {
        let root=try root(),target=root.appendingPathComponent("owned"),relay=root.appendingPathComponent("Relay"),keys=SnapshotFixtureKey()
        try FileManager.default.createDirectory(at:target,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        try FileManager.default.createSymbolicLink(at:relay,withDestinationURL:target)
        let vault=ProtectedSnapshotVault(directory:relay.appendingPathComponent("History"),purpose:.history,keys:keys)
        XCTAssertThrowsError(try vault.save(Data("fictional".utf8),createKey:true));XCTAssertTrue(keys.requests.isEmpty)
        try FileManager.default.removeItem(at:relay)
        try vault.save(Data("fictional".utf8),createKey:true)
        let file=relay.appendingPathComponent("History/history.relayvault")
        try FileManager.default.linkItem(at:file,to:root.appendingPathComponent("second-link"))
        let before=keys.requests
        XCTAssertThrowsError(try vault.load());XCTAssertEqual(keys.requests,before)
        XCTAssertThrowsError(try vault.save(Data("replacement".utf8)))
    }
}
