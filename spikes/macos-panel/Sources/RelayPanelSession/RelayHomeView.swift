import SwiftUI
import RelaySessionPanel

/// Side-effect-free Home surface; source controls and commands come from the owner adapter.
struct RelayHomeView<SourceControls:View>:View {
    let state:RelaySessionPresentation
    let preparation:RelayPreparationPresentation?
    let aiEnabled:Bool
    let error:String?
    var fixture=false
    var assistant:TypedAssistantController?
    var openHistory:(()->Void)?
    var guideLabel:String?
    var onResponsePreferences:(()->Void)?
    let onAction:(RelayUIAction)->Void
    @ViewBuilder let sourceControls:()->SourceControls
    private var offersChatGPTSetup:Bool{!aiEnabled && !fixture}
    private var headline:String {
        state.stopping ? "Finishing the session…":state.paused ? "Take your time.":state.running ? "Your session is live.":state.visualBusy ? "Updating image settings…":offersChatGPTSetup ? "Connect ChatGPT for live answers.":"Ready when you are."
    }
    var body:some View {
        HStack(spacing:0){
            VStack(alignment:.leading,spacing:assistant == nil ? 24:16){
                RelayBrand().padding(.bottom,12)
                Label("Session",systemImage:"waveform").font(.system(size:13,weight:.medium)).frame(maxWidth:.infinity,alignment:.leading).padding(10).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
                Button{onAction(.context)}label:{Label("My Context",systemImage:"person.text.rectangle").frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).font(.system(size:13)).foregroundStyle(RelayTheme.secondary).padding(.horizontal,10).disabled(fixture)
                if let openHistory{Button(action:openHistory){Label("History",systemImage:"clock.arrow.circlepath").frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).font(.system(size:13)).foregroundStyle(RelayTheme.secondary).padding(.horizontal,10)}
                Spacer()
                Button{onAction(.settings)}label:{Label("Settings",systemImage:"gearshape").frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).font(.system(size:13)).foregroundStyle(RelayTheme.secondary).padding(.horizontal,10)
            }.padding(20).frame(width:188).background(.white.opacity(0.02))
            Rectangle().fill(RelayTheme.line).frame(width:1)
            VStack(alignment:.leading,spacing:24){
                HStack{Text("SESSION").font(.system(size:11,weight:.semibold)).tracking(1.5).foregroundStyle(RelayTheme.muted);Spacer();Label(aiEnabled ? "AI suggestions":"Local reference cards",systemImage:aiEnabled ? "sparkles":"book.closed").font(.system(size:11)).foregroundStyle(RelayTheme.muted)}
                Spacer(minLength:0)
                VStack(alignment:.leading,spacing:12){
                    Text(headline).font(.system(size:30,weight:.semibold)).tracking(-0.7)
                    if offersChatGPTSetup {
                        HStack(spacing:16){
                            Text("Use your ChatGPT plan, or continue with limited local reference cards.").font(.system(size:14)).lineSpacing(5).foregroundStyle(RelayTheme.secondary).fixedSize(horizontal:false,vertical:true)
                            Button("Connect ChatGPT"){onAction(.connectChatGPT)}.buttonStyle(RelayPrimaryButtonStyle()).fixedSize()
                        }
                    }else{
                        Text("Listen to the conversation. Get clear talking points, with your own experience close at hand.").font(.system(size:14)).lineSpacing(5).foregroundStyle(RelayTheme.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                }
                if let assistant{
                    VStack(alignment:.leading,spacing:8){
                        HStack{
                            Text("Ask Relay").font(.system(size:15,weight:.semibold));Spacer()
                            if let guideLabel,let onResponsePreferences{ResponseGuideButton(name:guideLabel,action:onResponsePreferences)}
                            if state.assistantActive{Button("Open assistant"){onAction(.showSession)}.buttonStyle(.plain).font(.system(size:12)).foregroundStyle(RelayTheme.secondary)}
                        }
                        Text("Ask a question without starting audio recording.").font(.system(size:12)).foregroundStyle(RelayTheme.muted)
                        AssistantComposerView(assistant:assistant)
                    }.padding(16).background(RelayTheme.raised,in:RoundedRectangle(cornerRadius:16)).overlay{RoundedRectangle(cornerRadius:16).strokeBorder(RelayTheme.line)}
                }
                VStack(alignment:.leading,spacing:16){
                    sourceControls()
                    if let preparation{PreparationStatusView(presentation:preparation,canRetry:state.allows(.retryPreparation),showRecoveryActions:false,onAction:onAction)}
                    else{Text("Speech is prepared automatically on first use. About 225 MB is downloaded once.").font(.system(size:12)).foregroundStyle(RelayTheme.muted)}
                    if let error{Label(error,systemImage:"exclamationmark.circle").font(.system(size:12)).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)}
                    HStack(spacing:12){
                        if state.stopping || state.running {
                            Button("Show session"){onAction(.showSession)}.buttonStyle(RelayPrimaryButtonStyle())
                        }else if state.preparing || state.starting {
                            Button(state.cancellingPreparation ? "Finishing…":"Cancel preparation"){onAction(.cancelPreparation)}.buttonStyle(RelayQuietButtonStyle()).disabled(!state.allows(.cancelPreparation))
                        }else if state.paused{
                            Button("Resume session"){onAction(.resume)}.buttonStyle(RelayPrimaryButtonStyle()).disabled(!state.allows(.resume))
                        }else if state.visualBusy{
                            Text("Finish image setup in Settings before starting.").font(.system(size:12)).foregroundStyle(RelayTheme.muted)
                        }else if preparation?.recovery == .retry{
                            Button("Try again"){onAction(.retryPreparation)}.buttonStyle(RelayPrimaryButtonStyle()).disabled(!state.allows(.retryPreparation))
                        }else if preparation?.recovery == .openSettings{
                            Button("Open Settings"){onAction(.settings)}.buttonStyle(RelayPrimaryButtonStyle())
                        }else{
                            Button{onAction(.start)}label:{HStack(spacing:8){Image(systemName:"play.fill");Text("Start session")}}.buttonStyle(RelayPrimaryButtonStyle()).disabled(!state.allows(.start))
                        }
                        Spacer()
                        Button("Add résumé or context"){onAction(.context)}.buttonStyle(RelayQuietButtonStyle()).disabled(fixture)
                    }
                }.padding(20).background(RelayTheme.raised,in:RoundedRectangle(cornerRadius:16)).overlay{RoundedRectangle(cornerRadius:16).strokeBorder(RelayTheme.line)}
                Text(state.hasRemoteSource ? "Suggestions appear automatically as questions develop.":"Choose a conversation app for automatic question help. Your microphone adds reply context.").font(.system(size:12)).foregroundStyle(RelayTheme.muted)
                Spacer(minLength:0)
                if fixture{Text("SYNTHETIC DEMO · no audio capture or account request").font(.system(size:10,weight:.medium)).foregroundStyle(RelayTheme.muted)}
            }.padding(36).frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(width:920,height:assistant == nil ? 670:790).background(RelayTheme.base).foregroundStyle(.white).preferredColorScheme(.dark)
    }
}
struct PreparationStatusView:View {
    let presentation:RelayPreparationPresentation
    var canRetry=true
    var showRecoveryActions=true
    let onAction:(RelayUIAction)->Void
    var body:some View {
        VStack(alignment:.leading,spacing:8){
            HStack{Text(presentation.title).font(.system(size:13,weight:.medium));Spacer();if let fraction=presentation.fraction{Text(fraction,format:.percent.precision(.fractionLength(0))).monospacedDigit().foregroundStyle(RelayTheme.muted)}}
            if presentation.busy{if let fraction=presentation.fraction{ProgressView(value:fraction).tint(RelayTheme.live)}else{ProgressView().controlSize(.small)}}
            if let detail=presentation.detail{Text(detail).font(.system(size:12)).foregroundStyle(RelayTheme.muted)}
            if showRecoveryActions && presentation.recovery == .retry{Button("Try again"){onAction(.retryPreparation)}.buttonStyle(RelayQuietButtonStyle()).disabled(presentation.busy || !canRetry)}
            if showRecoveryActions && presentation.recovery == .openSettings{Button("Open Settings"){onAction(.settings)}.buttonStyle(RelayQuietButtonStyle())}
        }.accessibilityElement(children:.contain)
    }
}
