import Foundation
import Observation

@MainActor @Observable public final class ControlsController {
    public private(set) var isEnabled = false
    public private(set) var shortcuts: [ControlAction: ControlShortcut] = [:]
    public private(set) var lastError: ControlsError?
    private let registrar: any HotkeyRegistering
    private let actionPort: any ControlActionHandling
    private var leases: [ControlAction: UUID] = [:]
    private var isClosed = false

    public init(registrar: any HotkeyRegistering, actionPort: any ControlActionHandling) {
        self.registrar = registrar
        self.actionPort = actionPort
    }

    public func validate(_ shortcut: ControlShortcut, for action: ControlAction) throws {
        guard shortcut.isSafe else { throw ControlsError.unsafeShortcut }
        if let duplicate = ControlAction.allCases.first(where: { $0 != action && shortcuts[$0] == shortcut }) {
            throw ControlsError.duplicateShortcut(duplicate)
        }
    }

    public func configure(_ shortcut: ControlShortcut?, for action: ControlAction) throws {
        guard !isClosed else { throw ControlsError.closed }
        if let shortcut { try validate(shortcut, for: action) }
        guard shortcuts[action] != shortcut else { return }
        let original = shortcuts[action]
        retire(action)
        shortcuts[action] = shortcut
        guard isEnabled, let shortcut else { lastError = nil; return }
        do {
            try install(shortcut, for: action)
            lastError = nil
        } catch {
            retire(action)
            shortcuts[action] = original
            if let original {
                do { try install(original, for: action) }
                catch { disableAll() }
            }
            let failure = (error as? ControlsError) ?? .registrationFailed(action)
            lastError = failure
            throw failure
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        guard !isClosed else { throw ControlsError.closed }
        guard enabled != isEnabled else { return }
        guard enabled else { disableAll(); lastError = nil; return }
        isEnabled = true
        do {
            for action in ControlAction.allCases {
                if let shortcut = shortcuts[action] { try install(shortcut, for: action) }
            }
            lastError = nil
        } catch {
            disableAll()
            let failure = (error as? ControlsError) ?? .closed
            lastError = failure
            throw failure
        }
    }

    /// Commands and hotkeys share the same enable/teardown guard.
    public func dispatch(_ action: ControlAction) {
        guard isEnabled, !isClosed else { return }
        do { try actionPort.perform(action); lastError = nil }
        catch { lastError = .actionFailed(action) }
    }

    public func shutdown() {
        isClosed = true
        disableAll()
    }

    private func install(_ shortcut: ControlShortcut, for action: ControlAction) throws {
        let lease = UUID()
        leases[action] = lease
        try registrar.register(shortcut, for: action) { [weak self] in
            guard let self, self.leases[action] == lease else { return }
            self.dispatch(action)
        }
    }

    private func retire(_ action: ControlAction) {
        leases[action] = nil
        registrar.unregister(action)
    }

    private func disableAll() {
        isEnabled = false
        for action in ControlAction.allCases { retire(action) }
    }
}
