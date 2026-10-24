import SwiftUI
import KeyboardShortcuts

@MainActor public struct ControlsSettingsView: View {
    @Bindable private var controller: ControlsController
    @State private var settingsError: String?
    public init(controller: ControlsController) { self.controller = controller }

    public var body: some View {
        Form {
            Toggle("Enable global shortcuts", isOn: Binding(get: { controller.isEnabled }, set: { enabled in
                attempt { try controller.setEnabled(enabled) }
            }))
            Text("Assign shortcuts below. Use Command or Control with a key. Shortcuts do not require Accessibility access.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(ControlAction.allCases, id: \.self) { action in
                HStack {
                    Text(action.title)
                    Spacer()
                    KeyboardShortcuts.Recorder(shortcut: Binding(
                        get: { controller.shortcuts[action]?.keyboardShortcut },
                        set: { shortcut in attempt { try controller.configure(shortcut.map(ControlShortcut.init), for: action) } }
                    ))
                    .shortcutValidation { shortcut in
                        do { try controller.validate(.init(shortcut), for: action); return .allow }
                        catch { return .disallow(reason: "\(error.localizedDescription)") }
                    }
                    Button("Clear") { attempt { try controller.configure(nil, for: action) } }
                        .disabled(controller.shortcuts[action] == nil)
                }
            }
            Text("macOS and this app's menu conflicts are checked while recording. Another app may still use the same keys; choose a different shortcut if an action does not run. Hiding the panel is an ordinary window action.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = settingsError ?? controller.lastError?.localizedDescription {
                Text(message).foregroundStyle(.red).accessibilityLabel("Shortcut error: \(message)")
            }
        }
        .padding()
    }

    private func attempt(_ operation: () throws -> Void) {
        do { try operation(); settingsError = nil }
        catch { settingsError = error.localizedDescription }
    }
}
