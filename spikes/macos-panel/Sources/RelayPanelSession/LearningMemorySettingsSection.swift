import SwiftUI
import RelaySessionPanel

/// Presentation of the existing owned learner. Rendering never restores,
/// enables, opens History or creates persistence by itself.
@MainActor struct LearningMemorySettingsSection:View {
    @ObservedObject var memory:LearningMemoryCoordinator
    let openHistory:@MainActor ()->Void
    @State private var selectedRuleID:String?
    @State private var showExamples=false
    @State private var showReset=false
    @State private var resetTarget:LearningMemoryCoordinator?
    @State private var localMessage:String?

    var body:some View{
        VStack(alignment:.leading,spacing:16){
            HStack{
                Text("Learning Memory").font(.system(size:16,weight:.semibold))
                Spacer()
                if memory.snapshot.isBusy{ProgressView().controlSize(.small)}
            }
            Toggle("Adapt wording and response length",isOn:Binding(
                get:{memory.snapshot.phase == .ready},
                set:{enabled in changeEnabled(enabled)}
            )).toggleStyle(.switch).disabled(memory.snapshot.isBusy)
            Text("Learn tentative preferences from saved meetings and apply them automatically. You can see why, undo a preference or clear what was learned.")
                .font(.system(size:12)).foregroundStyle(RelayTheme.secondary)
            Text("When enabled, saved learning examples include the question, available suggestion, microphone reply and what followed, as text.")
                .font(.system(size:11)).foregroundStyle(RelayTheme.muted)
            Text("New résumé and career facts still need your confirmation. Turning this off clears learned examples and preferences; your saved meetings stay in History.")
                .font(.system(size:11)).foregroundStyle(RelayTheme.muted)
            if memory.snapshot.phase == .ready{
                if memory.snapshot.rules.isEmpty{
                    Text("No preferences yet. Relay looks for repeated patterns across saved meetings before changing its advice.")
                        .font(.system(size:12)).foregroundStyle(RelayTheme.muted)
                }
                ForEach(memory.snapshot.rules){rule in ruleRow(rule)}
                HStack{
                    Text("\(memory.snapshot.episodeCount) saved examples").font(.system(size:11)).foregroundStyle(RelayTheme.muted)
                    Spacer()
                    Button("Reset learned memory…"){
                        resetTarget=memory;showReset=true
                    }.buttonStyle(.plain).font(.system(size:12)).disabled(memory.snapshot.isBusy)
                }
            }else{
                Text(localMessage ?? memory.snapshot.message).font(.system(size:12)).foregroundStyle(RelayTheme.muted)
                Button("Open History",action:openHistory).buttonStyle(RelayQuietButtonStyle())
            }
        }
        .sheet(isPresented:$showExamples){examples}
        .confirmationDialog("Reset learned memory?",isPresented:$showReset){
            Button("Reset learned memory",role:.destructive){
                guard let original=resetTarget,original === memory,memory.snapshot.phase == .ready else{return}
                resetTarget=nil;_ = original.reset()
            }
            Button("Keep memory",role:.cancel){resetTarget=nil}
        }message:{Text("Learned examples and preferences will be cleared. Your saved meetings, personal notes and confirmed résumé stay saved.")}
        .onChange(of:memory.snapshot.phase){_,phase in
            if phase != .ready{showExamples=false;selectedRuleID=nil;showReset=false;resetTarget=nil}
        }
        .onChange(of:ObjectIdentifier(memory)){_,_ in
            showExamples=false;selectedRuleID=nil;showReset=false;resetTarget=nil;localMessage=nil
        }
    }
    private func changeEnabled(_ enabled:Bool){
        localMessage=nil
        if !enabled{_ = memory.disable();return}
        let original=memory
        Task{
            do{try await original.enable()}
            catch{if original === memory{localMessage="Learning could not be enabled. Open History to check saving and access."}}
        }
    }
    private func ruleRow(_ rule:LearningRule)->some View{
        VStack(alignment:.leading,spacing:9){
            HStack{
                Text(rule.label).font(.system(size:13,weight:.medium))
                Text(scopeLabel(rule.scope)).font(.system(size:10)).foregroundStyle(RelayTheme.muted)
                Spacer()
                if rule.suppressed{Text("Undone").font(.system(size:11)).foregroundStyle(RelayTheme.muted)}
                else{Button("Undo"){_ = memory.undo(rule.id)}.font(.system(size:12)).disabled(memory.snapshot.isBusy)}
            }
            Text(rule.suppressed ? "This preference will stay off until you reset learned memory.":"Tentative: based on possible similarities in \(rule.supportIDs.count) replies across \(rule.sessionCount) saved meetings.")
                .font(.system(size:11)).foregroundStyle(RelayTheme.muted)
            if !rule.supportIDs.isEmpty{
                Button("See examples"){
                    selectedRuleID=rule.id;showExamples=true
                }.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(RelayTheme.secondary)
            }
        }.padding(12).background(RelayTheme.raised,in:RoundedRectangle(cornerRadius:10))
    }
    private var examples:some View{
        VStack(alignment:.leading,spacing:16){
            Text("Why this preference?").font(.system(size:20,weight:.semibold))
            Text("These are source examples, not proof that you read a suggestion or that it improved the interview.")
                .font(.system(size:12)).foregroundStyle(RelayTheme.muted)
            if memory.snapshot.phase == .ready,let rule=memory.snapshot.rules.first(where:{$0.id==selectedRuleID}){
                let supporting=Array(memory.retainedEpisodes.filter{rule.supportIDs.contains($0.id)}.prefix(8))
                ScrollView{LazyVStack(alignment:.leading,spacing:18){
                    ForEach(supporting){episode in
                        VStack(alignment:.leading,spacing:10){
                            passage("Question · selected app audio",episode.question.text)
                            passage("Suggestion available",episode.suggestion.text)
                            passage("Reply · microphone",episode.reply.text)
                            passage("What followed · selected app audio",episode.continuation.text)
                        }.padding(14).background(RelayTheme.raised,in:RoundedRectangle(cornerRadius:10))
                    }
                }}
                Text("Showing up to 8 supporting examples. These saved text examples do not confirm new personal facts.")
                    .font(.system(size:11)).foregroundStyle(RelayTheme.muted)
            }else{Text("These examples are no longer available.").font(.system(size:13))}
            HStack{Spacer();Button("Close"){showExamples=false;selectedRuleID=nil}.buttonStyle(RelayQuietButtonStyle())}
        }.padding(28).frame(width:680,height:650).background(RelayTheme.base).foregroundStyle(.white).preferredColorScheme(.dark)
    }
    private func passage(_ label:String,_ value:String)->some View{
        VStack(alignment:.leading,spacing:5){
            Text(label).font(.system(size:11,weight:.medium)).foregroundStyle(RelayTheme.muted)
            Text(GeneratedMeetingNotesSection.visibleQuote(value)).font(.system(size:12)).textSelection(.enabled)
        }
    }
    private func scopeLabel(_ scope:LearningScope)->String{
        switch scope{case .technical:"Technical";case .recruiter:"Background";case .other:"General"}
    }
}
