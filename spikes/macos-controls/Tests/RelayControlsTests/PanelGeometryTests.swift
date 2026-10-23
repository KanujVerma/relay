import AppKit
import Testing
@testable import RelayControls

@Suite struct PanelGeometryTests {
    @Test func movingPanelStaysInsideItsSelectedDisplay() {
        let visible = CGRect(x: -1000, y: 50, width: 1000, height: 800)
        let moved = OwnPanelControls.movedFrame(CGRect(x: -980, y: 90, width: 400, height: 300), deltaX: -80, visibleFrame: visible)
        #expect(moved.origin == CGPoint(x: -1000, y: 90))
        let right = OwnPanelControls.movedFrame(moved, deltaX: 2000, visibleFrame: visible)
        #expect(right.origin.x == -400)
    }

    @MainActor @Test func copyExpandAndScrollUseOnlyTheCurrentAnswerAndEndClearsIt() throws {
        let host = SessionHarness()
        var copied: [String] = []
        var expanded = 0
        var scrolls: [Double] = []
        let panel = OwnPanelControls(window: nil, sessionActions: host, answerText: { host.answer },
            expandAnswer: { expanded += 1 }, scrollAnswer: { scrolls.append($0) }, copyText: { copied.append($0) })
        try panel.perform(.copyAnswer)
        try panel.perform(.expandAnswer)
        try panel.perform(.scrollDown)
        try panel.perform(.endSession)
        try panel.perform(.copyAnswer)
        try panel.perform(.expandAnswer)
        try panel.perform(.scrollUp)
        #expect(copied == ["old answer"])
        #expect(expanded == 1)
        #expect(scrolls == [160])
        #expect(!host.acceptsCapture)
        #expect(!host.acceptsModel)
    }
}
