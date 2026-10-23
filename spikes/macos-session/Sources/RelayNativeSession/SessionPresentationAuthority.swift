import Foundation

public struct PresentationLease: Sendable, Equatable, Codable {
    public let captureSessionID: UUID
    public let sessionEpoch: UInt64
    public let presentationGeneration: UInt64
}

public enum NativeSessionError: Error, Equatable {
    case alreadyRunning, counterExhausted, invalidClock, invalidFrame, frameTooLarge
    case notAuthorized, invalidConfiguration, modelUnavailable, transportClosed
}

/// The panel checks and commits inside withCurrentLease. The same lock protects
/// invalidation, so a queued result cannot check first and paint after onset.
/// Callbacks must not acquire another session lock from inside the commit.
public final class SessionPresentationAuthority: @unchecked Sendable {
    private let lock = NSLock()
    private var current: PresentationLease?
    public init() {}

    @discardableResult public func start() throws -> PresentationLease {
        try lock.withLock {
            guard current == nil else { throw NativeSessionError.alreadyRunning }
            let lease = PresentationLease(captureSessionID: UUID(), sessionEpoch: 1, presentationGeneration: 1)
            current = lease
            return lease
        }
    }
    public func snapshot() -> PresentationLease? { lock.withLock { current } }
    @discardableResult public func invalidate() -> PresentationLease? {
        lock.withLock {
            guard let lease = current, lease.presentationGeneration < UInt64.max else {
                current = nil
                return nil
            }
            let next = PresentationLease(captureSessionID: lease.captureSessionID,
                sessionEpoch: lease.sessionEpoch, presentationGeneration: lease.presentationGeneration + 1)
            current = next
            return next
        }
    }
    public func stop() { lock.withLock { current = nil } }
    @discardableResult public func withCurrentLease(_ lease: PresentationLease, perform: () -> Void) -> Bool {
        lock.withLock {
            guard current == lease else { return false }
            perform()
            return true
        }
    }
}
