import Foundation

/// Installed before Process.run. Foundation remains the sole child reaper.
/// The callback can race both waiter registration and actor thread migration.
final class ProfileProcessExitReceipt: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32?
    private var waiters: [CheckedContinuation<Int32, Never>] = []

    var hasExited: Bool { lock.withLock { status != nil } }

    func record(_ value: Int32) {
        let ready: [CheckedContinuation<Int32, Never>] = lock.withLock {
            guard status == nil else { return [] }
            status = value
            let ready = waiters
            waiters.removeAll()
            return ready
        }
        ready.forEach { $0.resume(returning: value) }
    }

    func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            let completed: Int32? = lock.withLock {
                if let status { return status }
                waiters.append(continuation)
                return nil
            }
            if let completed { continuation.resume(returning: completed) }
        }
    }
}
