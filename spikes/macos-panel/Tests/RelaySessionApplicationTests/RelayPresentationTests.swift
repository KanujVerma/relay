import XCTest
import AppKit
import RelayControls
import RelayScreenContext
@testable import RelayPanelSession

@MainActor final class RelayPresentationTests:XCTestCase {
    func testStartNeedsRealOwnerAdmissionSourceAndConsent() {
        var state=RelaySessionPresentation(ownerCanStart:true)
        XCTAssertFalse(state.allows(.start))
        state.hasSelectedSource=true;XCTAssertFalse(state.allows(.start))
        state.authorizedConversation=true;XCTAssertTrue(state.allows(.start))
        state.preparing=true;XCTAssertFalse(state.allows(.start));XCTAssertTrue(state.allows(.cancelPreparation))
        state.preparing=false;state.ownerCanStart=false;XCTAssertFalse(state.allows(.start))
    }
    func testAnswerActionsCannotRevivePausedOrStoppingContentAndEndStaysAvailable() {
        var state=RelaySessionPresentation(running:true,hasQuestion:true,hasAnswer:true)
        XCTAssertTrue(state.allows(.help));XCTAssertTrue(state.allows(.copy));XCTAssertTrue(state.allows(.expand))
        state.stopping=true
        XCTAssertFalse(state.allows(.help));XCTAssertFalse(state.allows(.copy));XCTAssertTrue(state.allows(.end))
        state.stopping=false;state.running=false;state.paused=true
        XCTAssertFalse(state.allows(.copy));XCTAssertFalse(state.allows(.resume))
        state.ownerCanResume=true;state.hasSelectedSource=true;state.authorizedConversation=true
        XCTAssertTrue(state.allows(.resume))
    }
    func testPreparationNeverInventsOrClampsInvalidProgress() {
        XCTAssertNil(RelayPreparationPresentation(title:"Checking",fraction:nil).fraction)
        XCTAssertNil(RelayPreparationPresentation(title:"Checking",fraction:.nan).fraction)
        XCTAssertNil(RelayPreparationPresentation(title:"Checking",fraction:1.1).fraction)
        XCTAssertEqual(RelayPreparationPresentation(title:"Preparing",fraction:0.45).fraction,0.45)
    }
    func testReopenedHomeUsesCurrentSessionInsteadOfOfferingAnotherStart() {
        var state=RelaySessionPresentation(running:true,ownerCanStart:true)
        XCTAssertTrue(state.allows(.showSession));XCTAssertFalse(state.allows(.start))
        state.running=false;state.paused=true;state.hasSelectedSource=true;state.authorizedConversation=true;state.ownerCanResume=true
        XCTAssertTrue(state.allows(.showSession));XCTAssertTrue(state.allows(.resume));XCTAssertFalse(state.allows(.start))
        state.paused=false;state.stopping=true
        XCTAssertTrue(state.allows(.showSession));XCTAssertFalse(state.allows(.resume))
        state.stopping=false
        XCTAssertFalse(state.allows(.showSession))
    }
    // Swift 6.2's isolated-deinit backdeploy path aborts from synchronous XCTest
    // invocation (swiftlang/swift#85663). Keep the real owner inside a test task.
    func testPresentationAcceptsAnExplicitMicrophoneOnlySourceWithoutStartingIt() async {
        let model=SessionApplicationModel(arguments:["relay"])
        model.selectedBundleID="";model.microphoneEnabled=true;model.authorizedConversation=true
        XCTAssertTrue(model.relayPresentation.hasSelectedSource)
        XCTAssertFalse(model.relayPresentation.hasRemoteSource)
        XCTAssertTrue(model.relayPresentation.allows(.start))
        model.microphoneEnabled=false
        XCTAssertFalse(model.relayPresentation.hasSelectedSource)
        XCTAssertFalse(model.relayPresentation.allows(.start))
        model.selectedBundleID="com.example.synthetic"
        XCTAssertTrue(model.relayPresentation.hasRemoteSource)
        XCTAssertTrue(model.relayPresentation.hasSelectedSource)
        XCTAssertFalse(model.running);XCTAssertNil(model.currentSessionID)
    }
    func testScreenLabelRequiresAnActualCurrentSelectionWithoutOpeningThePicker() async {
        let model=SessionApplicationModel(arguments:["relay"])
        let screen=model.screen
        XCTAssertEqual(model.relayContextLabel,"Screen off")
        screen.coordinator.enable();screen.retireCurrentRequest()
        XCTAssertTrue(screen.isEnabled);XCTAssertNil(screen.selectedSource)
        XCTAssertEqual(model.relayContextLabel,"Choose a window")
        screen.coordinator.select(ScreenSource(windowID:123,bundleID:"com.example.synthetic",processID:1,label:"Synthetic editor"))
        screen.retireCurrentRequest()
        XCTAssertEqual(model.relayContextLabel,"Window selected")
        screen.coordinator.sourceUnavailable(.closed)
        XCTAssertTrue(screen.isEnabled);XCTAssertNil(screen.selectedSource)
        XCTAssertEqual(model.relayContextLabel,"Choose a window")
    }
    func testFixtureHomeReopenDoesNotAutomaticallyStartAnotherSession() {
        let shell=RelayWindowShell()
        XCTAssertTrue(shell.claimFixtureStart())
        shell.expanded=false
        XCTAssertFalse(shell.claimFixtureStart())
    }
    func testCancellationCleanupAndRevokedConsentDoNotOfferAnotherStart() {
        var state=RelaySessionPresentation(preparing:true,cancellingPreparation:true,hasSelectedSource:true,authorizedConversation:true,ownerCanStart:true)
        XCTAssertFalse(state.allows(.start));XCTAssertFalse(state.allows(.retryPreparation));XCTAssertFalse(state.allows(.cancelPreparation));XCTAssertTrue(state.allows(.end))
        state.preparing=false;state.cancellingPreparation=false;state.authorizedConversation=false
        XCTAssertFalse(state.allows(.retryPreparation))
    }
    func testCommandRouterUsesExistingPortsAndRechecksStateAtDispatch()async {
        var state=RelaySessionPresentation(running:true,hasQuestion:true,hasAnswer:true)
        var controls:[ControlAction]=[],starts=0,context=0,shown=0
        let router=RelayCommandRouter(state:{state},control:{controls.append($0)},start:{starts+=1},cancelPreparation:{},retryPreparation:{},openContext:{context+=1},openSettings:{},showSession:{shown+=1})
        router.perform(.showSession);XCTAssertEqual(shown,1)
        router.perform(.help);router.perform(.copy);router.perform(.expand)
        XCTAssertEqual(controls,[.requestHelp,.copyAnswer,.expandAnswer])
        state.running=false;state.paused=true
        router.perform(.copy);router.perform(.help);router.perform(.context)
        XCTAssertEqual(controls.count,3);XCTAssertEqual(context,1)
        router.perform(.end);XCTAssertEqual(controls.last,.endSession)
        state.paused=false;state.hasSelectedSource=true;state.authorizedConversation=true;state.ownerCanStart=true
        if let operation=router.perform(.start){await operation.value}
        XCTAssertEqual(starts,1)
    }
    func testActualFixtureCommandsKeepHelpAndRealPauseResumeEnd()async throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model=SessionApplicationModel(arguments:["relay","--fixture-suite","coding","--repository",root.path])
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:690,height:500),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;model.attachWindow(window,scrollView:nil)
        let router=RelayCommandRouter(state:{model.relayPresentation},control:model.performWindowAction,start:{await model.start()},cancelPreparation:model.cancelPreparation,retryPreparation:{await model.retryPreparation()},openContext:{},openSettings:{},showSession:{})
        if let operation=router.perform(.start){await operation.value}
        try await waitUntil{model.snapshot.card != nil}
        router.perform(.expand);XCTAssertTrue(model.expanded)
        let replacement=model.snapshot.replacement
        router.perform(.help);try await waitUntil{model.snapshot.replacement>replacement && model.snapshot.card != nil}
        let original=model.currentSessionID
        router.perform(.pause);XCTAssertFalse(model.running);XCTAssertNil(model.snapshot.card);XCTAssertFalse(model.canResume)
        try await waitUntil{model.canResume}
        router.perform(.resume);try await waitUntil{model.running && model.snapshot.card != nil}
        XCTAssertNotEqual(model.currentSessionID,original)
        router.perform(.end);try await waitUntil{!model.stopping && !model.running}
        XCTAssertNil(model.snapshot.card)
        window.close();await model.stop()
    }
    private func waitUntil(_ predicate:()->Bool)async throws {
        for _ in 0..<2000{if predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        XCTFail("Fixture UI command did not finish")
    }
}
