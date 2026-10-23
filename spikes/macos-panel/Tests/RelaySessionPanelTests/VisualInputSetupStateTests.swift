import Foundation
import XCTest
@testable import RelaySessionPanel

@MainActor private final class HeldVisualControl {
    struct Call {let action:VisualInputAction;let update:@Sendable(VisualInputResponse)->Void;let continuation:CheckedContinuation<VisualInputResponse,any Error>;let id:UUID}
    var calls:[Call]=[]
    func send(_ action:VisualInputAction,_ update:@escaping @Sendable(VisualInputResponse)->Void)async throws->VisualInputResponse {
        try await withCheckedThrowingContinuation{calls.append(Call(action:action,update:update,continuation:$0,id:UUID()))}
    }
    func finish(_ index:Int,status:String,reason:String)throws {
        let call=calls[index]
        let data=try JSONSerialization.data(withJSONObject:["schemaVersion":1,"kind":"visual_input_response","requestID":call.id.uuidString.lowercased(),"action":call.action.rawValue,"resultRevision":2,"status":status,"reasonCode":reason,"model":"gpt-fixture"])
        call.continuation.resume(returning:try VisualInputResponse(data:data))
    }
}
@MainActor final class VisualInputSetupStateTests:XCTestCase {
    private func waitUntil(_ predicate:()->Bool)async throws {
        for _ in 0..<100 {if predicate(){return};try await Task.sleep(for:.milliseconds(1))}
        XCTFail("synthetic visual control did not progress")
    }
    func testDisableRetiresOffersBeforeIOAndKeepsBusyUntilOriginalProbeActuallyFinishes()async throws {
        let control=HeldVisualControl();let state=VisualInputSetupState();var retired=0
        state.onRetireImages={retired+=1}
        state.beginVerification(using:control.send)
        XCTAssertTrue(state.isBusy);XCTAssertFalse(state.mayOfferImages)
        try await waitUntil{control.calls.count==1}
        state.disable(using:control.send)
        XCTAssertFalse(state.mayOfferImages);XCTAssertTrue(state.isBusy);XCTAssertGreaterThan(retired,0)
        try await waitUntil{control.calls.count==2}
        try control.finish(1,status:"disabled",reason:"user_disabled")
        for _ in 0..<5{await Task.yield()}
        XCTAssertTrue(state.isBusy)
        // Even an old successful terminal cannot re-enable a disabled scope.
        try control.finish(0,status:"verified",reason:"probe_verified")
        await state.waitForQuiescence()
        XCTAssertFalse(state.isBusy);XCTAssertFalse(state.mayOfferImages)
    }
    func testPassiveStatusCannotEnableImagesAndHelperReplacementFencesLateVerify()async throws {
        let control=HeldVisualControl();let state=VisualInputSetupState()
        XCTAssertFalse(state.isBusy);XCTAssertFalse(state.mayOfferImages)
        state.refreshStatus(using:control.send);try await waitUntil{control.calls.count==1}
        try control.finish(0,status:"verified",reason:"current_status");await state.waitForQuiescence()
        XCTAssertEqual(state.status,.verified);XCTAssertFalse(state.mayOfferImages)
        state.beginVerification(using:control.send);try await waitUntil{control.calls.count==2}
        state.retireForHelperChange()
        try control.finish(1,status:"verified",reason:"probe_verified");await state.waitForQuiescence()
        XCTAssertFalse(state.mayOfferImages);XCTAssertNil(state.model)
    }
    func testOnlyCurrentExplicitVerifyTerminalAllowsLocalImageOffers()async throws {
        let control=HeldVisualControl();let state=VisualInputSetupState()
        state.beginVerification(using:control.send);try await waitUntil{control.calls.count==1}
        state.beginVerification(using:control.send)
        XCTAssertEqual(control.calls.count,1)
        try control.finish(0,status:"verified",reason:"probe_verified");await state.waitForQuiescence()
        XCTAssertTrue(state.mayOfferImages);XCTAssertEqual(state.model,"gpt-fixture")
        state.retireForHelperChange();XCTAssertFalse(state.mayOfferImages)
    }
}
