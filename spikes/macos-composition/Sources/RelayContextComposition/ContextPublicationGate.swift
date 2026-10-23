import Foundation
import RelayNativeSession

/// A manual request references native event ordering without inventing an EOU.
public struct PanelRequestBinding: Sendable, Equatable {
    public let lease: PresentationLease
    public let requestID: UUID
    public let eventSequence: UInt64
    public init(lease: PresentationLease, requestID: UUID, eventSequence: UInt64) {
        self.lease = lease; self.requestID = requestID; self.eventSequence = eventSequence
    }
    public init?(_ event: NativeSessionEvent) {
        guard event.kind == .eou, event.sourceCode == 2, let requestID = event.requestID else { return nil }
        self.init(lease: event.lease, requestID: requestID, eventSequence: event.eventSequence)
    }
}

/// Await a real bounded observation once, then check both native and context
/// authority synchronously before the panel's own atomic lease/commit reducer.
@MainActor public final class ContextPublicationGate {
    private let authority: SessionPresentationAuthority
    private var current: PanelRequestBinding?
    private var terminalStarted = false
    private var operation: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var flight: UUID?
    public init(authority: SessionPresentationAuthority) { self.authority = authority }
    public func bind(_ request: PanelRequestBinding) {
        operation?.cancel(); timer?.cancel(); flight=nil; operation = nil; current = request; terminalStarted = false
    }
    public func retire() {
        operation?.cancel(); timer?.cancel(); flight=nil; operation = nil; current = nil; terminalStarted = true
    }
    public func publish(_ request: PanelRequestBinding, budgetNanoseconds: UInt64 = 500_000_000,
                        validate: @escaping @MainActor () async -> Bool,
                        owns: @escaping @MainActor () -> Bool,
                        commit: @escaping @MainActor () -> Void,
                        rejected: @escaping @MainActor () -> Void = {}) {
        guard current == request, !terminalStarted else { return }
        terminalStarted = true
        let id=UUID();flight=id
        timer=Task { [weak self] in
            do { try await Task.sleep(nanoseconds:min(budgetNanoseconds,500_000_000)) } catch { return }
            guard let self,self.flight==id,self.current==request else { return }
            self.flight=nil;self.operation?.cancel();rejected()
        }
        operation = Task { [weak self] in
            let valid = await validate()
            guard let self, !Task.isCancelled, self.current == request,self.flight==id else { return }
            self.flight=nil;self.timer?.cancel()
            // The caller's reducer must perform its existing withCurrentLease
            // check inside commit. Do not recursively acquire that same lock.
            guard valid, self.authority.snapshot() == request.lease, owns() else { rejected(); return }
            commit()
        }
    }
}
