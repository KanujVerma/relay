import Combine
import Foundation
import XCTest
import RelayAccount
import RelayProfile
@testable import RelayPanelSession

private struct PeerReentryKey:ProfileKeyProvider{func key(createIfMissing:Bool)throws->Data{Data(repeating:95,count:32)}}
@MainActor private final class PeerReentryContextPreferences:SessionContextUsePreferences{var useInSessions=false}
@MainActor final class PeerModelPreferenceReentryProbeTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func waitUntil(_ predicate:()->Bool)async throws{
        for _ in 0..<2500{if predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NSError(domain:"actual model preference publication boundary not reached",code:1)
    }
    private func model()throws->SessionApplicationModel{
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-peer-reentry-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        addTeardownBlock{try? FileManager.default.removeItem(at:directory)}
        let repository=root
        let ports=AccountApplicationPorts(storage:AccountStorage(sharedDirectory:directory.appendingPathComponent("Relay"),keys:PeerReentryKey()),preferences:FixtureChatGPTPlanPreferences(),control:{runtime,bootstrap in
            PipeAccountPort(python:runtime.executable,repository:runtime.resourceRoot,bootstrap:bootstrap,pythonArguments:[repository.appendingPathComponent("tests/support/account_backend_helper.py").path,"--synthetic-account-test","--log",directory.appendingPathComponent("control.jsonl").path])
        },openBrowser:{_ in false},sessionArguments:{runtime,mode in
            mode == .protectedOAuth ? [repository.appendingPathComponent("tests/support/account_product_helper.py").path,"--synthetic-product-account-test","--log",directory.appendingPathComponent("requests.jsonl").path]:runtime.arguments
        })
        let value=SessionApplicationModel(arguments:["Relay","--fixture-suite","coding","--repository",root.path,"--python",try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"]),"--role","analytics"],contextPreferences:PeerReentryContextPreferences(),responsePreferencesStorage:ApplicationPreferenceStorage(),responsePreferencesReceipts:ApplicationPreferenceReceipts(),accountPorts:ports)
        addTeardownBlock{await value.shutdown()};return value
    }
    func testGeneralAfterActualFinishedPublicationClearsModelCardControl()async throws{
        let model=try model();try await model.responsePreferences.useBuiltin(.coding)
        let original=try XCTUnwrap(model.responsePreferences.capture())
        await model.start();try await waitUntil{model.snapshot.card != nil}
        XCTAssertEqual(model.snapshot.responsePreferencesRevision,original.revision)
        model.responsePreferences.useGeneral();await Task.yield()
        XCTAssertNil(model.snapshot.card);XCTAssertNil(model.snapshot.responsePreferencesRevision)
        XCTAssertNil(model.responsePreferences.capture());XCTAssertTrue(model.running)
        print("PEER model reentry control finalCard",model.snapshot.card != nil,"finalGUID",model.snapshot.responsePreferencesRevision != nil,"status",model.snapshot.status)
    }
    func testGeneralDuringModelPublishedWillSetCannotRestoreRetiredGuideCard()async throws{
        let model=try model();try await model.responsePreferences.useBuiltin(.coding)
        let original=try XCTUnwrap(model.responsePreferences.capture())
        var retired=false,nestedClear=false
        let subscription=model.$snapshot.dropFirst().sink{incoming in
            if retired,incoming.card==nil,incoming.responsePreferencesRevision==nil,incoming.status=="Response guide changed. Ask again."{nestedClear=true}
            guard !retired,incoming.card != nil,incoming.responsePreferencesRevision==original.revision else{return}
            retired=true;model.responsePreferences.useGeneral()
        }
        defer{subscription.cancel()}
        await model.start();try await waitUntil{retired}
        await Task.yield();try await Task.sleep(for:.milliseconds(100))
        print("PEER model reentry triggered",retired,"nestedClearPublished",nestedClear,"finalCard",model.snapshot.card != nil,"finalOldGUID",model.snapshot.responsePreferencesRevision==original.revision,"activeGuide",model.responsePreferences.capture() != nil,"usedLabel",model.usedResponseGuideName != nil,"status",model.snapshot.status)
        XCTAssertTrue(retired);XCTAssertTrue(nestedClear)
        XCTAssertNil(model.responsePreferences.capture());XCTAssertNil(model.usedResponseGuideName)
        XCTAssertNil(model.snapshot.card,"Outer published assignment must not restore a card after original guide retirement")
        XCTAssertNil(model.snapshot.responsePreferencesRevision)
        XCTAssertEqual(model.snapshot.status,"Response guide changed. Ask again.")
        XCTAssertTrue(model.running)
    }
}
