import Combine
import Foundation

/// Native-issued immutable selection. Public JSON/status cannot construct one.
/// Every token use still checks the encrypted registration/generation/scope.
@MainActor public final class AccountInferenceSelection {
    public let registrationID: UUID
    public let generation: UUID
    public let model: String
    fileprivate var valid = true
    fileprivate init(registrationID: UUID, generation: UUID, model: String) {
        self.registrationID = registrationID; self.generation = generation; self.model = model
    }
}

@MainActor public final class AccountController: ObservableObject {
    @Published public private(set) var snapshot: AccountSnapshot?
    @Published public private(set) var status: AccountStatus = .unavailable
    @Published public private(set) var busy = false
    @Published public private(set) var aiEnabled: Bool
    @Published public private(set) var message = "Connect ChatGPT to use your plan in Relay."
    @Published public private(set) var inferenceSelection: AccountInferenceSelection?
    public var needsPlanNotice: Bool {
        guard let row = snapshot?.activeRegistration else { return false }
        return row.planUsageState == .granted && !row.planNoticeAcknowledged
    }
    public var canMutate: Bool { !busy && isIdle() && !closed }
    public var canCancel: Bool { busy && operationTask != nil && !cancelling }
    private let storage: AccountStorage
    private let portFactory: @MainActor (AccountSecretBootstrap) throws -> any AccountPort
    private let retireInference: @MainActor () async throws -> Void
    private let openBrowser: @MainActor (URL) -> Bool
    private let persistAIEnabled: @MainActor (Bool) -> Void
    private let isIdle: @MainActor () -> Bool
    private var port: (any AccountPort)?
    private var generation: UUID?
    private var lifecycle = UUID()
    private var operationTask: Task<Void, Never>?, cancellingTask: Task<Void, Never>?
    private var pendingRequest: UUID?
    private var cancelling = false, closed = false
    private enum Operation { case restore, disable, request(AccountAction, UUID?, Bool) }

