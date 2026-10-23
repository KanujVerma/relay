import Foundation
import RelayNativeSession

public enum ContextForwardingError: Error, Equatable { case overflow, retired, oversizedContext }

/// Optional work may hold one EOU, never the original native event order.
/// New invalidation promptly forwards the held EOU without context, even if
/// the OS capture ignores cancellation. Native authority retires at source.
@MainActor public final class OrderedContextForwarder {
    private struct Pending { let event: SessionIngress; let bytes: Int }
    private struct Flight { let id: UUID; let pending: Pending; let operation: Task<Void, Never>; let timer: Task<Void, Never> }
    private var queue: [Pending] = []
    private var bytes = 0
    private var flight: Flight?
    private var retired = false
    private let maximumFrames: Int
    private let maximumBytes: Int
    private let captureBudgetNanoseconds: UInt64
    private let shouldCapture: @MainActor (SessionIngress) -> Bool
    private let capture: @MainActor (SessionIngress) async -> [Data]
    private let send: @MainActor (SessionIngress, [Data]) throws -> Void
    private let onFailure: @MainActor () -> Void
    public var isIdle: Bool { queue.isEmpty && flight == nil }

    public init(maximumFrames: Int = 32, maximumBytes: Int = 262_144, captureBudgetNanoseconds: UInt64 = 1_500_000_000,
                shouldCapture: @escaping @MainActor (SessionIngress) -> Bool,
                capture: @escaping @MainActor (SessionIngress) async -> [Data],
                send: @escaping @MainActor (SessionIngress, [Data]) throws -> Void,
                onFailure: @escaping @MainActor () -> Void) {
        self.maximumFrames = maximumFrames; self.maximumBytes = maximumBytes
        self.captureBudgetNanoseconds = min(captureBudgetNanoseconds, 1_500_000_000)
        self.shouldCapture = shouldCapture; self.capture = capture; self.send = send; self.onFailure = onFailure
    }
    public func enqueue(_ event: NativeSessionEvent) throws { try enqueue(.audio(event)) }
    public func enqueue(_ event: SessionIngress) throws {
        guard !retired else { throw ContextForwardingError.retired }
        let size = try event.encodedByteCount()
        guard queue.count + (flight == nil ? 0 : 1) < maximumFrames, bytes + size <= maximumBytes else {
            retire(); onFailure(); throw ContextForwardingError.overflow
        }
        queue.append(Pending(event: event, bytes: size)); bytes += size
        if event.invalidatesOptionalWork {
            if let current = flight { current.operation.cancel(); finish(current.id, context: []) }
        }
        drain()
    }
    public func retire() {
        retired = true; flight?.operation.cancel(); flight?.timer.cancel(); flight = nil; queue.removeAll(); bytes = 0
    }
    private func drain() {
        while !retired, flight == nil, !queue.isEmpty {
            let next = queue.removeFirst()
            if next.event.binding != nil, shouldCapture(next.event) {
                let id = UUID()
                let operation = Task { [weak self, capture] in
                    let context = await capture(next.event)
                    guard !Task.isCancelled else { return }
                    self?.finish(id, context: context)
                }
                let timer = Task { [weak self, captureBudgetNanoseconds] in
                    do { try await Task.sleep(nanoseconds: captureBudgetNanoseconds) } catch { return }
                    guard let self, let active = self.flight, active.id == id else { return }
                    active.operation.cancel(); self.finish(id, context: [])
                }
                flight = Flight(id: id, pending: next, operation: operation, timer: timer)
                return
            }
            deliver(next, context: [])
        }
    }
    private func finish(_ id: UUID, context: [Data]) {
        guard !retired, let current = flight, current.id == id else { return }
        current.timer.cancel(); flight = nil
        deliver(current.pending, context: context)
        drain()
    }
    private func deliver(_ pending: Pending, context: [Data]) {
        bytes -= pending.bytes
        do {
            guard context.count <= 1, context.allSatisfy({ !$0.isEmpty && $0.count <= 16_384 }) else {
                throw ContextForwardingError.oversizedContext
            }
            try send(pending.event, context)
        } catch { retire(); onFailure() }
    }
}
