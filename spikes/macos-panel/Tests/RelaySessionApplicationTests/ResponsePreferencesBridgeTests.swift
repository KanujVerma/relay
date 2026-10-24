import Foundation
import XCTest
import RelayProfile
import RelayNativeSession
import RelaySessionPanel
import RelayContextComposition
@testable import RelayPanelSession

private final class BridgePreferenceStorage:ProtectedSnapshotStorage,@unchecked Sendable {
    private let lock=NSLock();private var bytes:Data?
    func exists()throws->Bool{lock.withLock{bytes != nil}}
    func load()throws->Data{try lock.withLock{guard let bytes else{throw ProfileError.unavailable};return bytes}}
    func save(_ payload:Data,createKey:Bool)throws{lock.withLock{bytes=payload}}
}
@MainActor private final class BridgePreferenceReceipts:ResponsePreferencesReceiptStore {
    private var state=ResponsePreferencesReceipt(enabled:false,revision:nil)
    func read()->ResponsePreferencesReceipt{state}
    func commit(_ revision:UUID){state=ResponsePreferencesReceipt(enabled:true,revision:revision)}
    func disable(){state=ResponsePreferencesReceipt(enabled:false,revision:nil)}
}
@MainActor final class ResponsePreferencesBridgeTests:XCTestCase {
    private func controller()throws->NativeAssistantSessionController{
        let controller=NativeAssistantSessionController(),opened=try controller.begin(enqueue:{_ in})
        try controller.completeOpen(opened);return controller
    }
    private func issue(_ controller:NativeAssistantSessionController)throws->PanelRequestBinding{
        let value=try controller.issueUserQuestion(expectedLease:try XCTUnwrap(controller.authority.snapshot()),intent:.ask,question:"Explain event loops.",baseRequestID:nil,enqueue:{_ in})
        return PanelRequestBinding(lease:value.lease,requestID:value.requestID,eventSequence:value.anchorEventSequence)
    }
    func testFrozenOriginalGuideCannotBeReplacedDuringHeldContextAndRetirementIsFirst()async throws {
        var bridge:ResponsePreferencesRequestBridge?,frames:[[String:Any]]=[]
        let preferences=ResponsePreferencesCoordinator(storage:BridgePreferenceStorage(),receipts:BridgePreferenceReceipts(),onRetire:{original in
            do{try bridge?.retire(original)}catch{XCTFail("original retirement channel failed")}
        })
        try await preferences.useBuiltin(.coding)
        bridge=ResponsePreferencesRequestBridge(capture:preferences.capture,owns:preferences.owns,send:{data in frames.append(try JSONSerialization.jsonObject(with:data) as! [String:Any])},isCurrent:{true})
        let scope=try controller(),original=try issue(scope),use=try XCTUnwrap(preferences.capture())
        try bridge?.freeze(original)
        try await preferences.useBuiltin(.feature)
        XCTAssertEqual(frames.first?["kind"] as? String,"response_preferences_retired")
        XCTAssertEqual(frames.first?["preferencesRevision"] as? String,use.revision.uuidString.lowercased())
        try bridge?.sendOffer(for:original)
        XCTAssertEqual(frames.count,1,"a retired snapshot cannot be replaced by the current guide on an already frozen request")
        XCTAssertFalse(bridge?.permits(original,revision:use.revision) ?? true)
        XCTAssertTrue(bridge?.permits(original,revision:nil) ?? false)
        let fresh=try issue(scope),current=try XCTUnwrap(preferences.capture())
        try bridge?.freeze(fresh);try bridge?.sendOffer(for:fresh)
        XCTAssertEqual(frames.last?["requestID"] as? String,fresh.requestID.uuidString.lowercased())
        XCTAssertEqual(frames.last?["eventSequence"] as? UInt64,fresh.eventSequence)
        XCTAssertEqual(frames.last?["preferencesRevision"] as? String,current.revision.uuidString.lowercased())
        try bridge?.retire(use)
        XCTAssertTrue(bridge?.permits(fresh,revision:current.revision) ?? false)
    }
    func testUsedMarkerRequiresActualOfferAndCurrentOriginalSnapshot()async throws {
        let preferences=ResponsePreferencesCoordinator(storage:BridgePreferenceStorage(),receipts:BridgePreferenceReceipts())
        try await preferences.useBuiltin(.coding)
        var frames=0
        let bridge=ResponsePreferencesRequestBridge(capture:preferences.capture,owns:preferences.owns,send:{_ in frames+=1},isCurrent:{true})
        let scope=try controller(),binding=try issue(scope),snapshot=try XCTUnwrap(preferences.capture())
        try bridge.freeze(binding)
        XCTAssertFalse(bridge.permits(binding,revision:snapshot.revision))
        try bridge.sendOffer(for:binding);try bridge.sendOffer(for:binding)
        XCTAssertEqual(frames,1);XCTAssertTrue(bridge.permits(binding,revision:snapshot.revision))
        XCTAssertFalse(bridge.permits(binding,revision:UUID()))
        bridge.retireNative(binding)
        XCTAssertFalse(bridge.permits(binding,revision:snapshot.revision));XCTAssertTrue(bridge.permits(binding,revision:nil))
    }
    func testFailedRetirementChannelWithholdsHeldRequestInsteadOfFallingBack()async throws {
        let preferences=ResponsePreferencesCoordinator(storage:BridgePreferenceStorage(),receipts:BridgePreferenceReceipts())
        try await preferences.useBuiltin(.coding)
        let bridge=ResponsePreferencesRequestBridge(capture:preferences.capture,owns:preferences.owns,send:{_ in throw PanelBridgeError.closed},isCurrent:{true})
        let binding=try issue(controller()),snapshot=try XCTUnwrap(preferences.capture())
        try bridge.freeze(binding);XCTAssertThrowsError(try bridge.retire(snapshot))
        XCTAssertThrowsError(try bridge.sendOffer(for:binding));XCTAssertFalse(bridge.permits(binding,revision:snapshot.revision))
    }
    func testDefaultGeneralSendsNothingAndClosedOldBridgeCannotOfferForReplacementScope()async throws {
        let preferences=ResponsePreferencesCoordinator(storage:BridgePreferenceStorage(),receipts:BridgePreferenceReceipts())
        var frames=0,current=true
        let bridge=ResponsePreferencesRequestBridge(capture:preferences.capture,owns:preferences.owns,send:{_ in frames+=1},isCurrent:{current})
        let original=try issue(controller());try bridge.freeze(original);try bridge.sendOffer(for:original)
        XCTAssertEqual(frames,0)
        try await preferences.useBuiltin(.coding)
        let scope=try controller(),first=try issue(scope);try bridge.freeze(first);try bridge.sendOffer(for:first)
        XCTAssertEqual(frames,1)
        current=false;bridge.close()
        let replacement=try issue(controller());try bridge.freeze(replacement);try bridge.sendOffer(for:replacement)
        XCTAssertEqual(frames,1);XCTAssertFalse(bridge.permits(first,revision:try XCTUnwrap(preferences.capture()).revision))
    }
}
