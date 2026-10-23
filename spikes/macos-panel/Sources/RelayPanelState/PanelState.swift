import Foundation

// UI presentation contract only. Input still needs an independently trusted host
// that has already completed its safety/QA and active-turn publication checks.
public struct TurnKey: Equatable, Sendable {
    public let identifier: String
    public let revision: UInt64
    public let generation: UInt64
    // Assigned by the trusted producer when the event is CREATED, not when a
    // delayed callback is delivered. Increases after every stop/resume cycle.
    public let sessionEpoch: UInt64

    public init?(identifier: String, revision: UInt64, generation: UInt64, sessionEpoch: UInt64) {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
        guard !identifier.isEmpty, identifier.utf8.count <= 64,
              identifier.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              revision > 0, generation > 0, sessionEpoch > 0 else { return nil }
        self.identifier = identifier
        self.revision = revision
        self.generation = generation
        self.sessionEpoch = sessionEpoch
    }
}

private enum BoundedText {
    static func clean(_ raw: String, maxBytes: Int) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= maxBytes,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return value
    }
}

// Not a claim that technical facts or the speaker are independently verified.
// A host must select the text from its separately reviewed publication boundary.
public struct PanelCard: Equatable, Sendable {
    public let lead: String
    public let points: [String]
    public let detail: String?

    public init?(lead: String, points: [String], detail: String? = nil) {
        guard let cleanLead = BoundedText.clean(lead, maxBytes: 280),
              (1...2).contains(points.count) else { return nil }
        var cleanPoints: [String] = []
        for point in points {
            guard let cleanPoint = BoundedText.clean(point, maxBytes: 180) else { return nil }
            cleanPoints.append(cleanPoint)
        }
        let cleanDetail: String?
        if let detail {
            guard let value = BoundedText.clean(detail, maxBytes: 900) else { return nil }
            cleanDetail = value
        } else {
            cleanDetail = nil
        }
        self.lead = cleanLead
        self.points = cleanPoints
        self.detail = cleanDetail
    }
}

public enum PanelStatus: Equatable, Sendable {
    case idle
    case waiting
    case finalUnverified
    case needsReview
    case unavailable
}

// Fixed, content-free labels; never interpolate untrusted transcript or error text.
public enum WithholdReason: Equatable, Sendable {
    case uncertainSource
    case interrupted
    case validationRequired

    public var label: String {
        switch self {
        case .uncertainSource: "Source uncertain — no answer displayed"
        case .interrupted: "Question interrupted — answer withdrawn"
        case .validationRequired: "Answer requires review — not displayed"
        }
    }
}

public enum PanelUpdate: Sendable {
    case begin(turn: TurnKey, question: String)
    case publish(turn: TurnKey, card: PanelCard)
    case withhold(turn: TurnKey, reason: WithholdReason)
    case stop
    case resume
}

public struct PanelState: Sendable {
    public private(set) var status: PanelStatus = .idle
    public private(set) var currentTurn: TurnKey?
    public private(set) var question: String?
    public private(set) var card: PanelCard?
    public private(set) var reason: WithholdReason?
    public private(set) var isStopped = false
    // Every queued begin/publish/withhold event must preserve its originating
    // epoch; a pre-stop event delivered after resume carries the old epoch.
    public private(set) var sessionEpoch: UInt64 = 1

    // Monotonic within the current epoch; the epoch rejects every prior
    // session's delayed event, so a new session may restart generations.
    private var highestGeneration: UInt64 = 0

    public init() {}

    @discardableResult
    public mutating func apply(_ update: PanelUpdate) -> Bool {
        switch update {
        case let .begin(turn, question):
            // Reject any stale event minted in a previous session, including
            // callbacks queued before stop but only delivered after resume.
            guard turn.sessionEpoch == sessionEpoch else { return false }
            if isStopped { return false }
            guard turn.generation > highestGeneration else { return false }
            // A newer turn supersedes the old card even if the replacement
            // question is malformed. Advance before examining untrusted text.
            highestGeneration = turn.generation
            currentTurn = nil
            self.question = nil
            card = nil
            reason = nil
            guard let cleanQuestion = BoundedText.clean(question, maxBytes: 500) else {
                reason = .validationRequired
                status = .needsReview
                return false
            }
            currentTurn = turn
            self.question = cleanQuestion
            status = .waiting
            return true

        case let .publish(turn, card):
            guard !isStopped, currentTurn == turn, status == .waiting else { return false }
            self.card = card
            reason = nil
            status = .finalUnverified
            return true

        case let .withhold(turn, reason):
            guard !isStopped, currentTurn == turn,
                  status == .waiting || status == .finalUnverified else { return false }
            card = nil
            self.reason = reason
            status = .needsReview
            return true

        case .stop:
            currentTurn = nil
            question = nil
            card = nil
            reason = nil
            isStopped = true
            status = .unavailable
            return true

        case .resume:
            // Fail closed rather than wrapping an epoch and reauthorizing old
            // queued events after an unrealistic UInt64 counter exhaustion.
            guard isStopped, sessionEpoch < UInt64.max else { return false }
            sessionEpoch += 1
            highestGeneration = 0
            // Resuming never resurrects prior content or the previous turn key.
            currentTurn = nil
            question = nil
            card = nil
            reason = nil
            isStopped = false
            status = .idle
            return true
        }
    }
}
