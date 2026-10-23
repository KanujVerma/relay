import Foundation

public struct ProfileMemoryFact: Decodable, Sendable, Identifiable, Equatable {
    public var id: String { factID }
    public let factID: String
    public let claimKey: String
    public let claimText: String
    public let actor: String
    public let sourceID: String
    public let sourceLabel: String
    enum CodingKeys: String, CodingKey {
        case factID = "fact_id", claimKey = "claim_key", claimText = "claim_text"
        case actor, sourceID = "source_id", sourceLabel = "source_label"
    }
}

struct ProfileMemoryPage: Decodable {
    let memories: [ProfileMemoryFact]
    let totalCount: Int
    let nextAfter: String?
    enum CodingKeys: String, CodingKey {
        case memories, totalCount = "total_count", nextAfter = "next_after"
    }

    func validate(after: String?) throws {
        let ids = memories.map(\.factID)
        guard memories.count <= 8, totalCount >= memories.count,
              ids == ids.sorted(), Set(ids).count == ids.count,
              after != nil || !memories.isEmpty || totalCount == 0,
              memories.allSatisfy({ fact in
                  !fact.factID.isEmpty && fact.factID.count <= 64 &&
                  !fact.sourceID.isEmpty && fact.sourceID.count <= 64 &&
                  !fact.claimKey.isEmpty && fact.claimKey.count <= 160 &&
                  !fact.claimText.isEmpty && fact.claimText.count <= 2000 &&
                  !fact.sourceLabel.isEmpty && fact.sourceLabel.count <= 64 &&
                  ["self", "team", "teammate"].contains(fact.actor) &&
                  (after.map { fact.factID > $0 } ?? true)
              }),
              nextAfter == nil || (nextAfter == ids.last && !ids.isEmpty && totalCount > ids.count)
        else { throw ProfileError.invalidPayload }
    }
}
