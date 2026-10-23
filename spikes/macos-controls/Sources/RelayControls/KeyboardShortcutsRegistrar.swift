import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

extension ControlShortcut {
    public init(_ shortcut: KeyboardShortcuts.Shortcut) {
        var modifiers: ControlModifiers = []
        if shortcut.modifiers.contains(.command) { modifiers.insert(.command) }
        if shortcut.modifiers.contains(.control) { modifiers.insert(.control) }
        if shortcut.modifiers.contains(.option) { modifiers.insert(.option) }
        if shortcut.modifiers.contains(.shift) { modifiers.insert(.shift) }
        self.init(keyCode: shortcut.carbonKeyCode, modifiers: modifiers)
    }

    public var keyboardShortcut: KeyboardShortcuts.Shortcut {
        var carbon = 0
        if modifiers.contains(.command) { carbon |= cmdKey }
        if modifiers.contains(.control) { carbon |= controlKey }
        if modifiers.contains(.option) { carbon |= optionKey }
        if modifiers.contains(.shift) { carbon |= shiftKey }
        return .init(carbonKeyCode: keyCode, carbonModifiers: carbon)
    }
}

/// Constructing this adapter does not register keys or request permissions.
/// Own one instance per namespace; it removes only its own named handlers.
@MainActor public final class KeyboardShortcutsRegistrar: HotkeyRegistering {
    private let namespace: String
    public init(namespace: String = "relay.controls.v1") { self.namespace = namespace }
    private func name(_ action: ControlAction) -> KeyboardShortcuts.Name {
        .init("\(namespace).\(action.rawValue)")
    }

    public func register(_ shortcut: ControlShortcut, for action: ControlAction, handler: @escaping @MainActor () -> Void) throws {
        guard shortcut.isSafe else { throw ControlsError.unsafeShortcut }
        guard !shortcut.keyboardShortcut.isTakenBySystem else { throw ControlsError.systemConflict }
        let name = name(action)
        unregister(action)
        KeyboardShortcuts.setShortcut(shortcut.keyboardShortcut, for: name)
        KeyboardShortcuts.enable(name)
        KeyboardShortcuts.onKeyUp(for: name, action: handler)
        guard KeyboardShortcuts.isEnabled(for: name) else {
            unregister(action)
            throw ControlsError.registrationFailed(action)
        }
    }

    public func unregister(_ action: ControlAction) {
        let name = name(action)
        KeyboardShortcuts.removeHandler(for: name)
        KeyboardShortcuts.disable(name)
        KeyboardShortcuts.setShortcut(nil, for: name)
    }
}
