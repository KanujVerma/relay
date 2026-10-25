import AppKit
import Observation

public struct SelectionRequestIdentity: Equatable, Sendable {
    public let sessionID: UUID
    public let sessionEpoch: UInt64
    public let presentationGeneration: UInt64
    public let requestID: UUID
    public init(sessionID: UUID, sessionEpoch: UInt64, presentationGeneration: UInt64, requestID: UUID) {
        self.sessionID = sessionID
        self.sessionEpoch = sessionEpoch
        self.presentationGeneration = presentationGeneration
        self.requestID = requestID
    }
}

public struct SelectedTextObservation: Sendable {
    public let application: ApplicationIdentity
    public let role: String
    public let subrole: String?
    public let text: String
    public init(application: ApplicationIdentity, role: String, subrole: String?, text: String) {
        self.application = application
        self.role = role
        self.subrole = subrole
        self.text = text
    }
}

public struct SelectedTextSnapshot: Sendable {
    public let request: SelectionRequestIdentity
    public let application: ApplicationIdentity
    public let text: String
    public let capturedUptimeNanoseconds: UInt64
    public let consentGeneration: UUID
    public let provenance = "selected_accessibility_text"
    fileprivate let observationID: UUID
}

public enum SelectionError: Error, Equatable, LocalizedError, Sendable {
    case disabled, permissionRequired, applicationNotAllowed, unsupportedSelection
    case secureField, emptySelection, tooLarge, timedOut, stale, busy
    public var errorDescription: String? {
        switch self {
        case .disabled: "Selected-text context is disabled."
        case .permissionRequired: "Enable Accessibility access to read selected text. Ordinary shortcuts still work."
        case .applicationNotAllowed: "Choose an allowed app before reading selected text."
        case .unsupportedSelection: "This app does not expose a supported text selection. Paste the problem instead."
        case .secureField: "Secure fields cannot be read."
        case .emptySelection: "Select the relevant code or problem first."
        case .tooLarge: "Select at most 8 KiB of text."
        case .timedOut: "The app did not return selected text in time."
        case .stale: "The app, permission or current request changed. Select and read again."
        case .busy: "A selected-text read is already in progress."
        }
    }
}

@MainActor public protocol SelectedTextProviding: AnyObject {
    func isTrusted(prompt: Bool) -> Bool
    func selectedText(from application: ApplicationIdentity) async throws -> SelectedTextObservation
}

@MainActor @Observable public final class SelectedTextService {
    public private(set) var isEnabled = false
    public private(set) var isReading = false
    public private(set) var lastError: SelectionError?
    private var allowedBundleIDs = Set<String>()
    private var consentGeneration = UUID()
    private var observationID: UUID?
    private let provider: any SelectedTextProviding
    private let frontmostApplication: @MainActor () -> ApplicationIdentity?
    private let currentRequest: @MainActor () -> SelectionRequestIdentity?
    private let uptimeNanoseconds: @MainActor () -> UInt64
    private var focusObserver: NSObjectProtocol?
    private var readTask: Task<SelectedTextObservation, any Error>?

    /// Injectable initializer has no OS reads, observers, prompts or global keys.
    public init(provider: any SelectedTextProviding,
                frontmostApplication: @escaping @MainActor () -> ApplicationIdentity?,
                currentRequest: @escaping @MainActor () -> SelectionRequestIdentity?,
                uptimeNanoseconds: @escaping @MainActor () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.provider = provider
        self.frontmostApplication = frontmostApplication
        self.currentRequest = currentRequest
        self.uptimeNanoseconds = uptimeNanoseconds
    }

