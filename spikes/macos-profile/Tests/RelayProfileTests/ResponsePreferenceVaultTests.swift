import Foundation
import Security
import XCTest
@testable import RelayProfile

private final class ResponseVaultKey:ProfileKeyProvider,@unchecked Sendable {
    var calls:[Bool]=[]
    func key(createIfMissing:Bool)throws->Data{calls.append(createIfMissing);return Data(repeating:73,count:32)}
}
private final class ResponseVaultSecurity:SecurityItemClient,@unchecked Sendable {
    var queries:[[String:Any]]=[]
    func copy(_ query:[String:Any])->(OSStatus,Data?){queries.append(query);return(errSecItemNotFound,nil)}
    func add(_ query:[String:Any])->OSStatus{queries.append(query);return errSecSuccess}
}
final class ResponsePreferenceVaultTests:XCTestCase {
    private func root()throws->URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("relay-preference-vault-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        addTeardownBlock{try? FileManager.default.removeItem(at:url)};return url
    }
    func testExactNewKeyPurposeHasNoConstructionLookupAndPreservesOtherIdentities()throws {
        for (purpose,service,account) in [(KeychainKeyPurpose.responsePreferences,"com.relay.response-preferences.v1","local-response-preferences-aes256"),
             (.profile,"com.relay.profile.v1","local-profile-aes256"),(.chatGPTCredentials,"com.relay.chatgpt-auth.v1","local-chatgpt-aes256"),(.history,"com.relay.history.v1","local-history-aes256")] {
            let security=ResponseVaultSecurity(),key=KeychainProfileKey(purpose:purpose,client:security,random:{Data(repeating:73,count:32)})
            XCTAssertTrue(security.queries.isEmpty);_=try key.key(createIfMissing:true)
            XCTAssertEqual(security.queries.count,2)
            XCTAssertTrue(security.queries.allSatisfy{($0[kSecAttrService as String] as? String)==service && ($0[kSecAttrAccount as String] as? String)==account})
        }
    }
    func testExplicitCiphertextPurposeAndExistingOnlyReadCannotCreateOrReadOtherDomains()throws {
        let root=try root(),directory=root.appendingPathComponent("Relay/ResponsePreferences"),keys=ResponseVaultKey()
        let store=ProtectedSnapshotVault(directory:directory,purpose:.responsePreferences,keys:keys)
        XCTAssertTrue(keys.calls.isEmpty);XCTAssertFalse(try store.exists());XCTAssertThrowsError(try store.load())
        XCTAssertTrue(keys.calls.isEmpty);XCTAssertFalse(FileManager.default.fileExists(atPath:directory.path))
        let data=Data("Fictional preference: explain invariants briefly.".utf8)
        try store.save(data,createKey:true)
        let file=directory.appendingPathComponent("preferences.relayvault"),encrypted=try Data(contentsOf:file)
        XCTAssertTrue(encrypted.starts(with:Data("RELAYPREFERENCES1\n".utf8)));XCTAssertNil(encrypted.range(of:data))
        XCTAssertEqual(try store.load(),data);XCTAssertEqual(keys.calls,[true,false])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:directory.path),["preferences.relayvault"])
        let profile=ProfileVault(directory:root,keys:keys);try profile.save(Data("fictional profile".utf8),createKey:true)
        try Data(contentsOf:root.appendingPathComponent("profile.relayvault")).write(to:file)
        let before=keys.calls;XCTAssertThrowsError(try store.load());XCTAssertEqual(keys.calls,before)
    }
    func testUnsafeParentAndMissingAncestryAreRejectedWithoutHealingOrKeyWork()throws {
        let root=try root(),relay=root.appendingPathComponent("Relay"),keys=ResponseVaultKey()
        try FileManager.default.createDirectory(at:relay,withIntermediateDirectories:false,attributes:[.posixPermissions:0o755])
        let store=ProtectedSnapshotVault(directory:relay.appendingPathComponent("ResponsePreferences"),purpose:.responsePreferences,keys:keys)
        XCTAssertThrowsError(try store.save(Data("fictional guide".utf8),createKey:true))
        XCTAssertTrue(keys.calls.isEmpty)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:relay.path)[.posixPermissions] as? NSNumber)?.intValue,0o755)
        let nested=ProtectedSnapshotVault(directory:root.appendingPathComponent("missing/Relay/ResponsePreferences"),purpose:.responsePreferences,keys:keys)
        XCTAssertThrowsError(try nested.save(Data("fictional guide".utf8),createKey:true))
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("missing").path));XCTAssertTrue(keys.calls.isEmpty)
    }
}
