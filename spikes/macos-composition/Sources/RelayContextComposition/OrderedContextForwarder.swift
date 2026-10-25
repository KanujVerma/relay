import Foundation
import RelayNativeSession

public enum ContextForwardingError: Error, Equatable { case overflow, retired, oversizedContext, explicitUnavailable }

/// Optional work may hold one EOU, never the original native event order.
/// New invalidation promptly forwards the held EOU without context, even if
/// the OS capture ignores cancellation. Native authority retires at source.
@MainActor public final class OrderedContextForwarder {
    private enum Item {
        case session(SessionIngress), user(NativeUserQuestionRequest), cancel(NativeAnswerCancelRequest)
        var binding:PanelRequestBinding? {
            switch self {
            case .session(let ingress):return ingress.binding
            case .user(let request):return PanelRequestBinding(lease:request.lease,requestID:request.requestID,eventSequence:request.anchorEventSequence)
            case .cancel:return nil
            }
        }
        var isUser:Bool{if case .user=self{return true};return false}
        var isExplicit:Bool{if case .session=self{return false};return true}
        var invalidates:Bool{if case .session(let ingress)=self{return ingress.invalidatesOptionalWork};return true}
        func encodedByteCount()throws->Int {
            switch self {
            case .session(let ingress):return try ingress.encodedByteCount()
            case .user(let request):return try request.encodedJSON().count+4
            case .cancel(let request):return try request.encodedJSON().count+4
            }
        }
    }
    private struct Pending { let event: Item; let bytes: Int }
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
    private let explicit:ExplicitContextForwardingPorts?
    public var isIdle: Bool { queue.isEmpty && flight == nil }

    public init(maximumFrames: Int = 32, maximumBytes: Int = 262_144, captureBudgetNanoseconds: UInt64 = 1_500_000_000,
                shouldCapture: @escaping @MainActor (SessionIngress) -> Bool,
                capture: @escaping @MainActor (SessionIngress) async -> [Data],
                send: @escaping @MainActor (SessionIngress, [Data]) throws -> Void,
                onFailure: @escaping @MainActor () -> Void, explicit:ExplicitContextForwardingPorts? = nil) {
        self.maximumFrames = maximumFrames; self.maximumBytes = maximumBytes
        self.captureBudgetNanoseconds = min(captureBudgetNanoseconds, 1_500_000_000)
        self.shouldCapture = shouldCapture; self.capture = capture; self.send = send; self.onFailure = onFailure; self.explicit=explicit
    }
    public func enqueue(_ event: NativeSessionEvent) throws { try enqueue(.audio(event)) }
    public func enqueue(_ event: SessionIngress) throws {try enqueueItem(.session(event))}
    public func enqueueUserQuestion(_ request:NativeUserQuestionRequest,retiring:PanelRequestBinding? = nil)throws {
        guard explicit != nil else{throw ContextForwardingError.explicitUnavailable}
        try enqueueItem(.user(request),retiring:retiring)
    }
    public func enqueueAnswerCancellation(_ request:NativeAnswerCancelRequest,retiring target:PanelRequestBinding)throws {
        guard explicit != nil else{throw ContextForwardingError.explicitUnavailable}
        guard target.lease==request.targetLease,target.requestID==request.targetRequestID else{throw ContextForwardingError.retired}
        try enqueueItem(.cancel(request),retiring:target)
    }
    private func enqueueItem(_ event:Item,retiring target:PanelRequestBinding? = nil)throws {
        guard !retired else { throw ContextForwardingError.retired }
        let size = try event.encodedByteCount()
        guard queue.count + (flight == nil ? 0 : 1) < maximumFrames, bytes + size <= maximumBytes else {
            retire(); onFailure(); throw ContextForwardingError.overflow
        }
        // Denial must be written before cancelling an optional producer can
        // release its original request frame. It grants no new authority.
        var targets:[PanelRequestBinding]=[]
        if let target{targets.append(target)}
        if event.invalidates,let current=flight,(event.isExplicit || current.pending.event.isUser),
           let held=current.pending.event.binding,!targets.contains(held){targets.append(held)}
        do{for target in targets{try explicit?.retire(target)}}
        catch{retire();onFailure();throw error}
        queue.append(Pending(event: event, bytes: size)); bytes += size
        if event.invalidates {
            if let current = flight { current.operation.cancel(); finish(current.id, context: []) }
        }
        drain()
    }
    public func cancelOptionalWork() {
        if let current=flight { current.operation.cancel(); finish(current.id,context:[]) }
    }
    public func retire() {
        retired = true; flight?.operation.cancel(); flight?.timer.cancel(); flight = nil; queue.removeAll(); bytes = 0
    }
    private func drain() {
        while !retired, flight == nil, !queue.isEmpty {
            let next = queue.removeFirst()
            if next.event.binding != nil, shouldCaptureItem(next.event) {
                let id = UUID()
                let operation = Task { [weak self] in
                    guard let self else{return}
                    let context = await self.captureItem(next.event)
                    guard !Task.isCancelled else { return }
                    self.finish(id, context: context)
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
    private func shouldCaptureItem(_ item:Item)->Bool {
        switch item{case .session(let ingress):return shouldCapture(ingress);case .user(let request):return explicit?.shouldCapture(request) ?? false;case .cancel:return false}
    }
    private func captureItem(_ item:Item)async->[Data] {
        switch item{case .session(let ingress):return await capture(ingress);case .user(let request):return await explicit?.capture(request) ?? [];case .cancel:return []}
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
            switch pending.event {
            case .session(let ingress):try send(ingress,context)
            case .user(let request):guard let explicit else{throw ContextForwardingError.explicitUnavailable};try explicit.sendQuestion(request,context)
            case .cancel(let request):guard let explicit else{throw ContextForwardingError.explicitUnavailable};try explicit.sendCancellation(request)
            }
        } catch { retire(); onFailure() }
    }
}
