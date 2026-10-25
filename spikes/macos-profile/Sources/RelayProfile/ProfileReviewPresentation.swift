import CryptoKit
import Foundation

/// Presentation defaults never establish ownership or approve a source.
enum ProfileReviewPresentation {
    static func claimKey(sourceID: String, factID: String, topic: String,
                         selectedClaimKey: String? = nil) -> String {
        // An existing ledger key is identity, not free text to normalize.
        if let selectedClaimKey { return selectedClaimKey }
        let explicit = topic.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                     locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: ".", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if !explicit.isEmpty { return explicit }
        // Length prefixes preserve the two identity boundaries without making
        // source text, a guessed topic or a model claim into a memory key.
        let identity = "\(sourceID.utf8.count):\(sourceID)\(factID.utf8.count):\(factID)"
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return "reviewed." + digest
    }

    static func canApprove(actor: String, claimKey: String, hasExisting: Bool,
                           replacesExisting: Bool, requiresExisting: Bool = false) -> Bool {
        ["self", "team", "teammate"].contains(actor) && !claimKey.isEmpty && claimKey.count <= 160 &&
            (!hasExisting || replacesExisting) && (!requiresExisting || (hasExisting && replacesExisting))
    }
}
