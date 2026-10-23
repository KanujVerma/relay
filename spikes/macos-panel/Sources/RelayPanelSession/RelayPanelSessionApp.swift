import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RelayProfile
import RelaySessionPanel
import RelayControls
import RelayScreenContext

@main struct RelayPanelSessionApp: App {
    @StateObject private var model=SessionApplicationModel()
    var body: some Scene {
        Window("Relay",id:"relay-session") { SessionView(model:model) }
        .defaultSize(width:570,height:620)
    }
}

@MainActor private struct SessionView: View {
    @ObservedObject var model:SessionApplicationModel
    @ObservedObject private var visual:VisualInputSetupState
    init(model:SessionApplicationModel){self.model=model;visual=model.visual}
    @State private var settings=false
    @State private var preparing=false
    @State private var setup=true
    @State private var selectingASR=false
    @State private var selectingVAD=false
    private var apps:[NSRunningApplication] { NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }.sorted { ($0.localizedName ?? "")<($1.localizedName ?? "") } }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text("Relay").font(.title2.bold());Spacer()
                Text(model.fixture ? "OFFLINE FIXTURE":visual.isBusy ? "VISUAL INPUT CHECK":model.paused ? "PAUSED":model.running ? "SESSION ACTIVE":"READY").font(.caption.bold()).foregroundStyle(.secondary)
            }
            if model.fixture { Text("Synthetic audio and injected answers. No microphone or AI request.").font(.caption).foregroundStyle(.secondary) }
            if !model.running && !model.fixture {
                Toggle("Use configured ChatGPT plan for AI suggestions",isOn:Binding(get:{model.oauth},set:{enabled in Task { await model.setAIEnabled(enabled) }})).disabled(!model.canChangeAIMode)
                Text("Uses the existing Relay sign-in. Account setup is not available in this window yet. AI suggestions run during a session; the optional visual-input test makes one explicit request while idle. Local reference cards remain available with AI off.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Session setup",isExpanded:$setup) {
                    VStack(alignment:.leading,spacing:10) {
                        Picker("Interview app",selection:$model.selectedBundleID) {
                            Text("Select an app").tag("")
                            ForEach(apps,id:\.processIdentifier) { app in if let bundle=app.bundleIdentifier { Text(app.localizedName ?? bundle).tag(bundle) } }
                        }
                        Toggle("Include my microphone replies",isOn:$model.microphoneEnabled)
                        HStack { Button("Choose speech models") { selectingASR=true };Text(model.asrFolder.isEmpty ? "Not selected":"Selected").font(.caption).foregroundStyle(.secondary) }
                        HStack { Button("Choose speech detector") { selectingVAD=true };Text(model.vadFolder.isEmpty ? "Not selected":"Selected").font(.caption).foregroundStyle(.secondary) }
                        Toggle("This conversation permits recording and assistance",isOn:$model.authorizedConversation)
                        Toggle("I have permission to use these local speech models",isOn:$model.modelLicensesAcknowledged)
                    }.padding(.top,8)
                }
            }
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    Text(model.snapshot.question ?? (model.running ? "Listening for the next question":"Ready for your interview"))
                        .font(.headline).textSelection(.enabled).accessibilityAddTraits(.isHeader)
                    Text(model.snapshot.status).font(.caption).foregroundStyle(.secondary)
                    if let card=model.snapshot.card {
                        Text(card.lead).font(.body).textSelection(.enabled)
                        ForEach(Array(card.points.enumerated()),id:\.offset) { _,point in Text("• "+point).font(.callout).textSelection(.enabled) }
                        if let detail=card.detail {
                            DisclosureGroup(detail.kind=="code" ? "Code and detail":"More detail",isExpanded:$model.expanded) {
                                ScrollView(.horizontal) {
                                    Text(detail.text).font(.system(.callout,design:detail.kind=="code" ? .monospaced:.default)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(.top,8)
                                }
                            }
                        }
                    } else if model.running { Text("Talking points appear automatically as the discussion develops.").foregroundStyle(.secondary) }
                    if !model.contextStatus.isEmpty { Text(model.contextStatus).font(.caption).foregroundStyle(.secondary) }
                    if let error=model.error { Text(error).foregroundStyle(.secondary).font(.callout) }
                }.frame(maxWidth:.infinity,alignment:.leading)
                    .background(SessionWindowAttachment { window,scroll in model.attachWindow(window,scrollView:scroll) })
            }
            Divider()
            HStack {
                if model.running || model.starting {
                    Button("Pause") { model.performWindowAction(.pause) }.disabled(model.stopping)
                    Button("End") { model.performWindowAction(.endSession) }
                } else {
                    Button(model.paused ? "Resume":"Start session") { Task { await model.start() } }.buttonStyle(.borderedProminent).disabled(!model.canStartSession)
                    if model.paused || visual.isBusy { Button("End") { model.performWindowAction(.endSession) } }
                }
                Button("Help") { model.performWindowAction(.requestHelp) }.disabled(!model.running || model.stopping)
                Button("Copy") { model.performWindowAction(.copyAnswer) }.disabled(model.snapshot.card == nil)
                Spacer()
                Button("Settings") { settings=true }
            }
            HStack {
                Button("Prepare background") { preparing=true }.disabled(model.fixture || model.stopping || visual.isBusy)
                if model.stopping { Text("Waiting for the previous session to finish").font(.caption).foregroundStyle(.secondary) }
            }
            if model.paused { Text("Resume starts a fresh conversation. Saved background and explicit context settings stay available.").font(.caption).foregroundStyle(.secondary) }

        }.padding(22).frame(minWidth:480,minHeight:430)
        .onChange(of:model.snapshot.replacement) { _,_ in model.expanded=false }
        .task { if model.fixture { await model.start() } }
        .sheet(isPresented:$settings) { SessionSettingsView(model:model).frame(minWidth:650,minHeight:650).toolbar { Button("Done") { settings=false } } }
        .sheet(isPresented:$preparing) { ProfilePreparationView(controller:model.profile,role:model.role).frame(minWidth:620,minHeight:650).padding().toolbar { Button("Done") { preparing=false } } }
        .fileImporter(isPresented:$selectingASR,allowedContentTypes:[.folder]) { if case .success(let url)=$0 { model.asrFolder=url.path } }
        .fileImporter(isPresented:$selectingVAD,allowedContentTypes:[.folder]) { if case .success(let url)=$0 { model.vadFolder=url.path } }
    }
}
