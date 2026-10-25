import AppKit
import SwiftUI
import XCTest
import RelaySessionPanel
@testable import RelayPanelSession

@MainActor private final class InertSettingsLearningControls:LearningControlPreferences {
    var calls=0
    func read()async throws->LearningControlReceipt{calls+=1;throw HistoryError.unavailable}
    func deny(_ value:LearningPendingControl)async throws->LearningControlReceipt{calls+=1;throw HistoryError.unavailable}
    func commit(_ value:LearningControlRecord)async throws->LearningControlReceipt{calls+=1;throw HistoryError.unavailable}
}

@MainActor final class LearningMemorySettingsTests:XCTestCase {
    func testRenderingOffSettingsCannotReadControlsOpenHistoryOrEnableLearning()async throws{
        let controls=InertSettingsLearningControls();var sourceCalls=0,navigations=0
        let ports=LearningPersistencePorts(scope:{sourceCalls+=1;return nil},load:{sourceCalls+=1;throw HistoryError.closed},
            mutate:{_ in sourceCalls+=1;throw HistoryError.closed},affiliation:{_ in sourceCalls+=1;return nil})
        let memory=LearningMemoryCoordinator(preferences:controls,persistence:ports,canEnable:{XCTFail("Rendering cannot enable Learning");return false})
        let size=CGSize(width:680,height:540)
        let hosting=NSHostingView(rootView:LearningMemorySettingsSection(memory:memory,openHistory:{navigations+=1})
            .padding(24).frame(width:size.width,height:size.height).background(Color.black).foregroundStyle(.white).preferredColorScheme(.dark))
        let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=hosting;hosting.frame=NSRect(origin:.zero,size:size)
        window.layoutIfNeeded();hosting.layoutSubtreeIfNeeded()
        XCTAssertFalse(window.isVisible);XCTAssertEqual(memory.snapshot.phase,.off)
        XCTAssertEqual(controls.calls,0);XCTAssertEqual(sourceCalls,0);XCTAssertEqual(navigations,0)
        window.contentView=nil;window.close()
    }
}
