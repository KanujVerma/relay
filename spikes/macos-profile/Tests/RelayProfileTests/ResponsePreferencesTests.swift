import Combine
import Foundation
import XCTest
@testable import RelayProfile

private struct PreferenceFixtureKey:ProfileKeyProvider {
    func key(createIfMissing:Bool)throws->Data{Data(repeating:81,count:32)}
}
private final class HeldPreferenceStorage:ProtectedSnapshotStorage,@unchecked Sendable {
    let inner:any ProtectedSnapshotStorage
    private let condition=NSCondition()
    private var calls=[0,0,0],holdSave=false,holdLoad=false,waiting=false,rejectSave=false
    init(_ inner:any ProtectedSnapshotStorage){self.inner=inner}
    var counts:[Int]{condition.lock();defer{condition.unlock()};return calls}
    var entered:Bool{condition.lock();defer{condition.unlock()};return waiting}
    func holdNextSave(){condition.lock();holdSave=true;waiting=false;condition.unlock()}
    func holdNextLoad(){condition.lock();holdLoad=true;waiting=false;condition.unlock()}
    func rejectNextSave(){condition.lock();rejectSave=true;condition.unlock()}
    func release(){condition.lock();holdSave=false;holdLoad=false;condition.broadcast();condition.unlock()}
    private func begin(_ index:Int){
        condition.lock();defer{condition.unlock()};calls[index]+=1
        if index==1 && holdLoad || index==2 && holdSave{waiting=true;while index==1 && holdLoad || index==2 && holdSave{condition.wait()};waiting=false}
    }
    func exists()throws->Bool{begin(0);return try inner.exists()}
    func load()throws->Data{begin(1);return try inner.load()}
    func save(_ payload:Data,createKey:Bool)throws{
        begin(2);condition.lock();let reject=rejectSave;rejectSave=false;condition.unlock()
        if reject{throw ResponsePreferencesError.unavailable};try inner.save(payload,createKey:createKey)
    }
}
@MainActor private final class PreferenceFixtureReceipts:ResponsePreferencesReceiptStore {
    var value=ResponsePreferencesReceipt(enabled:false,revision:nil)
    var reads=0,writes=0
    func read()->ResponsePreferencesReceipt{reads+=1;return value}
    func commit(_ revision:UUID){writes+=1;value=ResponsePreferencesReceipt(enabled:true,revision:revision)}
    func disable(){writes+=1;value=ResponsePreferencesReceipt(enabled:false,revision:nil)}
}

