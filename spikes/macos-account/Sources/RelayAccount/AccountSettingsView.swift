import SwiftUI

/// Every enabled action consumes the real controller. No mock account/model
/// picker, usage meter, profile-consent toggle or private authorization URL is rendered.
public struct AccountSettingsView: View {
    @ObservedObject private var controller: AccountController
    @State private var showNotice = false
    public init(controller: AccountController) { self.controller = controller }
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ChatGPT connection").font(.title2.weight(.semibold))
                Text("Use your ChatGPT plan for eligible AI requests in Relay.").foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Continue with ChatGPT") { Task { await controller.connect() } }
                    .buttonStyle(.borderedProminent).disabled(!controller.canMutate)
                Button("Restore saved connection") { Task { await controller.restore() } }
                    .disabled(!controller.canMutate)
                if controller.canCancel { Button("Cancel") { Task { await controller.cancel() } } }
                if controller.busy { ProgressView().controlSize(.small) }
            }
            Text(controller.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            if let snapshot = controller.snapshot {
                ForEach(snapshot.registrations) { registration in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: registration.id == snapshot.activeRegistrationID ? "checkmark.circle.fill" : "person.crop.circle")
                            .foregroundStyle(registration.id == snapshot.activeRegistrationID ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(registration.label).fontWeight(.medium)
                            if let email = registration.email { Text(email).font(.callout).foregroundStyle(.secondary) }
                            Text("Identity checked at sign-in. This label identifies a saved registration.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if registration.id != snapshot.activeRegistrationID {
                            Button("Use this account") { Task { await controller.select(registration.id) } }
                                .disabled(!controller.canMutate || registration.sessionState != .available)
                        }
                        Button("Reconnect") { Task { await controller.reconnect(registration.id) } }.disabled(!controller.canMutate)
                    }.padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                }
                if let registration = snapshot.activeRegistration {
                    Divider()
                    Toggle("Use ChatGPT plan for AI", isOn: Binding(get: { controller.aiEnabled }, set: { value in Task { await controller.setAIEnabled(value) } }))
                        .disabled(!controller.canMutate || registration.planUsageState != .granted || registration.sessionState != .available)
                    if registration.planUsageState != .granted {
                        Text("Signing in and allowing plan usage are separate choices.").font(.callout).foregroundStyle(.secondary)
                        Button("Enable ChatGPT plan usage") { Task { await controller.enablePlan(registration.id) } }.disabled(!controller.canMutate)
                    }
                    HStack {
                        if let selection = controller.inferenceSelection {
                            Text("Automatic model: \(snapshot.models.first(where: { $0.slug == selection.model })?.displayName ?? selection.model)").font(.callout)
                        } else { Text("A current model check is required before AI can run.").font(.callout).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Refresh models") { Task { await controller.refreshModels() } }.disabled(!controller.canMutate)
                        Button("Sign out") { Task { await controller.signOut(registration.id) } }.disabled(!controller.canMutate)
                    }
                }
            }
            Link("Manage usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
            Text("Your Personal Brain and its approval settings remain separate. Connecting does not import your ChatGPT conversations.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .onAppear { showNotice = controller.needsPlanNotice }
        .onChange(of: controller.needsPlanNotice) { _, value in if value { showNotice = true } }
        .sheet(isPresented: $showNotice) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Using your ChatGPT plan").font(.title2.weight(.semibold))
                Text("Relay sends eligible AI requests through this ChatGPT plan. You can review usage and adjust limits in ChatGPT settings.")
                Link("Manage usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                Button("Got it") { Task { await controller.acknowledgePlanNotice(); showNotice = false } }
                    .buttonStyle(.borderedProminent).disabled(controller.busy)
            }.padding(28).frame(width: 420).interactiveDismissDisabled()
        }
    }
}
