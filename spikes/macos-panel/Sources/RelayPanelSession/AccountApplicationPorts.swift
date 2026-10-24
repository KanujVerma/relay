import AppKit
import Foundation
import RelayAccount
import RelaySessionPanel

@MainActor protocol ChatGPTPlanPreferences: AnyObject { var enabled: Bool { get set } }
@MainActor final class UserDefaultsChatGPTPlanPreferences: ChatGPTPlanPreferences {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var enabled: Bool {
        get { defaults.bool(forKey: "relay.useChatGPTPlan.v1") }
        set { defaults.set(newValue, forKey: "relay.useChatGPTPlan.v1") }
    }
}
@MainActor final class FixtureChatGPTPlanPreferences: ChatGPTPlanPreferences { var enabled = false }

/// Explicit native dependency ports. Production uses the fixed default storage,
/// bundled runtime and native browser; synthetic tests inject every effect.
@MainActor struct AccountApplicationPorts {
    let storage: AccountStorage
    let preferences: any ChatGPTPlanPreferences
    let control: @MainActor (HelperRuntimeLocation, AccountSecretBootstrap) throws -> any AccountPort
    let openBrowser: @MainActor (URL) -> Bool
    let sessionArguments: @MainActor (HelperRuntimeLocation, HelperMode) -> [String]
}
