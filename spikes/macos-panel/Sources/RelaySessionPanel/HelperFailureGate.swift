import Foundation

/// The callback must retire only the helper generation that observed failure.
/// Its synchronous check/invalidation is atomic with activating a replacement.
public final class HelperFailureGate: @unchecked Sendable {
    private let lock=NSLock()
    private var current:UUID?
    public init() {}
    public func activate(_ identity:UUID) { lock.withLock { current=identity } }
    @discardableResult public func withCurrent(_ identity:UUID,perform:()->Void) -> Bool {
        lock.withLock {
            guard current==identity else { return false }
            perform();return true
        }
    }
}
