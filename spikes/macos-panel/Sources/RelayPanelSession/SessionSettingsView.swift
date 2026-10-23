import AppKit
import SwiftUI
import RelayControls
import RelayScreenContext
import RelaySessionPanel

@MainActor struct SessionSettingsView:View {
    @ObservedObject var model:SessionApplicationModel
    var body:some View {
        TabView {
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    ScreenContextSettingsView(model:model.screen)
                    if let snapshot=model.screen.coordinator.snapshot {
                        TimelineView(.periodic(from:.now,by:1)) { _ in
                            let now=DispatchTime.now().uptimeNanoseconds
                            let age=now>=snapshot.capturedUptimeNanoseconds ? (now-snapshot.capturedUptimeNanoseconds)/1_000_000_000:0
                            Text("\(snapshot.source.label) · observed \(age)s ago · local OCR").font(.caption)
                        }
                        if let image=model.screen.coordinator.preview { Image(decorative:image,scale:1).resizable().scaledToFit().frame(maxHeight:220).accessibilityLabel("Selected window capture preview") }
                        Text(snapshot.text).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                    }
                    VisualInputOptions(model:model)
                }.padding()
            }.tabItem { Text("Screen context") }
            SelectedTextOptions(model:model).tabItem { Text("Selected text") }
            ControlsSettingsView(controller:model.controls)
                .onAppear { model.restoreShortcuts() }
                .onChange(of:model.controls.shortcuts) { _,_ in model.saveShortcuts() }
                .onDisappear { model.saveShortcuts() }
                .tabItem { Text("Shortcuts") }
        }.disabled(model.fixture)
    }
}

@MainActor private struct VisualInputOptions:View {
    @ObservedObject var model:SessionApplicationModel
    @ObservedObject private var visual:VisualInputSetupState
    init(model:SessionApplicationModel){self.model=model;visual=model.visual}
    private var status:String {
        switch visual.status {
        case .disabled:"Visual input is off."
        case .checking:"Testing the configured model."
        case .verified:visual.mayOfferImages ? "Visual input is enabled for this helper.":"The last check passed. Test again to enable visual input."
        case .unverified:"Visual input could not be verified. OCR text remains available."
        case .cancelled:"The visual-input test was cancelled."
        case .unavailable:"Visual input is unavailable with the current setup."
        case .busy:"Finish the current session or test before trying again."
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Divider();Text("Optional image understanding").font(.headline)
            Text("This test sends a small generated image using your configured ChatGPT plan. If it passes, Relay may send the selected window image with OCR for future questions. The check applies to this helper and model; it is not an account entitlement.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Test visual input and enable"){model.beginVisualVerification()}.disabled(!model.canTestVisualInput)
                if visual.needsDisable || visual.status != .disabled{Button("Disable visual input"){model.disableVisualInput()}}
            }
            Text(status).font(.caption)
            if let name=visual.model{Text("Configured model: "+name).font(.caption).foregroundStyle(.secondary)}
            if !model.oauth{Text("Enable AI suggestions in the main window to run this optional test. Existing Relay sign-in is required; account setup is not available in this window yet.").font(.caption).foregroundStyle(.secondary)}
            Text("OCR text stays available when images are off or a transfer is incomplete. Images require a successful text capture; selected text uses text only. An image-dependent answer is withheld if the selected window changes before it is ready.").font(.caption).foregroundStyle(.secondary)
            Text("Pause and End turn visual input off. Test again while idle before another session to enable it.").font(.caption).foregroundStyle(.secondary)
            Text("A successful check can expire or lose validity after a sign-in refresh. Relay may then use OCR text only; the check does not promise image input throughout a long interview.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor private struct SelectedTextOptions:View {
    @ObservedObject var model:SessionApplicationModel
    @Bindable private var service:SelectedTextService
    init(model:SessionApplicationModel){self.model=model;service=model.selectedText}
    private var apps:[NSRunningApplication] { NSWorkspace.shared.runningApplications.filter{$0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier}.sorted{($0.localizedName ?? "")<($1.localizedName ?? "")} }
    var body:some View {
        Form {
            Picker("Allow selected text from",selection:Binding(get:{model.selectedTextBundleID},set:{model.chooseSelectedTextApp($0)})) {
                Text("Choose a text app").tag("")
                ForEach(apps,id:\.processIdentifier) { app in if let bundle=app.bundleIdentifier { Text(app.localizedName ?? bundle).tag(bundle) } }
            }
            Toggle("Use selected text for explicit Help",isOn:Binding(get:{service.isEnabled},set:{model.setSelectedTextEnabled($0)})).disabled(model.selectedTextBundleID.isEmpty)
            Text("Only Help reads the focused selection from this app. Use its configured shortcut while the text app stays focused. Automatic audio questions use optional OCR instead. Secure and unsupported selections are unavailable.").font(.caption).foregroundStyle(.secondary)
            if service.isEnabled { Button("Request Accessibility access") { model.setSelectedTextEnabled(true) } }
            if let error=service.lastError { Text(error.localizedDescription).font(.caption).foregroundStyle(.secondary) }
            Text("Selected text takes priority over OCR for Help. The answer names the context source it used. Selected text is task context, never confirmed background.").font(.caption).foregroundStyle(.secondary)
        }.padding()
    }
}
