import Foundation

@MainActor public protocol HistorySavingPreferences:AnyObject {
    var savingEnabled:Bool{get set}
}
/// The only persisted preference is a nonprivate opt-in Boolean. Private titles,
/// times, rows, notes and indexes are never stored in preferences.
@MainActor public final class UserDefaultsHistoryPreferences:HistorySavingPreferences {
    private let defaults:UserDefaults
    private let key="relay.history.saving-enabled.v1"
    public init(defaults:UserDefaults = .standard){self.defaults=defaults}
    public var savingEnabled:Bool{get{defaults.bool(forKey:key)}set{defaults.set(newValue,forKey:key)}}
}
