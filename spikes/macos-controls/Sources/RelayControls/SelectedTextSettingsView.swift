import SwiftUI

/// The host supplies its explicitly chosen application allowlist. This view
/// never reads text: the separate Help action in the source app does that.
@MainActor public struct SelectedTextSettingsView: View {
    @Bindable private var service: SelectedTextService
    private let allowedBundleIDs: Set<String>
    @State private var settingsError: String?

    public init(service: SelectedTextService, allowedBundleIDs: Set<String>) {
        self.service = service
        self.allowedBundleIDs = allowedBundleIDs
    }

    public var body: some View {
        Form {
            Toggle("Use selected text from chosen apps", isOn: Binding(
                get: { service.isEnabled },
                set: { enabled in
                    if enabled { enable() }
                    else { service.revoke(); settingsError = nil }
                }
            ))
            .disabled(allowedBundleIDs.isEmpty)
            Text("Only an explicit Help action reads the focused selection. Password fields and unsupported selections are unavailable. Ordinary shortcuts and audio do not require this permission.")
                .font(.caption).foregroundStyle(.secondary)
            if allowedBundleIDs.isEmpty {
                Text("Choose allowed applications in session setup first.")
            } else {
                Text("Allowed apps: \(allowedBundleIDs.sorted().joined(separator: ", "))")
                    .font(.caption)
            }
            if service.isEnabled {
                Button("Request Accessibility access") { enable() }
            }
            if let message = settingsError ?? service.lastError?.localizedDescription {
                Text(message).foregroundStyle(.red)
            }
        }
        .padding()
        .onChange(of: allowedBundleIDs) { _, _ in service.revoke() }
    }

    private func enable() {
        do {
            try service.enable(allowedBundleIDs: allowedBundleIDs, requestPermission: true)
            settingsError = nil
        } catch { settingsError = error.localizedDescription }
    }
}
