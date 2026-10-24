import Foundation

/// The workspace uses the same synchronous action boundary as the app's
/// remembered-use coordinator. Standalone callers retain explicit Open.
@MainActor struct ProfilePreparationActions {
    let controller: ProfileController
    var onOpen: (@MainActor () -> Void)?
    var onLock: (@MainActor () -> Void)?

    init(controller: ProfileController, onOpen: (@MainActor () -> Void)? = nil,
         onLock: (@MainActor () -> Void)? = nil) {
        self.controller = controller; self.onOpen = onOpen; self.onLock = onLock
    }
    func open() {
        if let onOpen { onOpen() }
        else { Task { await controller.openProfile() } }
    }
    func lock() {
        if let onLock { onLock() }
        else { _ = controller.beginClose() }
    }
    func canLock(sessionUse: SessionContextUseSnapshot?) -> Bool {
        controller.opened || controller.busy || sessionUse?.useInSessions == true || sessionUse?.isBusy == true
    }
}
