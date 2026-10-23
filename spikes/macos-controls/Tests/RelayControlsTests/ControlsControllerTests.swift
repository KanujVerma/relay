import Testing
@testable import RelayControls

@MainActor
@Suite struct ControlsControllerTests {
    @Test func duplicateAndUnmodifiedBindingsAreRejectedBeforeRegistration() throws {
        let registrar = FakeRegistrar()
        let host = SessionHarness()
        let controls = ControlsController(registrar: registrar, actionPort: host)
        #expect(throws: ControlsError.unsafeShortcut) {
            try controls.configure(.init(keyCode: 48, modifiers: []), for: .requestHelp)
        }
        try controls.configure(.init(keyCode: 4, modifiers: [.command, .shift]), for: .requestHelp)
        #expect(throws: ControlsError.duplicateShortcut(.requestHelp)) {
            try controls.configure(.init(keyCode: 4, modifiers: [.command, .shift]), for: .pause)
        }
        #expect(registrar.callbacks.isEmpty)
    }

    @Test func staleCallbacksCannotPauseAfterRebindOrDisable() throws {
        let registrar = FakeRegistrar()
        let host = SessionHarness()
        let controls = ControlsController(registrar: registrar, actionPort: host)
        try controls.configure(.init(keyCode: 35, modifiers: [.command, .shift]), for: .pause)
        try controls.setEnabled(true)
        let old = try #require(registrar.callbacks[.pause])
        try controls.configure(.init(keyCode: 35, modifiers: [.command, .control]), for: .pause)
        old()
        #expect(host.acceptsCapture)
        registrar.callbacks[.pause]?()
        #expect(!host.acceptsCapture)
        #expect(!host.acceptsModel)
        #expect(host.answer == nil)
        host.acceptsCapture = true
        let rebound = try #require(registrar.callbacks[.pause])
        try controls.setEnabled(false)
        rebound()
        #expect(host.acceptsCapture)
        #expect(registrar.callbacks.isEmpty)
    }

    @Test func registrationFailureRollsBackAndReportsDisabledState() throws {
        let registrar = FakeRegistrar()
        let controls = ControlsController(registrar: registrar, actionPort: SessionHarness())
        try controls.configure(.init(keyCode: 4, modifiers: [.command, .shift]), for: .requestHelp)
        try controls.configure(.init(keyCode: 35, modifiers: [.command, .shift]), for: .pause)
        registrar.failure = .pause
        #expect(throws: ControlsError.registrationFailed(.pause)) { try controls.setEnabled(true) }
        #expect(!controls.isEnabled)
        #expect(registrar.callbacks.isEmpty)
    }

    @Test func failedRebindRestoresOldShortcutWithFreshLease() throws {
        let registrar = FakeRegistrar()
        let host = SessionHarness()
        let controls = ControlsController(registrar: registrar, actionPort: host)
        let original = ControlShortcut(keyCode: 35, modifiers: [.command, .shift])
        try controls.configure(original, for: .pause)
        try controls.setEnabled(true)
        let old = try #require(registrar.callbacks[.pause])
        registrar.failNext = true
        #expect(throws: ControlsError.registrationFailed(.pause)) {
            try controls.configure(.init(keyCode: 4, modifiers: [.command, .shift]), for: .pause)
        }
        #expect(controls.shortcuts[.pause] == original)
        old()
        #expect(host.acceptsCapture)
        registrar.callbacks[.pause]?()
        #expect(!host.acceptsCapture)
    }

    @Test func shutdownRejectsDirectAndQueuedActionsAndSurfacesHostFailure() throws {
        let registrar = FakeRegistrar()
        let host = SessionHarness()
        let controls = ControlsController(registrar: registrar, actionPort: host)
        try controls.configure(.init(keyCode: 4, modifiers: [.command, .shift]), for: .requestHelp)
        try controls.setEnabled(true)
        host.fail = true
        controls.dispatch(.requestHelp)
        #expect(controls.lastError == .actionFailed(.requestHelp))
        let queued = try #require(registrar.callbacks[.requestHelp])
        controls.shutdown()
        host.fail = false
        controls.dispatch(.requestHelp)
        queued()
        #expect(host.helpRequests == 0)
        #expect(throws: ControlsError.closed) { try controls.setEnabled(true) }
    }

    @Test func releasingControllerUnregistersItsKeys() throws {
        let registrar = FakeRegistrar()
        let host = SessionHarness()
        var controls: ControlsController? = ControlsController(registrar: registrar, actionPort: host)
        try controls?.configure(.init(keyCode: 4, modifiers: [.command, .shift]), for: .requestHelp)
        try controls?.setEnabled(true)
        let queued = try #require(registrar.callbacks[.requestHelp])
        controls = nil
        #expect(registrar.callbacks.isEmpty)
        queued()
        #expect(host.helpRequests == 0)
    }
}

@MainActor final class FakeRegistrar: HotkeyRegistering {
    var callbacks: [ControlAction: @MainActor () -> Void] = [:]
    var failure: ControlAction?
    var failNext = false
    func register(_ shortcut: ControlShortcut, for action: ControlAction, handler: @escaping @MainActor () -> Void) throws {
        if action == failure || failNext {
            failNext = false
            throw ControlsError.registrationFailed(action)
        }
        callbacks[action] = handler
    }
    func unregister(_ action: ControlAction) { callbacks[action] = nil }
}

@MainActor final class SessionHarness: ControlActionHandling {
    var acceptsCapture = true
    var acceptsModel = true
    var answer: String? = "old answer"
    var helpRequests = 0
    var fail = false
    func perform(_ action: ControlAction) throws {
        if fail { throw ControlsError.actionFailed(action) }
        switch action {
        case .pause, .endSession:
            acceptsCapture = false
            acceptsModel = false
            answer = nil
        case .resume: acceptsCapture = true; acceptsModel = true
        case .requestHelp: helpRequests += 1
        default: break
        }
    }
}
