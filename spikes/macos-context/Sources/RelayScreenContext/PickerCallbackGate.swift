import Foundation
/// Every picker observer is born with one token. Queued callbacks keep that token after removal.
struct PickerCallbackGate {
    private var active: UUID?
    mutating func begin() -> UUID { let token = UUID(); active = token; return token }
    mutating func retire() { active = nil }
    func accepts(_ token: UUID) -> Bool { active == token }
}
