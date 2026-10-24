import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RelayControls
import RelayScreenContext
import RelaySessionPanel
import RelaySessionCapture
import RelayAccount

enum RelaySettingsSection:String,CaseIterable,Sendable {
    case general="General",screen="Screen context",ai="AI",history="History",responses="Responses",shortcuts="Shortcuts",advanced="Advanced"
    var symbol:String{switch self{case .general:"slider.horizontal.3";case .screen:"rectangle.dashed";case .ai:"sparkles";case .history:"clock.arrow.circlepath";case .responses:"text.bubble";case .shortcuts:"keyboard";case .advanced:"wrench.and.screwdriver"}}
}
@MainActor struct SessionSettingsView:View {
    @ObservedObject var model:SessionApplicationModel
    @ObservedObject private var setup:SpeechSetupCoordinator
    @ObservedObject private var visual:VisualInputSetupState
    var selectedSection:RelaySettingsSection{model.settingsSection}
    @State private var selectingASR=false
    @State private var selectingVAD=false
    @Environment(\.openWindow) private var openWindow
    init(model:SessionApplicationModel){self.model=model;setup=model.speechSetup;visual=model.visual}
    var body:some View {
        VStack(spacing:0){
            HStack{Text("Settings").font(.system(size:13,weight:.semibold));Spacer();Text("Relay").font(.system(size:12)).foregroundStyle(RelayTheme.muted)}.padding(.horizontal,20).frame(height:40).background(.white.opacity(0.035))
            HStack(spacing:4){ForEach(RelaySettingsSection.allCases,id:\.self){item in Button{model.settingsSection=item}label:{VStack(spacing:7){Image(systemName:item.symbol).font(.system(size:18));Text(item.rawValue).font(.system(size:11,weight:.medium))}.frame(width:106,height:64).background(selectedSection==item ? .white.opacity(0.08):.clear,in:RoundedRectangle(cornerRadius:10))}.buttonStyle(.plain).foregroundStyle(selectedSection==item ? .white:RelayTheme.muted)};Spacer()}.padding(.horizontal,20).padding(.vertical,12)
            Divider().overlay(RelayTheme.line)
            ScrollView{VStack(alignment:.leading,spacing:24){content}.padding(.horizontal,32).padding(.vertical,28).frame(maxWidth:760,alignment:.leading).frame(maxWidth:.infinity)}
        }.frame(width:920,height:670).background(RelayTheme.base).foregroundStyle(.white).preferredColorScheme(.dark).disabled(model.fixture)
            .fileImporter(isPresented:$selectingASR,allowedContentTypes:[.folder]){if case .success(let url)=$0{model.asrFolder=url.path}}
            .fileImporter(isPresented:$selectingVAD,allowedContentTypes:[.folder]){if case .success(let url)=$0{model.vadFolder=url.path}}
    }
    @ViewBuilder private var content:some View {
        switch selectedSection {
        case .general:
            settingsTitle("Conversation","Choose what Relay listens to. Audio starts only when you start a session.")
            RelaySourceControls(model:model)
            Divider().overlay(RelayTheme.line)
            settingsTitle("Local speech","Speech files are prepared automatically and reused on your Mac.")
            PreparationStatusView(presentation:preparationWithoutRecovery,onAction:{_ in})
            Button("Open session setup"){openWindow(id:"relay-home")}.buttonStyle(RelayQuietButtonStyle())
            Text("First preparation downloads about 225 MB. Speech readiness does not grant microphone or conversation-app access; macOS may request that when you start.").font(.system(size:12)).foregroundStyle(RelayTheme.muted)
            Text("Speech recognition currently supports English.").font(.system(size:12)).foregroundStyle(RelayTheme.muted)
        case .screen:
            settingsTitle("Screen context","Choose one window to supply visible task context. You control its access.")
            ScreenContextSettingsView(model:model.screen)
            Divider().overlay(RelayTheme.line)
            SelectedTextOptions(model:model)
        case .ai:
            AccountSettingsView(controller:model.account)
            Text("Local reference cards remain available with AI off. Finish or pause the current session before changing your connection.").font(.system(size:12)).foregroundStyle(RelayTheme.muted)
            Divider().overlay(RelayTheme.line)
            VisualInputOptions(model:model)
        case .responses:
            ResponsePreferencesSettingsView(model:model)
        case .shortcuts:
            settingsTitle("Keyboard shortcuts","Control Relay's own window and current answer.")
            ControlsSettingsView(controller:model.controls).onAppear{model.restoreShortcuts()}.onChange(of:model.controls.shortcuts){_,_ in model.saveShortcuts()}.onDisappear{model.saveShortcuts()}
        case .history:
            HistorySettingsOptions(model:model)
        case .advanced:
            settingsTitle("Advanced speech files","Leave both paths empty to use automatic setup. Custom files require both folders and explicit permission to use their models.")
            VStack(alignment:.leading,spacing:12){TextField("ASR model folder",text:$model.asrFolder);Button("Choose speech folder"){selectingASR=true};TextField("Compiled VAD model",text:$model.vadFolder);Button("Choose detector"){selectingVAD=true};Toggle("I have permission to use these custom speech models",isOn:$model.modelLicensesAcknowledged)}.disabled(model.running || model.starting || model.stopping || setup.snapshot.isBusy)
            VStack(alignment:.leading,spacing:8){
                Text("Managed speech licenses").font(.system(size:13,weight:.medium))
                Link("Parakeet · NVIDIA Open Model License",destination:URL(string:"https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/")!)
                Link("Silero VAD · MIT",destination:URL(string:"https://github.com/snakers4/silero-vad/blob/master/LICENSE")!)
                Link("FluidAudio · Apache 2.0",destination:URL(string:"https://github.com/FluidInference/FluidAudio/blob/c79c4106b954f81205113c3343e5a7e59a1089b5/LICENSE")!)
            }.font(.system(size:12))
            Divider().overlay(RelayTheme.line)
            Text("Role: "+model.role).font(.system(size:12)).foregroundStyle(RelayTheme.muted)
            Text("Image checks expire after 15 minutes or a sign-in refresh. Pause and End turn images off; test again while idle. Only a current source/request and actual verified model route can use an image.").font(.system(size:12)).foregroundStyle(RelayTheme.muted)
        }
    }
    private var preparationWithoutRecovery:RelayPreparationPresentation{var value=RelayPreparationPresentation(setup.snapshot);value.recovery = .none;return value}
    private func settingsTitle(_ title:String,_ subtitle:String)->some View{VStack(alignment:.leading,spacing:8){Text(title).font(.system(size:18,weight:.semibold));Text(subtitle).font(.system(size:13)).lineSpacing(4).foregroundStyle(RelayTheme.secondary)}}
}
@MainActor private struct HistorySettingsOptions:View{
    @ObservedObject var model:SessionApplicationModel
    @ObservedObject private var history:SessionHistoryCoordinator
    @Environment(\.openWindow) private var openWindow
    init(model:SessionApplicationModel){self.model=model;history=model.history}
    var body:some View{
        VStack(alignment:.leading,spacing:16){
            Text("Local session history").font(.system(size:18,weight:.semibold))
            Text("Optional saving keeps final audio-session transcript text and your manual notes encrypted on this Mac for 30 days. No raw audio, screenshots or screen text is saved. Typed chats and suggested answers are not saved here. Nothing is added to My Context automatically.").font(.system(size:13)).lineSpacing(4).foregroundStyle(RelayTheme.secondary)
            Toggle("Save session text locally",isOn:Binding(get:{history.savingEnabled},set:{enabled in if enabled{Task{try? await history.enableSaving()}}else{history.stopSaving()}})).disabled(!history.savingEnabled && (!model.canEnableHistory || history.isBusy))
            Text(history.snapshot.message).font(.system(size:12)).foregroundStyle(RelayTheme.muted)
            HStack{Button("Open History"){openWindow(id:"relay-history")}.buttonStyle(RelayQuietButtonStyle());Button("Lock history"){history.lock()}.buttonStyle(RelayQuietButtonStyle())}
            Text("Enable saving while idle. Stop saving keeps existing history available. Lock turns saving off and closes it. Recording permission changes do not delete saved history; use History to delete a source, a session or everything. Expiry runs when history is accessed, and exported copies remain yours to manage.").font(.system(size:12)).lineSpacing(4).foregroundStyle(RelayTheme.muted)
        }
    }
}
@MainActor private struct VisualInputOptions:View {
    @ObservedObject var model:SessionApplicationModel
    @ObservedObject private var visual:VisualInputSetupState
    init(model:SessionApplicationModel){self.model=model;visual=model.visual}
    private var status:String{switch visual.status{case .disabled:"Images are off";case .checking:"Testing visual input…";case .verified:visual.mayOfferImages ? "Visual input enabled (last check passed)":"Last check passed; test again to enable";case .unverified:"Visual input could not be verified";case .cancelled:"Visual test cancelled";case .unavailable:"Visual input unavailable with this setup";case .busy:"Finish the current session or test first"}}
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            Text("Optional image understanding").font(.system(size:16,weight:.semibold))
            Text("This sends one generated test image using your configured plan. If verified, Relay may use your selected-window image alongside its text for future questions.").font(.system(size:13)).lineSpacing(4).foregroundStyle(RelayTheme.secondary)
            HStack{Button("Test and enable images"){model.beginVisualVerification()}.buttonStyle(RelayQuietButtonStyle()).disabled(!model.canTestVisualInput);if visual.needsDisable || visual.status != .disabled{Button("Turn off"){model.disableVisualInput()}.buttonStyle(RelayQuietButtonStyle())}}
            Text(status).font(.system(size:12)).foregroundStyle(RelayTheme.muted)
            Text("Pause and End switch images off. Checks can expire or lose validity after a sign-in refresh; OCR text remains available.").font(.system(size:12)).foregroundStyle(RelayTheme.muted)
            if let name=visual.model{Text("Configured model: "+name).font(.system(size:11)).foregroundStyle(RelayTheme.muted)}
        }
    }
}
@MainActor private struct SelectedTextOptions:View {
    @ObservedObject var model:SessionApplicationModel
    @Bindable private var service:SelectedTextService
    init(model:SessionApplicationModel){self.model=model;service=model.selectedText}
    private var apps:[NSRunningApplication]{NSWorkspace.shared.runningApplications.filter{$0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier}.sorted{($0.localizedName ?? "")<($1.localizedName ?? "")}}
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            Text("Selected text for Help").font(.system(size:16,weight:.semibold))
            Picker("Allowed app",selection:Binding(get:{model.selectedTextBundleID},set:{model.chooseSelectedTextApp($0)})){Text("Choose a text app").tag("");ForEach(apps,id:\.processIdentifier){app in if let bundle=app.bundleIdentifier{Text(app.localizedName ?? bundle).tag(bundle)}}}
            Toggle("Use its selected text for explicit Help",isOn:Binding(get:{service.isEnabled},set:{model.setSelectedTextEnabled($0)})).disabled(model.selectedTextBundleID.isEmpty)
            Text("Use the Help shortcut while that app stays focused. Automatic questions use optional screen text instead. Selected text is task context, never confirmed personal history.").font(.system(size:12)).foregroundStyle(RelayTheme.muted)
            if let error=service.lastError{Text(error.localizedDescription).font(.system(size:12)).foregroundStyle(.orange)}
        }
    }
}
