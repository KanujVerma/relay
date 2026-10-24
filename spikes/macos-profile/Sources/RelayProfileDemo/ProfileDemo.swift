import Foundation
import RelayProfile
import SwiftUI

/// Demo composition only. The integrated app injects its existing helper port.
/// Launch creates a window but performs no import, Keychain access or inference.
@main @MainActor struct ProfileDemo: App {
    @StateObject private var controller: ProfileController
    init() {
        let arguments = CommandLine.arguments
        func option(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        let repository = URL(fileURLWithPath: option("--repository") ?? FileManager.default.currentDirectoryPath)
        let python = URL(fileURLWithPath: option("--python") ?? "/opt/homebrew/bin/python3")
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let vault = ProfileVault(directory: support.appendingPathComponent("Relay/Profile", isDirectory: true))
        _controller = StateObject(wrappedValue: ProfileController(
            client: ProfileClient(port: PipeProfilePort(python: python, repository: repository)), vault: vault))
    }
    var body: some Scene {
        WindowGroup("Relay interview preparation") { ProfilePreparationView(controller: controller) }
            .defaultSize(width: 880, height: 780)
    }
}
