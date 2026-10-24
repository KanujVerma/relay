import AppKit
import SwiftUI
import RelayProfile
import RelaySessionPanel
import RelaySessionCapture
import RelayControls

@main struct RelayPanelSessionApp:App {
    @StateObject private var model=SessionApplicationModel()
    @StateObject private var shell=RelayWindowShell()
    var body:some Scene {
        Window("Relay",id:"relay-home"){RelayHomeAdapter(model:model,shell:shell)}.defaultSize(width:920,height:670).windowResizability(.contentSize)
        Window("Relay session",id:"relay-live"){RelayLiveAdapter(model:model,shell:shell)}.windowStyle(.hiddenTitleBar).windowResizability(.contentSize)
        Window("My Context",id:"relay-context"){RelayMemoryWorkspace(model:model)}.defaultSize(width:920,height:720)
        Window("History",id:"relay-history"){RelayHistoryWorkspace(model:model)}.defaultSize(width:920,height:670)
        Window("Relay Settings",id:"relay-settings"){SessionSettingsView(model:model)}.defaultSize(width:920,height:670).windowResizability(.contentSize)
        MenuBarExtra("Relay",systemImage:model.running ? "waveform.circle.fill":"waveform"){RelayMenu(model:model)}
        .commands{RelayAppCommands(model:model)}
    }
}
private struct RelayAppCommands:Commands {
    let model:SessionApplicationModel
    @Environment(\.openWindow) private var openWindow
    var body:some Commands {
        CommandGroup(replacing:.appSettings){Button("Settings…"){openWindow(id:"relay-settings")}.keyboardShortcut(",",modifiers:.command)}
        CommandGroup(replacing:.appTermination){Button("Quit Relay"){Task{await model.shutdown();NSApplication.shared.terminate(nil)}}.keyboardShortcut("q",modifiers:.command)}
    }
}
@MainActor private struct RelayMenu:View {
    @ObservedObject var model:SessionApplicationModel
    @Environment(\.openWindow) private var openWindow
    var body:some View {
        Text("Relay · "+model.relayPresentation.status)
        Button("Show Relay"){openWindow(id:model.running || model.assistantActive || model.paused || model.stopping ? "relay-live":"relay-home")}
        Divider()
        if model.paused{Button("Resume"){model.performWindowAction(.resume)}.disabled(!model.relayPresentation.allows(.resume))}
        else{Button("Pause"){model.performWindowAction(.pause)}.disabled(!model.relayPresentation.allows(.pause))}
        Button("End session"){model.performWindowAction(.endSession)}.disabled(!model.relayPresentation.allows(.end))
        Divider()
        Button("My Context"){openWindow(id:"relay-context")}.disabled(model.fixture)
        Button("History"){openWindow(id:"relay-history")}.disabled(model.fixture)
        Button("Settings…"){openWindow(id:"relay-settings")}
        Divider()
        Button("Quit Relay"){Task{await model.shutdown();NSApplication.shared.terminate(nil)}}
    }
}
@MainActor private struct RelayHomeAdapter:View {
    @ObservedObject var model:SessionApplicationModel
    @ObservedObject private var setup:SpeechSetupCoordinator
    @ObservedObject private var visual:VisualInputSetupState
    @ObservedObject private var preferences:ResponsePreferencesCoordinator
    @ObservedObject var shell:RelayWindowShell
    @Environment(\.openWindow) private var openWindow
    init(model:SessionApplicationModel,shell:RelayWindowShell){self.model=model;self.shell=shell;setup=model.speechSetup;visual=model.visual;preferences=model.responsePreferences}
    private var router:RelayCommandRouter{RelayCommandRouter(state:{model.relayPresentation},control:model.performWindowAction,start:{await model.start();if model.running{openWindow(id:"relay-live")}},cancelPreparation:model.cancelPreparation,retryPreparation:{await model.retryPreparation();if model.running{openWindow(id:"relay-live")}},openContext:{openWindow(id:"relay-context")},openSettings:{openWindow(id:"relay-settings")},openAISettings:{model.showAISettings{openWindow(id:"relay-settings")}},showSession:{openWindow(id:"relay-live")})}
    var body:some View {
        RelayHomeView(state:model.relayPresentation,preparation:model.relayPreparation,aiEnabled:model.oauth,error:model.error,fixture:model.fixture,assistant:model.assistant,openHistory:{openWindow(id:"relay-history")},guideLabel:model.responseGuideName,onResponsePreferences:{model.showResponsePreferences{openWindow(id:"relay-settings")}},onAction:{router.perform($0)}){RelaySourceControls(model:model)}
            .task{if model.fixture && shell.claimFixtureStart(){await model.start();if model.running{openWindow(id:"relay-live")}}}
            .onChange(of:model.running){_,running in if running{shell.expanded=true;openWindow(id:"relay-live")}}
            .onChange(of:model.assistantActive){_,active in if active{shell.expanded=true;openWindow(id:"relay-live")}}
    }
}
@MainActor struct RelaySourceControls:View {
    @ObservedObject var model:SessionApplicationModel
    private var apps:[NSRunningApplication]{NSWorkspace.shared.runningApplications.filter{$0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier}.sorted{($0.localizedName ?? "")<($1.localizedName ?? "")}}
    var body:some View {
        VStack(alignment:.leading,spacing:14){
            HStack{
                Picker("Conversation app",selection:$model.selectedBundleID){Text(model.microphoneEnabled ? "Microphone only":"Choose an app").tag("");ForEach(apps,id:\.processIdentifier){app in if let bundle=app.bundleIdentifier{Text(app.localizedName ?? bundle).tag(bundle)}}}.labelsHidden().frame(maxWidth:.infinity,alignment:.leading).accessibilityLabel("Conversation app")
                Toggle("My microphone",isOn:$model.microphoneEnabled).font(.system(size:12)).toggleStyle(.checkbox)
            }.disabled(model.running || model.starting || model.stopping || model.accountPreparationActive || model.accountPreparationCancelling || model.speechSetup.snapshot.isBusy)
            Toggle("This conversation permits recording and assistance",isOn:Binding(get:{model.authorizedConversation},set:{allowed in if !allowed && (model.running || model.starting){model.performWindowAction(.endSession)};model.authorizedConversation=allowed})).font(.system(size:12)).toggleStyle(.checkbox)
        }
    }
}
@MainActor private struct RelayLiveAdapter:View {
    @ObservedObject var model:SessionApplicationModel
    @ObservedObject var shell:RelayWindowShell
    @ObservedObject private var setup:SpeechSetupCoordinator
    @ObservedObject private var visual:VisualInputSetupState
    @ObservedObject private var preferences:ResponsePreferencesCoordinator
    @Environment(\.openWindow) private var openWindow
    @State private var startedAt:Double?
    init(model:SessionApplicationModel,shell:RelayWindowShell){self.model=model;self.shell=shell;setup=model.speechSetup;visual=model.visual;preferences=model.responsePreferences}
    private var router:RelayCommandRouter{RelayCommandRouter(state:{model.relayPresentation},control:model.performWindowAction,start:{await model.start()},cancelPreparation:model.cancelPreparation,retryPreparation:{await model.retryPreparation()},openContext:{openWindow(id:"relay-context")},openSettings:{openWindow(id:"relay-settings")},openAISettings:{model.showAISettings{openWindow(id:"relay-settings")}},showSession:{openWindow(id:"relay-live")})}
    var body:some View {
        TimelineView(.periodic(from:.now,by:1)){_ in
            LiveSessionView(state:model.relayPresentation,question:model.snapshot.question,answer:model.relayAnswer,status:model.snapshot.status,contextLabel:model.relayContextLabel,contextDetail:model.relayContextDetail,error:model.error,elapsed:elapsed,fixture:model.fixture,assistant:model.assistant,guideLabel:model.responseGuideName,onResponsePreferences:{model.showResponsePreferences{openWindow(id:"relay-settings")}},attachScroll:{window,scroll in model.attachWindow(window,scrollView:scroll)},expanded:$shell.expanded,detailExpanded:$model.expanded,onAction:{router.perform($0)})
        }
        .background(RelayLiveWindowAttachment(shell:shell,attach:{window in model.attachWindow(window,scrollView:nil)}))
        .onAppear{if model.running{startedAt=ProcessInfo.processInfo.systemUptime}}
        .onChange(of:model.currentSessionID){_,_ in startedAt=model.running ? ProcessInfo.processInfo.systemUptime:nil}
        .onChange(of:model.snapshot.replacement){_,_ in model.expanded=false;if model.snapshot.card != nil{shell.expanded=true}}
        .onChange(of:model.expanded){_,expanded in if expanded{shell.expanded=true}}
        .onChange(of:model.stopping){_,stopping in if !stopping && !model.running && !model.assistantActive && !model.assistantClosing && !model.starting && !model.paused{shell.hideLive();openWindow(id:"relay-home")}}
    }
    private var elapsed:String?{guard model.running,let startedAt else{return nil};let seconds=max(0,Int(ProcessInfo.processInfo.systemUptime-startedAt));return String(format:"%02d:%02d",seconds/60,seconds%60)}
}
@MainActor struct RelayMemoryWorkspace:View {
    @ObservedObject var model:SessionApplicationModel
    @ObservedObject private var use:SessionContextUseCoordinator
    init(model:SessionApplicationModel){self.model=model;use=model.contextUse}
    var body:some View{
        ProfilePreparationView(controller:model.profile,role:model.role,sessionUse:use.snapshot,onOpen:model.openMyContext,onLock:model.lockMyContext)
            .frame(minWidth:760,minHeight:670).preferredColorScheme(.dark).disabled(model.fixture)
    }
}
