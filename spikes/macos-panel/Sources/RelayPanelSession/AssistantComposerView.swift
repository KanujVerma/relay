import SwiftUI
import RelaySessionPanel

@MainActor struct AssistantComposerView:View {
    @ObservedObject var assistant:TypedAssistantController
    var body:some View {
        VStack(alignment:.leading,spacing:9){
            if assistant.snapshot.transcriptVisible{SessionTranscriptView(store:assistant.transcript)}
            if let basis=assistant.snapshot.basis,!assistant.draft.isEmpty {
                HStack(alignment:.top,spacing:8){
                    Image(systemName:"arrow.turn.down.right")
                    Text("Following up: "+basis.question).lineLimit(2)
                    Spacer(minLength:0)
                    Button("Use latest"){assistant.useLatestQuestionForDraft()}.buttonStyle(.plain).disabled(!assistant.snapshot.canHelpCurrent)
                }.font(.system(size:11)).foregroundStyle(RelayTheme.muted)
            }
            if assistant.snapshot.basisState == .unavailable {
                HStack{
                    Text("The original context is unavailable.").font(.system(size:11)).foregroundStyle(.orange)
                    Spacer()
                    Button("Send as new question"){assistant.sendDraftAsNewQuestion()}.font(.system(size:11)).buttonStyle(.plain).disabled(!assistant.snapshot.canSendAsNew)
                }
            }
            HStack(alignment:.bottom,spacing:10){
                TextField("Ask a question or add a follow-up…",text:$assistant.draft,axis:.vertical)
                    .font(.system(size:13)).textFieldStyle(.plain).lineLimit(1...3)
                    .onSubmit{assistant.submitDraft()}.accessibilityLabel("Question or follow-up")
                Button{assistant.submitDraft()}label:{Image(systemName:"arrow.up").font(.system(size:13,weight:.semibold)).frame(width:28,height:28)}
                    .buttonStyle(.plain).background(.white.opacity(assistant.snapshot.canSend ? 0.17:0.045),in:Circle())
                    .disabled(!assistant.snapshot.canSend).accessibilityLabel("Send question")
            }.padding(11).background(.black.opacity(0.2),in:RoundedRectangle(cornerRadius:12))
            HStack{
                Button{assistant.setTranscriptVisible(!assistant.snapshot.transcriptVisible)}label:{Label(assistant.snapshot.transcriptVisible ? "Hide transcript":"Transcript",systemImage:"text.alignleft")}.buttonStyle(.plain)
                Spacer()
                if assistant.snapshot.canStop {
                    Button{Task{await assistant.cancelCurrentResponse()}}label:{Label("Stop response",systemImage:"stop.fill")}.buttonStyle(.plain)
                }else if !assistant.snapshot.status.isEmpty{Text(assistant.snapshot.status).lineLimit(1)}
            }.font(.system(size:11)).foregroundStyle(RelayTheme.muted)
        }.padding(.horizontal,14).padding(.vertical,11)
    }
}

@MainActor private struct SessionTranscriptView:View {
    @ObservedObject var store:SessionTranscriptStore
    var body:some View {
        ScrollView{
            VStack(alignment:.leading,spacing:12){
                if store.snapshot.omittedRowCount>0{Text("Earlier conversation is no longer shown.").font(.system(size:10)).foregroundStyle(RelayTheme.muted)}
                if store.snapshot.rows.isEmpty{Text("Recognized speech appears here during the session.").foregroundStyle(RelayTheme.muted)}
                ForEach(store.snapshot.rows){row in
                    VStack(alignment:.leading,spacing:4){
                        Text(row.source.label).font(.system(size:10,weight:.medium)).foregroundStyle(RelayTheme.muted)
                        Text(row.text).font(.system(size:12)).textSelection(.enabled)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(10)
        }.frame(maxHeight:150).background(.black.opacity(0.14),in:RoundedRectangle(cornerRadius:10))
            .accessibilityLabel("Current session transcript")
    }
}