@MainActor final class ResponsePreferencesTests:XCTestCase {
    private func storage()throws->HeldPreferenceStorage {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("relay-response-coordinator-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        addTeardownBlock{try? FileManager.default.removeItem(at:root)}
        return HeldPreferenceStorage(ProtectedSnapshotVault(directory:root.appendingPathComponent("Relay/ResponsePreferences"),purpose:.responsePreferences,keys:PreferenceFixtureKey()))
    }
    private func waitUntil(_ predicate:()->Bool)async throws{
        for _ in 0..<2500{if predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NSError(domain:"preference boundary not reached",code:1)
    }
    private func guide(_ name:String="Short invariants")throws->ResponseGuide{
        try ResponseGuide(name:name,focus:.coding,guidance:"Prefer concise invariants.\nDiscuss supplied input constraints.")
    }
    func testCatalogRoundTripAndStrictDuplicateUnknownIdentityTextAndBudgetDomains()async throws {
        let guide=try guide(),catalog=try ResponsePreferencesCatalog(selected:guide.id.uuidString.lowercased(),guides:[guide])
        let data=try catalog.encoded();XCTAssertEqual(try ResponsePreferencesCatalog.decode(data),catalog)
        let original=try XCTUnwrap(String(data:data,encoding:.utf8))
        XCTAssertThrowsError(try ResponsePreferencesCatalog.decode(Data(original.replacingOccurrences(of:"\"schemaVersion\":1",with:"\"schemaVersion\":1,\"schemaVersion\":1").utf8)))
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        for invalid in [true,"1",2] as [Any] {
            object["schemaVersion"]=invalid
            XCTAssertThrowsError(try ResponsePreferencesCatalog.decode(JSONSerialization.data(withJSONObject:object)))
        }
        XCTAssertThrowsError(try ResponsePreferencesCatalog.decode(Data(original.replacingOccurrences(of:"\"schemaVersion\":1",with:"\"schemaVersion\":1.0").utf8)))
        object=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any]);object["model"]="permission-is-not-a-preference"
        XCTAssertThrowsError(try ResponsePreferencesCatalog.decode(JSONSerialization.data(withJSONObject:object)))
        XCTAssertThrowsError(try ResponsePreferencesCatalog(selected:"missing",guides:[guide]))
        XCTAssertThrowsError(try ResponsePreferencesCatalog(selected:"general",guides:[guide,guide]))
        XCTAssertThrowsError(try ResponsePreferencesCatalog(selected:"general",guides:try (0..<9).map{try self.guide("Guide \($0)")}))
        XCTAssertThrowsError(try ResponseGuide(name:String(repeating:"é",count:33),focus:.automatic,guidance:"Brief"))
        XCTAssertThrowsError(try ResponseGuide(name:"Guide",focus:.automatic,guidance:String(repeating:"é",count:1025)))
        XCTAssertThrowsError(try ResponseGuide(name:"Guide",focus:.automatic,guidance:"bad\u{202e}text"))
        XCTAssertThrowsError(try ResponsePreferencesCatalog.decode(Data(repeating:32,count:32769)))
        XCTAssertThrowsError(try ResponsePreferencesCatalog.decode(Data([0xff])))
    }
    func testDefaultGeneralAndDisabledExplicitPreparationDoNoProtectedStorageWork()async throws {
        let store=try storage(),receipts=PreferenceFixtureReceipts()
        let coordinator=ResponsePreferencesCoordinator(storage:store,receipts:receipts)
        XCTAssertEqual(receipts.reads,0);XCTAssertEqual(store.counts,[0,0,0]);XCTAssertNil(coordinator.capture())
        XCTAssertEqual(coordinator.snapshot.guideName,"General");XCTAssertFalse(coordinator.snapshot.isBusy)
        try await coordinator.prepareForExplicitAction(intentID:UUID(),isCurrent:{true})
        XCTAssertEqual(store.counts,[0,0,0]);XCTAssertNil(coordinator.capture());XCTAssertEqual(receipts.writes,0)
        coordinator.useGeneral();XCTAssertEqual(store.counts,[0,0,0])
    }
    func testExplicitBuiltinFirstUseCreatesEmptyProtectedCatalogAndRestoresExistingOnly()async throws {
        let store=try storage(),receipts=PreferenceFixtureReceipts()
        let coordinator=ResponsePreferencesCoordinator(storage:store,receipts:receipts)
        try await coordinator.useBuiltin(.coding)
        let use=try XCTUnwrap(coordinator.capture());XCTAssertEqual(use.focus,.coding)
        XCTAssertTrue(coordinator.owns(use));XCTAssertEqual(store.counts[2],1)
        let catalog=try ResponsePreferencesCatalog.decode(store.load())
        XCTAssertEqual(catalog.selected,"coding");XCTAssertTrue(catalog.guides.isEmpty)
        XCTAssertEqual(receipts.value.revision,catalog.revision);XCTAssertTrue(receipts.value.enabled)
        let restored=ResponsePreferencesCoordinator(storage:store,receipts:receipts)
        try await restored.prepareForExplicitAction(intentID:UUID(),isCurrent:{true})
        XCTAssertEqual(restored.capture()?.focus,.coding);XCTAssertFalse(restored.owns(use))
        XCTAssertEqual(store.counts[2],1)
        coordinator.useGeneral();XCTAssertFalse(coordinator.owns(use));XCTAssertNil(coordinator.capture())
    }
    func testMissingRememberedCatalogFailsWithoutCreateAndGeneralRecovers()async throws {
        let store=try storage(),receipts=PreferenceFixtureReceipts();receipts.value=ResponsePreferencesReceipt(enabled:true,revision:UUID())
        let coordinator=ResponsePreferencesCoordinator(storage:store,receipts:receipts)
        do{try await coordinator.prepareForExplicitAction(intentID:UUID(),isCurrent:{true});XCTFail("missing remembered guide cannot be fabricated")}catch{}
        XCTAssertNil(coordinator.capture());XCTAssertEqual(store.counts,[1,0,0]);XCTAssertFalse(coordinator.snapshot.isBusy)
        coordinator.useGeneral();try await coordinator.prepareForExplicitAction(intentID:UUID(),isCurrent:{true})
        XCTAssertEqual(store.counts,[1,0,0]);XCTAssertFalse(receipts.value.enabled)
    }
    func testCancelledRealSaveJoinsThenRestartRejectsItsUncommittedDiskRevision()async throws {
        let store=try storage(),receipts=PreferenceFixtureReceipts(),coordinator=ResponsePreferencesCoordinator(storage:store,receipts:receipts)
        try await coordinator.useBuiltin(.coding)
        let originalReceipt=receipts.value,old=try XCTUnwrap(coordinator.capture())
        let draft=try guide(),expected=coordinator.catalog?.revision
        store.holdNextSave();defer{store.release()}
        let save=Task{try await coordinator.saveAndUse(draft,expectedCatalogRevision:expected)}
        try await waitUntil{store.entered};coordinator.cancel()
        XCTAssertTrue(coordinator.snapshot.isBusy);XCTAssertTrue(coordinator.owns(old));XCTAssertEqual(receipts.value,originalReceipt)
        do{try await coordinator.useBuiltin(.feature);XCTFail("actual old write still owns availability")}catch{}
        store.release();do{try await save.value;XCTFail("cancelled original cannot activate")}catch{}
        await coordinator.waitForQuiescence();XCTAssertFalse(coordinator.snapshot.isBusy)
        XCTAssertEqual(receipts.value,originalReceipt);XCTAssertTrue(coordinator.owns(old))
        let disk=try ResponsePreferencesCatalog.decode(store.load());XCTAssertNotEqual(disk.revision,originalReceipt.revision)
        let restarted=ResponsePreferencesCoordinator(storage:store,receipts:receipts)
        do{try await restarted.prepareForExplicitAction(intentID:UUID(),isCurrent:{true});XCTFail("stale committed bytes are not an active selection")}catch{}
        XCTAssertNil(restarted.capture());XCTAssertFalse(restarted.snapshot.isBusy)
        restarted.useGeneral();try await restarted.useBuiltin(.feature)
        XCTAssertEqual(restarted.capture()?.focus,.feature)
    }
    func testGeneralDuringHeldExistingLoadCannotBeReenabledByOldCompletion()async throws {
        let store=try storage(),receipts=PreferenceFixtureReceipts(),first=ResponsePreferencesCoordinator(storage:store,receipts:receipts)
        try await first.useBuiltin(.coding)
        let coordinator=ResponsePreferencesCoordinator(storage:store,receipts:receipts),id=UUID()
        store.holdNextLoad();defer{store.release()}
        let prepare=Task{try await coordinator.prepareForExplicitAction(intentID:id,isCurrent:{true})}
        try await waitUntil{store.entered};coordinator.useGeneral()
        XCTAssertTrue(coordinator.snapshot.isBusy);XCTAssertFalse(receipts.value.enabled);XCTAssertNil(coordinator.capture())
        store.release();do{try await prepare.value;XCTFail("retired load cannot become current")}catch{}
        await coordinator.waitForQuiescence();XCTAssertFalse(coordinator.snapshot.isBusy);XCTAssertNil(coordinator.capture())
        try await coordinator.useBuiltin(.feature);XCTAssertEqual(coordinator.capture()?.focus,.feature)
        coordinator.cancel(intentID:id);XCTAssertEqual(coordinator.capture()?.focus,.feature)
    }
    func testSaveUseDeletePreservesCatalogAndOnlyRetiresActuallySelectedGuide()async throws {
        let store=try storage(),receipts=PreferenceFixtureReceipts();var retired:[UUID]=[]
        let coordinator=ResponsePreferencesCoordinator(storage:store,receipts:receipts,onRetire:{retired.append($0.revision)})
        try await coordinator.open();let first=try guide("First")
        try await coordinator.saveAndUse(first,expectedCatalogRevision:coordinator.catalog?.revision)
        let original=try XCTUnwrap(coordinator.capture());XCTAssertTrue(retired.isEmpty)
        let second=try guide("Second")
        try await coordinator.saveAndUse(second,expectedCatalogRevision:coordinator.catalog?.revision)
        let replacement=try XCTUnwrap(coordinator.capture());XCTAssertEqual(retired,[original.revision])
        try await coordinator.delete(id:first.id,expectedCatalogRevision:try XCTUnwrap(coordinator.catalog?.revision))
        XCTAssertTrue(coordinator.owns(replacement));XCTAssertEqual(retired,[original.revision])
        try await coordinator.delete(id:second.id,expectedCatalogRevision:try XCTUnwrap(coordinator.catalog?.revision))
        XCTAssertNil(coordinator.capture());XCTAssertEqual(retired,[original.revision,replacement.revision])
        XCTAssertFalse(receipts.value.enabled);XCTAssertTrue(try ResponsePreferencesCatalog.decode(store.load()).guides.isEmpty)
    }
    func testBoundedCatalogRoundTripIncludesEightFullSizeGuidesAndEveryFocus()async throws {
        for focus in ResponseGuideFocus.allCases {
            for count in 0...8 {
                let guides=try (0..<count).map{try ResponseGuide(name:"Guide \($0) 中文",focus:focus,guidance:String(repeating:"é",count:1024))}
                let selected=guides.last?.id.uuidString.lowercased() ?? "general"
                let catalog=try ResponsePreferencesCatalog(selected:selected,guides:guides)
                XCTAssertEqual(try ResponsePreferencesCatalog.decode(catalog.encoded()),catalog)
            }
        }
    }
    func testFailedActualSaveKeepsPreviousCiphertextReceiptAndActivation()async throws {
        let store=try storage(),receipts=PreferenceFixtureReceipts(),coordinator=ResponsePreferencesCoordinator(storage:store,receipts:receipts)
        try await coordinator.useBuiltin(.coding)
        let before=try store.load(),receipt=receipts.value,old=try XCTUnwrap(coordinator.capture()),draft=try guide()
        store.rejectNextSave()
        do{try await coordinator.saveAndUse(draft,expectedCatalogRevision:coordinator.catalog?.revision);XCTFail("save failure must be reported")}catch{}
        XCTAssertEqual(try store.load(),before);XCTAssertEqual(receipts.value,receipt);XCTAssertTrue(coordinator.owns(old))
        XCTAssertFalse(coordinator.snapshot.isBusy);XCTAssertEqual(coordinator.snapshot.stage,.unavailable)
    }
    func testChangedDiskRevisionRejectsAnOldEditorWithoutOverwritingIt()async throws {
        let store=try storage(),receipts=PreferenceFixtureReceipts(),coordinator=ResponsePreferencesCoordinator(storage:store,receipts:receipts)
        try await coordinator.useBuiltin(.coding)
        let expected=coordinator.catalog?.revision,other=try ResponsePreferencesCatalog(selected:"feature")
        try store.save(other.encoded(),createKey:false)
        let before=try store.load(),writes=store.counts[2],draft=try guide()
        do{try await coordinator.saveAndUse(draft,expectedCatalogRevision:expected);XCTFail("an old editor cannot overwrite newer disk data")}catch{}
        XCTAssertEqual(try store.load(),before);XCTAssertEqual(store.counts[2],writes)
    }
    func testObsoleteCoalescedWaiterCancellationCannotRetireTheNextActualSave()async throws {
        let store=try storage(),receipts=PreferenceFixtureReceipts(),seed=ResponsePreferencesCoordinator(storage:store,receipts:receipts)
        try await seed.useBuiltin(.coding)
        let coordinator=ResponsePreferencesCoordinator(storage:store,receipts:receipts),id=UUID()
        store.holdNextLoad();defer{store.release()}
        let first=Task{try await coordinator.prepareForExplicitAction(intentID:id,isCurrent:{true})}
        try await waitUntil{store.entered}
        let obsolete=Task{try await coordinator.prepareForExplicitAction(intentID:id,isCurrent:{true})}
        for _ in 0..<5{await Task.yield()}
        var replacement:Task<Void,any Error>?,replaced=false
        let observer=coordinator.$snapshot.dropFirst().sink{state in
            if state.stage == .ready && !replaced{
                replaced=true;store.holdNextSave()
                replacement=Task{try await coordinator.useBuiltin(.feature)}
                obsolete.cancel()
            }
        }
        defer{observer.cancel()}
        store.release();try await first.value
        try await waitUntil{store.entered && replacement != nil}
        do{try await obsolete.value;XCTFail("obsolete caller was cancelled")}catch{}
        XCTAssertTrue(coordinator.snapshot.isBusy)
        store.release();try await XCTUnwrap(replacement).value
        XCTAssertEqual(coordinator.capture()?.focus,.feature);XCTAssertFalse(coordinator.snapshot.isBusy)
    }
    func testExplicitFeatureFirstUseAlsoCreatesOnlyAnEmptyProtectedCatalog()async throws {
        let store=try storage(),receipts=PreferenceFixtureReceipts(),coordinator=ResponsePreferencesCoordinator(storage:store,receipts:receipts)
        XCTAssertEqual(store.counts,[0,0,0]);try await coordinator.useBuiltin(.feature)
        XCTAssertEqual(coordinator.capture()?.focus,.feature)
        let actual=try ResponsePreferencesCatalog.decode(store.load())
        XCTAssertEqual(actual.selected,"feature");XCTAssertTrue(actual.guides.isEmpty);XCTAssertEqual(store.counts[2],1)
    }
    func testLostOriginalIntentDuringActualLoadCannotBecomeReady()async throws {
        let store=try storage(),receipts=PreferenceFixtureReceipts(),seed=ResponsePreferencesCoordinator(storage:store,receipts:receipts)
        try await seed.useBuiltin(.coding)
        let coordinator=ResponsePreferencesCoordinator(storage:store,receipts:receipts);var current=true
        store.holdNextLoad();defer{store.release()}
        let pending=Task{try await coordinator.prepareForExplicitAction(intentID:UUID(),isCurrent:{current})}
        try await waitUntil{store.entered};current=false
        XCTAssertTrue(coordinator.snapshot.isBusy);XCTAssertNil(coordinator.capture())
        store.release();do{try await pending.value;XCTFail("the original intent no longer owns readiness")}catch{}
        XCTAssertNil(coordinator.capture());XCTAssertFalse(coordinator.snapshot.isBusy)
        XCTAssertEqual(coordinator.snapshot.stage,.cancelled)
    }
    func testGeneralQueuesOriginalRetirementBeforeAnyCancellationPublication()async throws {
        let store=try storage(),receipts=PreferenceFixtureReceipts();var order:[String]=[]
        let coordinator=ResponsePreferencesCoordinator(storage:store,receipts:receipts,onRetire:{_ in order.append("retired")})
        try await coordinator.useBuiltin(.coding)
        let draft=try guide(),expected=coordinator.catalog?.revision
        store.holdNextSave();defer{store.release()}
        let pending=Task{try await coordinator.saveAndUse(draft,expectedCatalogRevision:expected)}
        try await waitUntil{store.entered}
        let observer=coordinator.$snapshot.dropFirst().sink{state in if state.stage == .cancelling{order.append("published")}}
        defer{observer.cancel()}
        coordinator.useGeneral()
        XCTAssertEqual(order.first,"retired","publication callbacks may release held EOU/PNG, so original retirement must be first")
        store.release();do{try await pending.value;XCTFail("the old save was retired")}catch{}
        XCTAssertNil(coordinator.capture());XCTAssertFalse(coordinator.snapshot.isBusy)
    }
    func testReentrantGeneralBeforeActualSaveStartsDoesNoProtectedIO()async throws {
        let store=try storage(),receipts=PreferenceFixtureReceipts(),coordinator=ResponsePreferencesCoordinator(storage:store,receipts:receipts)
        let observer=coordinator.$snapshot.dropFirst().sink{state in if state.stage == .saving{coordinator.useGeneral()}}
        defer{observer.cancel()}
        do{try await coordinator.useBuiltin(.coding);XCTFail("General retired the original before its actual IO started")}catch{}
        XCTAssertEqual(store.counts,[0,0,0]);XCTAssertNil(coordinator.capture());XCTAssertFalse(receipts.value.enabled)
        XCTAssertFalse(coordinator.snapshot.isBusy)
    }
    func testReentrantRetirementCannotActivateTheSupersededSavedGuide()async throws {
        let store=try storage(),receipts=PreferenceFixtureReceipts();var coordinator:ResponsePreferencesCoordinator!
        coordinator=ResponsePreferencesCoordinator(storage:store,receipts:receipts,onRetire:{_ in coordinator.useGeneral()})
        try await coordinator.useBuiltin(.coding)
        do{try await coordinator.useBuiltin(.feature);XCTFail("reentrant General wins over earlier activation")}catch{}
        XCTAssertNil(coordinator.capture());XCTAssertFalse(receipts.value.enabled);XCTAssertFalse(coordinator.snapshot.isBusy)
        try await coordinator.useBuiltin(.feature);XCTAssertEqual(coordinator.capture()?.focus,.feature)
    }
}
