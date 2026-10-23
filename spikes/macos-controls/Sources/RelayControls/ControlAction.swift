import Foundation

public enum ControlAction: String, CaseIterable, Codable, Sendable {
    case requestHelp, showPanel, hidePanel, pause, resume, endSession
    case expandAnswer, copyAnswer, scrollUp, scrollDown, movePanelLeft, movePanelRight

    public var title: String {
        switch self {
        case .requestHelp: "Help with current context"
        case .showPanel: "Show and focus panel"
        case .hidePanel: "Hide panel"
        case .pause: "Pause session"
        case .resume: "Resume session"
        case .endSession: "End session"
        case .expandAnswer: "Expand current answer"
        case .copyAnswer: "Copy current answer"
        case .scrollUp: "Scroll answer up"
        case .scrollDown: "Scroll answer down"
        case .movePanelLeft: "Move panel left"
        case .movePanelRight: "Move panel right"
        }
    }
}

public struct ControlModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = Self(rawValue: 1)
    public static let control = Self(rawValue: 2)
    public static let option = Self(rawValue: 4)
    public static let shift = Self(rawValue: 8)
}

public struct ControlShortcut: Hashable, Codable, Sendable {
    public let keyCode: Int
    public let modifiers: ControlModifiers
    public init(keyCode: Int, modifiers: ControlModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
    public var isSafe: Bool {
        (0...127).contains(keyCode)
            && modifiers.rawValue & ~15 == 0
            && !modifiers.intersection([.command, .control]).isEmpty
    }
}

public enum ControlsError: Error, Equatable, LocalizedError, Sendable {
    case unsafeShortcut, duplicateShortcut(ControlAction), systemConflict
    case registrationFailed(ControlAction), actionFailed(ControlAction), closed
    public var errorDescription: String? {
        switch self {
        case .unsafeShortcut: "Use Command or Control with a key. Unmodified typing keys are unavailable."
        case .duplicateShortcut(let action): "This shortcut is already used by \(action.title)."
        case .systemConflict: "This shortcut is used by macOS. Choose another in Keyboard settings."
        case .registrationFailed(let action): "Could not register \(action.title). Another app may use this shortcut."
        case .actionFailed(let action): "\(action.title) could not complete. Check the session state."
        case .closed: "These controls have been shut down."
        }
    }
}

/// The application's real session/presentation controller implements this port.
/// Pause/end must synchronously retire capture/model admission and presentation
/// authority before returning, then finish asynchronous hardware teardown.
/// Returning successfully must never mean only changing a timer or UI flag.
@MainActor public protocol ControlActionHandling: AnyObject {
    func perform(_ action: ControlAction) throws
}

@MainActor public protocol HotkeyRegistering: AnyObject {
    func register(_ shortcut: ControlShortcut, for action: ControlAction, handler: @escaping @MainActor () -> Void) throws
    func unregister(_ action: ControlAction)
}
