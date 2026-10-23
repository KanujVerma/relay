import AppKit
import Combine
import Foundation

public struct ProfileReviewCard: Decodable, Sendable, Identifiable, Equatable {
    public var id: String { factID }
    public let factID: String
    public let sourceID: String
    public let snippet: String
    public let sourceSHA256: String
    public let spanStart: Int
    public let spanEnd: Int
    public let reviewRevision: Int
    public let actorHint: String
    public let fingerprint: String
    public let locator: String?
    enum CodingKeys: String, CodingKey {
        case factID = "fact_id", sourceID = "source_id", snippet
        case sourceSHA256 = "source_sha256", spanStart = "span_start", spanEnd = "span_end"
        case reviewRevision = "review_revision", actorHint = "actor_hint", fingerprint = "card_fingerprint"
        case locator
    }
}

public struct ProfileSourceSummary: Decodable, Sendable, Identifiable {
    public var id: String { sourceID }
    public let sourceID: String
    public let label: String
    public let purpose: String
    enum CodingKeys: String, CodingKey { case sourceID = "source_id", label, purpose }
}

public struct ProfileJobCard: Decodable, Sendable {
    public let sourceID: String
    public let text: String
    public let fingerprint: String
    enum CodingKeys: String, CodingKey { case sourceID = "source_id", text, fingerprint }
}

public struct ProfileExistingFact: Decodable, Sendable {
    public let factID: String
    public let claimText: String
    public let actor: String
    enum CodingKeys: String, CodingKey { case factID = "fact_id", claimText = "claim_text", actor }
}

/// The native view calls these actions from visible controls. This is the
/// application interaction owner, not an OS identity or biometric attestation.
/// onInvalidate must synchronously retire any visible personal answer lease.
@MainActor public final class ProfileController: ObservableObject {
    @Published public private(set) var opened = false
    @Published public private(set) var busy = false
    @Published public private(set) var card: ProfileReviewCard?
    @Published public private(set) var job: ProfileJobCard?
    @Published public private(set) var sources: [ProfileSourceSummary] = []
    @Published public private(set) var pendingCount = 0
    @Published public private(set) var errorStatus: String?
    @Published public private(set) var existingFact: ProfileExistingFact?
    @Published public private(set) var existingClaimKey: String?
    @Published public private(set) var memories: [ProfileMemoryFact] = []
    @Published public private(set) var memoryCount = 0
    @Published public private(set) var closeOutcome: ProfileCloseOutcome?
    private let client: ProfileClient
    private let vault: ProfileVault
    private let onInvalidate: @MainActor () -> Void
    private var lifecycle = UUID()
    private var memoryCursor: String?
    public var canLoadMoreMemories: Bool { opened && !busy && memoryCursor != nil }

    public init(client: ProfileClient, vault: ProfileVault,
                onInvalidate: @escaping @MainActor () -> Void = {}) {
        self.client = client; self.vault = vault; self.onInvalidate = onInvalidate
    }

