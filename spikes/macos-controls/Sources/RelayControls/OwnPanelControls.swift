import AppKit

/// Composes own-window actions with the real session owner. The current-answer
/// closure must return nil after the host retires presentation authority.
@MainActor public final class OwnPanelControls: ControlActionHandling {
    private weak var window: NSWindow?
    private let sessionActions: any ControlActionHandling
    private let answerText: @MainActor () -> String?
    private let expandAnswer: @MainActor () -> Void
    private let scrollAnswer: @MainActor (Double) -> Void
    private let copyText: @MainActor (String) -> Void

    public init(window: NSWindow?, sessionActions: any ControlActionHandling,
                answerText: @escaping @MainActor () -> String?,
                expandAnswer: @escaping @MainActor () -> Void,
                scrollAnswer: @escaping @MainActor (Double) -> Void,
                copyText: @escaping @MainActor (String) -> Void = { text in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }) {
        self.window = window
        self.sessionActions = sessionActions
        self.answerText = answerText
        self.expandAnswer = expandAnswer
        self.scrollAnswer = scrollAnswer
        self.copyText = copyText
    }

    public func perform(_ action: ControlAction) throws {
        switch action {
        case .showPanel:
            guard let window else { throw ControlsError.actionFailed(action) }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        case .hidePanel: window?.orderOut(nil)
        case .expandAnswer: if answerText() != nil { expandAnswer() }
        case .copyAnswer: if let text = answerText() { copyText(text) }
        case .scrollUp: if answerText() != nil { scrollAnswer(-160) }
        case .scrollDown: if answerText() != nil { scrollAnswer(160) }
        case .movePanelLeft, .movePanelRight:
            guard let window, let screen = window.screen else { throw ControlsError.actionFailed(action) }
            window.setFrame(Self.movedFrame(window.frame, deltaX: action == .movePanelLeft ? -80 : 80, visibleFrame: screen.visibleFrame), display: true)
        default: try sessionActions.perform(action)
        }
    }

    nonisolated static func movedFrame(_ frame: CGRect, deltaX: CGFloat, visibleFrame: CGRect) -> CGRect {
        var moved = frame
        moved.origin.x = min(max(frame.origin.x + deltaX, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - frame.width))
        moved.origin.y = min(max(frame.origin.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - frame.height))
        return moved
    }
}