    public init(storage: AccountStorage,
                portFactory: @escaping @MainActor (AccountSecretBootstrap) throws -> any AccountPort,
                retireInference: @escaping @MainActor () async throws -> Void,
                openBrowser: @escaping @MainActor (URL) -> Bool,
                aiEnabled: Bool = false, persistAIEnabled: @escaping @MainActor (Bool) -> Void = { _ in },
                isIdle: @escaping @MainActor () -> Bool = { true }) {
        self.storage = storage; self.portFactory = portFactory; self.retireInference = retireInference
        self.openBrowser = openBrowser; self.aiEnabled = aiEnabled; self.persistAIEnabled = persistAIEnabled; self.isIdle = isIdle
    }
    private func invalidateSelection() { inferenceSelection?.valid = false; inferenceSelection = nil }
    public func owns(_ selection: AccountInferenceSelection) -> Bool {
        !closed && aiEnabled && selection.valid && inferenceSelection === selection
    }
    public func sessionBootstrap() throws -> AccountSecretBootstrap? {
        guard let selection = inferenceSelection, owns(selection) else { return nil }
        return try storage.bootstrap(purpose: .oauthSession, registrationID: selection.registrationID, generation: selection.generation, createKey: false)
    }
    private func current(_ owner: UUID) -> Bool { lifecycle == owner && !closed && !cancelling && isIdle() }
    private func authorize(_ effect: AccountAuthorization, owner: UUID) -> Bool {
        guard current(owner), pendingRequest == effect.requestID else { return false }
        return openBrowser(effect.authorizationURL)
    }
    private func perform(_ action: AccountAction, registrationID: UUID?, owner: UUID) async throws -> AccountResponse {
        guard current(owner), let port else { throw AccountError.closed }
        let request = try AccountRequest(action: action, registrationID: registrationID)
        pendingRequest = request.id
        defer { if pendingRequest == request.id { pendingRequest = nil } }
        let response = try await port.perform(request, authorization: { [weak self] effect in await self?.authorize(effect, owner: owner) ?? false })
        guard current(owner), response.requestID == request.id, response.action == action, response.isTerminal,
              response.snapshot.revision >= (snapshot?.revision ?? 0) else { throw AccountError.rejected }
        if [.connect, .enablePlan, .select].contains(action), let registrationID,
           [.ready, .planDisabled].contains(response.status) {
            guard response.snapshot.activeRegistrationID == registrationID else { throw AccountError.rejected }
        }
        snapshot = response.snapshot; status = response.status; message = Self.message(response)
        return response
    }
    private func issueSelection() {
        guard aiEnabled, let generation, let snapshot, snapshot.catalogState == .current,
              let row = snapshot.activeRegistration, row.sessionState == .available, row.planUsageState == .granted,
              let model = snapshot.models.first else { return }
        inferenceSelection = AccountInferenceSelection(registrationID: row.id, generation: generation, model: model.slug)
    }
    private func preference(_ value: Bool) {
        if aiEnabled != value { aiEnabled = value; persistAIEnabled(value) }
    }
    private func run(_ operation: Operation) async {
        guard canMutate else { return }
        let owner = UUID(); lifecycle = owner; busy = true; cancelling = false; invalidateSelection()
        let task = Task { @MainActor in
            do {
                // Root supplies an actual old-session-helper stop/reap barrier.
                // Async scope completion alone does not join a token thread.
                try await retireInference()
                guard current(owner) else { return }
                await port?.close(); port = nil
                guard current(owner) else { return }
                if case .disable = operation {
                    preference(false); message = "AI is off. Your ChatGPT connection remains saved."
                    return
                }
                let generation = UUID(); self.generation = generation
                let createKey: Bool
                if case .request(let action, _, _) = operation { createKey = action == .connect || action == .enablePlan }
                else { createKey = false }
                let storage = self.storage
                let bootstrap = try await Task.detached { try storage.controlBootstrap(generation: generation, createKey: createKey) }.value
                guard current(owner) else { return }
                port = try portFactory(bootstrap)
                switch operation {
                case .restore:
                    let response = try await perform(.status, registrationID: nil, owner: owner)
                    if aiEnabled, response.snapshot.activeRegistration?.sessionState == .available,
                       response.snapshot.activeRegistration?.planUsageState == .granted, let identity = response.snapshot.activeRegistrationID {
                        _ = try await perform(.select, registrationID: identity, owner: owner)
                        issueSelection()
                    }
                case .request(let action, let identity, let enable):
                    let response = try await perform(action, registrationID: identity, owner: owner)
                    if [.connect, .enablePlan, .select].contains(action), response.status == .ready {
                        if enable { preference(true) }
                        issueSelection()
                    } else if [.connect, .enablePlan, .select].contains(action), response.status == .planDisabled {
                        preference(false)
                    } else if action == .signOut { preference(false) }
                case .disable: break
                }
            } catch {
                guard lifecycle == owner, !cancelling, !closed else { return }
                invalidateSelection()
                status = (error as? AccountError) == .locked ? .locked : .error
                message = status == .locked ? "Protected account key is unavailable. Unlock your Mac or connect again." : "Account setup could not finish. Existing account data was kept. Try again."
                await port?.close(); port = nil
            }
        }
        operationTask = task; await task.value
        if lifecycle == owner, !cancelling {
            operationTask = nil; pendingRequest = nil; busy = false
            if aiEnabled, inferenceSelection == nil, status == .ready { message = "Connected. Current model availability could not be verified. Refresh models before using AI." }
        }
    }
    public func restore() async { await run(.restore) }
    public func connect() async { await run(.request(.connect, nil, true)) }
    public func reconnect(_ identity: UUID) async { await run(.request(.connect, identity, true)) }
    public func enablePlan(_ identity: UUID) async { await run(.request(.enablePlan, identity, true)) }
    public func select(_ identity: UUID) async { await run(.request(.select, identity, true)) }
    public func signOut(_ identity: UUID) async { await run(.request(.signOut, identity, false)) }
    public func refreshModels() async {
        guard let identity = snapshot?.activeRegistrationID else { return }
        await run(.request(.select, identity, false))
    }
    public func setAIEnabled(_ enabled: Bool) async {
        if !enabled { await run(.disable) }
        else if let identity = snapshot?.activeRegistrationID { await run(.request(.select, identity, true)) }
    }
    public func acknowledgePlanNotice() async {
        guard canMutate, let identity = snapshot?.activeRegistrationID, port != nil else { return }
        let owner = lifecycle; busy = true
        defer { if lifecycle == owner { busy = false } }
        do { _ = try await perform(.acknowledgePlanNotice, registrationID: identity, owner: owner) }
        catch { if current(owner) { message = "The notice could not be saved. You can dismiss it again after restoring your connection." } }
    }
    public func cancel() async {
        if let cancellingTask { await cancellingTask.value; return }
        guard let ownerTask = operationTask else { return }
        let owner = lifecycle; cancelling = true; invalidateSelection()
        let port = self.port, target = pendingRequest
        let task = Task { @MainActor in
            if let port, let target {
                do { _ = try await port.perform(AccountRequest(action: .cancel, targetRequestID: target)) }
                catch { await port.close() }
            }
            await ownerTask.value
            await port?.close()
            if lifecycle == owner {
                self.port = nil; pendingRequest = nil; operationTask = nil; busy = false
                status = .cancelled; message = "Account setup cancelled. No previous AI session was resumed."
            }
        }
        cancellingTask = task; await task.value; cancellingTask = nil; cancelling = false
    }
    public func close() async {
        await cancel(); closed = true; invalidateSelection()
        try? await retireInference()
        await port?.close(); port = nil; busy = false
    }
    private static func message(_ response: AccountResponse) -> String {
        switch response.reason {
        case .connected, .accountSelected: return response.status == .planDisabled ? "Signed in. Enable ChatGPT plan usage to use AI." : "Connected. Relay is ready to use your ChatGPT plan."
        case .planPermissionMissing: return "Signed in. ChatGPT plan usage was not granted. Enable it explicitly to use AI."
        case .signedOut: return "Signed out. Your saved account can be reconnected."
        case .remoteRevocationUnconfirmed: return "Local tokens were cleared. Remote sign-out could not be confirmed; review your ChatGPT connected apps."
        case .reauthenticationRequired: return "Reconnect this saved ChatGPT account before using AI."
        case .authorizationDeclined: return "ChatGPT authorization was declined."
        case .catalogUnavailable: return "Current model availability could not be checked. Try Refresh models."
        case .operationBusy: return "Another account operation is still finishing."
        case .authorizationCancelled: return "Account setup cancelled."
        default: return response.status == .signedOut ? "No active ChatGPT connection." : "Saved connection checked."
        }
    }
}