    private func decode<T: Decodable>(_ value: Any, as: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func apply(_ state: [String: Any]) throws {
        card = try (state["card"] as? [String: Any]).map { try decode($0, as: ProfileReviewCard.self) }
        job = try (state["job"] as? [String: Any]).map { try decode($0, as: ProfileJobCard.self) }
        pendingCount = state["pending_count"] as? Int ?? 0
        existingFact = nil
        existingClaimKey = nil
    }
    private func readSources() async throws -> [ProfileSourceSummary] {
        let response = try await client.command(["command": "sources"])
        return try decode(response["sources"] ?? [], as: [ProfileSourceSummary].self)
    }
    private func readMemories(after: String? = nil) async throws -> ProfileMemoryPage {
        let response = try await client.command(["command": "memories", "after": after as Any? ?? NSNull(), "limit": 8])
        let page = try decode(response, as: ProfileMemoryPage.self)
        try page.validate(after: after)
        return page
    }
    private func applyMemories(_ page: ProfileMemoryPage) {
        memories = page.memories; memoryCount = page.totalCount; memoryCursor = page.nextAfter
    }
    private func clearVisibleState() {
        opened = false; card = nil; job = nil; sources = []; existingFact = nil; pendingCount = 0
        existingClaimKey = nil; memories = []; memoryCount = 0; memoryCursor = nil
    }
    private func lockAfterFailure(operation: UUID, message: String) async {
        guard lifecycle == operation else { return }
        clearVisibleState()
        onInvalidate()
        let outcome = await client.close()
        guard lifecycle == operation else { return }
        closeOutcome = outcome
        errorStatus = outcome == .locked
            ? message + " Profile locked. Reopen to review the saved state."
            : message + " Profile unavailable. The helper was stopped; a fresh helper is required."
    }
    public func openProfile() async {
        guard !busy, !opened else { return }
        let operation = UUID()
        lifecycle = operation
        busy = true; errorStatus = nil; closeOutcome = nil
        defer { if lifecycle == operation { busy = false } }
        do {
            let state: [String: Any]
            if try vault.exists() {
                state = try await client.load(vault.load())
                guard lifecycle == operation else { return }
            } else {
                state = try await client.command(["command": "new"])
                guard lifecycle == operation else { return }
                let snapshot = try await client.snapshot()
                guard lifecycle == operation else { return }
                try vault.save(snapshot, createKey: true)
            }
            let newSources = try await readSources()
            guard lifecycle == operation else { return }
            let newMemories = try await readMemories()
            guard lifecycle == operation else { return }
            try apply(state)
            sources = newSources
            applyMemories(newMemories)
            opened = true
        } catch {
            await lockAfterFailure(operation: operation,
                                   message: "Profile could not be opened. Existing data and keys were kept.")
        }
    }
    private func mutate(_ action: @MainActor () async throws -> [String: Any]) async {
        guard opened, !busy else { return }
        let operation = lifecycle
        busy = true; errorStatus = nil; closeOutcome = nil; onInvalidate()
        defer { if lifecycle == operation { busy = false } }
        do {
            let state = try await action()
            guard lifecycle == operation else { return }
            let snapshot = try await client.snapshot()
            guard lifecycle == operation else { return }
            try vault.save(snapshot)
            let newSources = try await readSources()
            guard lifecycle == operation else { return }
            let newMemories = try await readMemories()
            guard lifecycle == operation else { return }
            try apply(state)
            sources = newSources
            applyMemories(newMemories)
        } catch ProfileError.rejected {
            guard lifecycle == operation else { return }
            errorStatus = "Review could not be applied. Check ownership, the fact key and the selected revision."
        } catch { await lockAfterFailure(operation: operation, message: "The change could not be saved.") }
    }
    public func stageEnteredText(_ text: String, purpose: String, label: String, role: String, project: String?) async {
        await mutate {
            try await self.client.select(Data(text.utf8), fileType: "txt", purpose: purpose,
                                         label: label, role: role, project: project)
        }
    }
    public func stageSelectedFile(_ url: URL, purpose: String, label: String, role: String, project: String?) async {
        await mutate {
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                  let size = attributes.fileSize, size > 0, size <= 2 * 1024 * 1024,
                  ["txt", "pdf", "docx"].contains(url.pathExtension.lowercased())
            else { throw ProfileError.invalidPayload }
            let data = try Data(contentsOf: url)
            return try await self.client.select(data, fileType: url.pathExtension.lowercased(), purpose: purpose,
                                                label: label, role: role, project: project)
        }
    }
    public func review(_ displayed: ProfileReviewCard, actor: String, claimKey: String, replaces: ProfileExistingFact?) async {
        guard displayed == card else { return }
        await mutate {
            var request: [String: Any] = ["command": "decide", "fact_id": displayed.factID,
                "fingerprint": displayed.fingerprint, "decision": "approve", "actor": actor, "claim_key": claimKey]
            if let replaces { request["replaces_fact_id"] = replaces.factID }
            return try await self.client.command(request)
        }
    }
    public func reject(_ displayed: ProfileReviewCard) async {
        guard displayed == card else { return }
        await mutate { try await self.client.command(["command": "decide", "fact_id": displayed.factID,
            "fingerprint": displayed.fingerprint, "decision": "reject"]) }
    }
    public func lookupExisting(claimKey: String) async {
        guard opened, !busy else { return }
        let operation = lifecycle
        busy = true; defer { if lifecycle == operation { busy = false } }
        existingFact = nil; existingClaimKey = nil
        do {
            let response = try await client.command(["command": "current_claim", "claim_key": claimKey])
            guard lifecycle == operation else { return }
            existingFact = try (response["fact"] as? [String: Any]).map { try decode($0, as: ProfileExistingFact.self) }
            existingClaimKey = claimKey
            errorStatus = existingFact == nil ? "No active fact uses this key." : nil
        } catch {
            guard lifecycle == operation else { return }
            errorStatus = "The existing fact could not be checked."
        }
    }
    public func loadMoreMemories() async {
        guard canLoadMoreMemories, let after = memoryCursor else { return }
        let operation = lifecycle
        busy = true; errorStatus = nil
        defer { if lifecycle == operation { busy = false } }
        do {
            let page = try await readMemories(after: after)
            guard lifecycle == operation, opened else { return }
            let combined = memories + page.memories
            guard Set(combined.map(\.factID)).count == combined.count, page.totalCount >= combined.count
            else { throw ProfileError.invalidPayload }
            memories = combined; memoryCount = page.totalCount; memoryCursor = page.nextAfter
        } catch {
            await lockAfterFailure(operation: operation, message: "Saved memory could not be loaded.")
        }
    }
    public func approveJob(_ displayed: ProfileJobCard) async {
        guard displayed.sourceID == job?.sourceID, displayed.fingerprint == job?.fingerprint else { return }
        await mutate { try await self.client.command(["command": "approve_job", "source_id": displayed.sourceID,
                                                       "fingerprint": displayed.fingerprint]) }
    }
    public func revoke(_ source: ProfileSourceSummary) async {
        await mutate { try await self.client.command(["command": "revoke", "source_id": source.sourceID]) }
    }
    public func close() async {
        let operation = UUID()
        lifecycle = operation
        busy = true
        onInvalidate()
        clearVisibleState()
        let outcome = await client.close()
        guard lifecycle == operation else { return }
        closeOutcome = outcome
        busy = false
        errorStatus = outcome == .locked ? nil : "Profile unavailable. The helper was stopped; a fresh helper is required."
    }
}
