import Combine
import Foundation

/// One explicit Start/Send owns preparation before any request/scope is issued.
/// This never opens a browser. A saved grant is reselected with current models;
/// the final request owner still has to issue its own fresh native authority.
@MainActor public final class AccountPreparationController: ObservableObject {
    @Published public private(set) var isPreparing = false
    @Published public private(set) var isCancelling = false
    private final class Flight {
        let id: UUID
        let current: @MainActor () -> Bool
        var denied = false
        var task: Task<Void, any Error>?
        var cancellation: Task<Void, Never>?
        var selection: AccountInferenceSelection?
        init(id: UUID, current: @escaping @MainActor () -> Bool) { self.id = id; self.current = current }
    }
    private let account: AccountController
    private var flight: Flight?
    public var hasCurrentCaller: Bool { flight.map { !$0.denied && $0.current() } ?? true }
    public var intentID: UUID? { flight?.id }
    public init(account: AccountController) { self.account = account }

    public func prepare(intentID: UUID, isCurrent: @escaping @MainActor () -> Bool) async throws {
        guard isCurrent() else { throw CancellationError() }
        let owner: Flight
        if let existing = flight {
            guard existing.id == intentID else { throw AccountError.unavailable }
            owner = existing // Never replace the original caller's predicate.
        } else {
            if !account.aiEnabled { return }
            if let selection = account.inferenceSelection, account.owns(selection) { return }
            owner = Flight(id: intentID, current: isCurrent); flight = owner; isPreparing = true
            owner.task = Task { @MainActor in
                guard !owner.denied, owner.current() else { throw CancellationError() }
                await self.account.restore()
                guard !owner.denied, owner.current() else { throw CancellationError() }
                guard let selection = self.account.inferenceSelection, self.account.owns(selection) else { throw AccountError.unavailable }
                owner.selection = selection
            }
        }
        guard let task = owner.task else { throw AccountError.closed }
        try await withTaskCancellationHandler {
            do {
                try await task.value
                guard !owner.denied, owner.current(), let selection = owner.selection, account.owns(selection) else { throw CancellationError() }
                if owner.cancellation == nil { finish(owner) }
            } catch {
                if owner.cancellation == nil { finish(owner) }
                throw error
            }
        } onCancel: {
            Task { @MainActor [weak self] in await self?.cancel(intentID: intentID) }
        }
    }
    public func cancel(intentID: UUID) async {
        guard let owner = flight, owner.id == intentID else { return }
        if let cancellation = owner.cancellation { await cancellation.value; return }
        owner.denied = true; isCancelling = true
        let cancellation = Task { @MainActor in
            await self.account.cancel()
            _ = await owner.task?.result
            self.finish(owner)
        }
        owner.cancellation = cancellation; await cancellation.value
    }
    private func finish(_ owner: Flight) {
        guard flight === owner else { return }
        flight = nil; owner.task = nil; isPreparing = false; isCancelling = false
    }
}
