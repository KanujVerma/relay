import Foundation

/// Settings metadata only. The encrypted ProfileVault remains the facts store.
@MainActor public protocol SessionContextUsePreferences:AnyObject {
    var useInSessions:Bool{get set}
}
@MainActor public final class UserDefaultsSessionContextUsePreferences:SessionContextUsePreferences {
    private let defaults:UserDefaults
    private static let key="relay.profile.useInSessions.v1"
    public init(defaults:UserDefaults = .standard){self.defaults=defaults}
    public var useInSessions:Bool {
        get{defaults.bool(forKey:Self.key)}
        set{defaults.set(newValue,forKey:Self.key)}
    }
}
