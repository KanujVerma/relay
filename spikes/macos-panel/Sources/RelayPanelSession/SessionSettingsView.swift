import AppKit
import SwiftUI
import RelayControls
import RelayScreenContext

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
                    Text("This version sends local OCR text only. Image understanding is off. OCR can miss code symbols, indentation and diagram relationships.").font(.caption).foregroundStyle(.secondary)
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