    /// Live convenience adapter observes app switches to invalidate even an
    /// away-and-back focus change. It does not request trust or read selection.
    public convenience init(currentRequest: @escaping @MainActor () -> SelectionRequestIdentity?) {
        self.init(provider: AccessibilitySelectedTextProvider(), frontmostApplication: WorkspaceFrontmostApplication.current, currentRequest: currentRequest)
        focusObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidate() }
        }
    }

    isolated deinit {
        readTask?.cancel()
        if let focusObserver { NSWorkspace.shared.notificationCenter.removeObserver(focusObserver) }
    }

    /// Invoke only from an explicit Enable or Enable-and-read user action.
    /// An untrusted enable can remain enabled while macOS permission is pending.
    public func enable(allowedBundleIDs: Set<String>, requestPermission: Bool) throws {
        guard !allowedBundleIDs.isEmpty,
              allowedBundleIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 255 }) else {
            throw SelectionError.applicationNotAllowed
        }
        invalidate()
        self.allowedBundleIDs = allowedBundleIDs
        consentGeneration = UUID()
        isEnabled = true
        let trusted = provider.isTrusted(prompt: requestPermission)
        lastError = trusted ? nil : .permissionRequired
    }

    public func revoke() {
        isEnabled = false
        allowedBundleIDs.removeAll()
        consentGeneration = UUID()
        invalidate()
    }

    /// The host calls this synchronously on pause/end, request supersession or
    /// any source change. Old async work cannot gain a new identity on return.
    public func invalidate() {
        observationID = nil
        readTask?.cancel()
    }

    public func read(request: SelectionRequestIdentity) async throws -> SelectedTextSnapshot {
        do { return try await readCurrent(request: request) }
        catch is CancellationError { lastError = .stale; throw SelectionError.stale }
        catch {
            let failure = (error as? SelectionError) ?? .unsupportedSelection
            lastError = failure
            throw failure
        }
    }

    private func readCurrent(request: SelectionRequestIdentity) async throws -> SelectedTextSnapshot {
        try Task.checkCancellation()
        guard isEnabled else { throw SelectionError.disabled }
        guard !isReading else { throw SelectionError.busy }
        guard provider.isTrusted(prompt: false) else { invalidate(); throw SelectionError.permissionRequired }
        guard currentRequest() == request else { throw SelectionError.stale }
        guard let application = frontmostApplication(), allowedBundleIDs.contains(application.bundleID) else {
            throw SelectionError.applicationNotAllowed
        }
        let started = uptimeNanoseconds()
        let generation = consentGeneration
        let identity = UUID()
        observationID = identity
        isReading = true
        defer {
            if Task.isCancelled, observationID == identity { observationID = nil }
            isReading = false
            readTask = nil
        }
        let task = Task { try await provider.selectedText(from: application) }
        readTask = task
        let observation = try await withTaskCancellationHandler(operation: {
            try await task.value
        }, onCancel: { task.cancel() })
        try Task.checkCancellation()
        guard isEnabled, generation == consentGeneration, observationID == identity,
              provider.isTrusted(prompt: false), frontmostApplication() == application,
              currentRequest() == request, observation.application == application else { throw SelectionError.stale }
        let captured = uptimeNanoseconds()
        guard captured >= started, captured - started <= 750_000_000 else { invalidate(); throw SelectionError.timedOut }
        try Self.validate(observation)
        lastError = nil
        return .init(request: request, application: application, text: observation.text,
                     capturedUptimeNanoseconds: captured, consentGeneration: generation, observationID: identity)
    }

    /// Checks current authority/focus and a five-second observation age. This
    /// does not claim that the source text has remained unchanged since reading.
    public func validateCurrent(_ snapshot: SelectedTextSnapshot) -> Bool {
        guard observationID == snapshot.observationID else { return false }
        let now = uptimeNanoseconds()
        let valid = isEnabled && consentGeneration == snapshot.consentGeneration
            && allowedBundleIDs.contains(snapshot.application.bundleID)
            && provider.isTrusted(prompt: false)
            && frontmostApplication() == snapshot.application
            && currentRequest() == snapshot.request
            && now >= snapshot.capturedUptimeNanoseconds
            && now - snapshot.capturedUptimeNanoseconds <= 5_000_000_000
        if !valid { invalidate() }
        return valid
    }

    static func validate(_ observation: SelectedTextObservation) throws {
        let identifiers = observation.role.lowercased() + " " + (observation.subrole ?? "").lowercased()
        guard !identifiers.contains("secure"), !identifiers.contains("password") else { throw SelectionError.secureField }
        guard ["AXTextArea", "AXTextField", "AXStaticText"].contains(observation.role) else { throw SelectionError.unsupportedSelection }
        guard observation.text.utf8.count <= 8192 else { throw SelectionError.tooLarge }
        guard !observation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SelectionError.emptySelection }
        guard observation.text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t" }) else {
            throw SelectionError.unsupportedSelection
        }
    }
}
