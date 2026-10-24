import Foundation
import SwiftUI
import RelaySessionPanel

/// Presentation only. Every action carries the original displayed target;
/// the actual model/controller rechecks ownership and CAS before any effect.
@MainActor struct GeneratedMeetingNotesSection:View {
    let snapshot:GeneratedMeetingNotesSnapshot
    let generate:(GeneratedMeetingNotesSnapshot,HistoryNotesSelection)->Void
    let cancel:(GeneratedMeetingNotesSnapshot)->Void
    let showCitation:(GeneratedMeetingNotesSnapshot,HistoryNotesCitationData)->Void
    let saveEdits:@MainActor @Sendable (GeneratedMeetingNotesSnapshot,HistoryNotesEditedTexts) async throws->Void
    let deleteGenerated:(GeneratedMeetingNotesSnapshot)->Void
    var availableRows:[HistoryFinal]=[]
    @ObservedObject var draft:GeneratedMeetingNotesDraft
    @State private var showEditor=false
    @State private var deleteTarget:GeneratedMeetingNotesSnapshot?
    @State private var confirmDelete=false
    @State private var excerptTarget:GeneratedMeetingNotesSnapshot?
    @State private var excerptRows:[HistoryFinal]=[]
    @State private var firstRowID=""
    @State private var lastRowID=""
    @State private var showExcerpt=false
    @State private var blockedEditTarget:GeneratedMeetingNotesSnapshot?
    @State private var showKeptDraft=false

    private var busy:Bool{[.preparing,.generating,.saving,.cancelling].contains(snapshot.phase)}
    private var anchored:Bool{snapshot.workspaceEpoch != nil && snapshot.recordID != nil && snapshot.recordRevision != nil}
    private var editStillVisible:Bool{
        guard let target=draft.snapshot.target else{return false}
        return target.workspaceEpoch==snapshot.workspaceEpoch && target.recordID==snapshot.recordID
            && target.document?.noteID==snapshot.document?.noteID && snapshot.document != nil
    }
    var body:some View{
        VStack(alignment:.leading,spacing:14){
            HStack(spacing:10){
                Image(systemName:"sparkles").foregroundStyle(RelayTheme.secondary)
                Text("Meeting notes").font(.system(size:15,weight:.semibold))
                Text(snapshot.document?.origin == "generated_user_edited" ? "Edited locally":"AI-generated")
                    .font(.system(size:10,weight:.medium)).foregroundStyle(RelayTheme.muted)
                    .padding(.horizontal,8).padding(.vertical,4).background(.white.opacity(0.06),in:Capsule())
                Spacer()
                if busy{ProgressView().controlSize(.small)}
                if snapshot.canCancel,snapshot.operationID != nil{
                    Button("Stop"){cancel(snapshot)}.buttonStyle(RelayQuietButtonStyle())
                }
            }
            if let document=snapshot.document{
                Text(scopeLabel(document.selection)).font(.system(size:11)).foregroundStyle(RelayTheme.muted)
                if !document.sourceGaps.isEmpty || ["partial","interrupted"].contains(document.sourceState){
                    Label("Some meeting text was missing when these notes were generated.",systemImage:"exclamationmark.circle")
                        .font(.system(size:12)).foregroundStyle(.orange)
                }
                items("Summary",document.notes.summary)
                items("Decisions",document.notes.decisions)
                items("Next steps",document.notes.nextSteps)
                HStack(spacing:12){
                    if snapshot.canEdit,anchored{Button("Edit wording"){beginEditing()}.buttonStyle(RelayQuietButtonStyle()).disabled(busy)}
                    if snapshot.canGenerate,anchored{regenerate.disabled(busy)}
                    Spacer()
                    if snapshot.canDelete,anchored{
                        Button("Delete AI notes…",role:.destructive){deleteTarget=snapshot;confirmDelete=true}.font(.system(size:12)).disabled(busy)
                    }
                }
            }else{
                Text("A summary, decisions and next steps from this saved meeting.")
                    .font(.system(size:13)).lineSpacing(4).foregroundStyle(RelayTheme.secondary)
                HStack(spacing:12){
                    Button(busy ? phaseLabel:"Generate notes"){generate(snapshot,.fullSavedTranscript)}
                        .buttonStyle(RelayQuietButtonStyle()).disabled(busy || !snapshot.canGenerate || !anchored)
                    if !availableRows.isEmpty{
                        Button("Choose passages…"){beginExcerpt()}.buttonStyle(.plain)
                            .disabled(busy || !snapshot.canGenerate || !anchored)
                    }
                }
            }
            if let message=snapshot.message,!message.isEmpty{
                Text(message).font(.system(size:12)).foregroundStyle(snapshot.phase == .unavailable ? .orange:RelayTheme.muted).textSelection(.enabled)
            }else if busy{Text(phaseLabel).font(.system(size:12)).foregroundStyle(RelayTheme.muted)}
        }
        .sheet(isPresented:$showEditor){editor}
        .sheet(isPresented:$showExcerpt,onDismiss:clearExcerpt){excerptPicker}
        .confirmationDialog("Delete these AI notes?",isPresented:$confirmDelete){
            Button("Delete AI notes",role:.destructive){if let original=deleteTarget{deleteTarget=nil;deleteGenerated(original)}}
            Button("Keep notes",role:.cancel){deleteTarget=nil}
        }message:{Text("Your transcript and personal notes stay saved.")}
        .confirmationDialog("You have unsaved meeting notes",isPresented:$showKeptDraft){
            Button("Keep draft",role:.cancel){blockedEditTarget=nil}
            if !draft.snapshot.isSaving{
                Button("Discard draft and edit these notes",role:.destructive){
                    let original=blockedEditTarget;blockedEditTarget=nil;draft.discard()
                    if let original,draft.prepareEditor(original){showEditor=true}
                }
            }
        }message:{Text(draft.snapshot.isSaving ? "A save is still finishing. Wait before opening a different note.":"Your existing wording is kept. Discard it only if you want to edit a different note.")}
        .onChange(of:snapshot.workspaceEpoch){_,_ in retirePresentation()}
        .onChange(of:snapshot.recordID){_,_ in retirePresentation()}
        .onChange(of:snapshot.recordRevision){_,_ in showExcerpt=false;clearExcerpt()}
        .onChange(of:snapshot.document?.noteID){old,new in if old != new{showEditor=false;deleteTarget=nil;confirmDelete=false}}
    }
    private var regenerate:some View{
        Menu("Regenerate"){
            Button("Full saved transcript"){generate(snapshot,.fullSavedTranscript)}
            if case .excerpt=snapshot.selection{Button("Selected passages"){generate(snapshot,snapshot.selection)}}
            if !availableRows.isEmpty{Button("Choose passages…"){beginExcerpt()}}
        }.menuStyle(.borderlessButton).fixedSize()
    }
    private func beginExcerpt(){
        excerptTarget=snapshot;excerptRows=Array(availableRows.prefix(1024))
        firstRowID=excerptRows.first?.id ?? "";lastRowID=excerptRows.last?.id ?? "";showExcerpt=true
    }
    private func clearExcerpt(){excerptTarget=nil;excerptRows=[];firstRowID="";lastRowID=""}
    private func retirePresentation(){
        showEditor=false;deleteTarget=nil;confirmDelete=false;showExcerpt=false;clearExcerpt();blockedEditTarget=nil;showKeptDraft=false
    }
    private var selectedExcerpt:HistoryNotesSelection?{
        guard let first=excerptRows.firstIndex(where:{$0.id==firstRowID}),
              let last=excerptRows.firstIndex(where:{$0.id==lastRowID}),first<=last else{return nil}
        return .excerpt(firstRowID:firstRowID,lastRowID:lastRowID)
    }
    private var excerptPicker:some View{
        VStack(alignment:.leading,spacing:18){
            Text("Choose meeting passages").font(.system(size:20,weight:.semibold))
            Text("Notes will cover every saved passage between these two. To extend the range, load more passages in the transcript first.")
                .font(.system(size:12)).foregroundStyle(RelayTheme.muted)
            Picker("Start with",selection:$firstRowID){ForEach(excerptRows){row in Text(rowLabel(row)).tag(row.id)}}
            Picker("End with",selection:$lastRowID){ForEach(excerptRows){row in Text(rowLabel(row)).tag(row.id)}}
            if selectedExcerpt==nil{Text("Choose an end passage after the start.").font(.system(size:12)).foregroundStyle(.orange)}
            HStack{
                Button("Cancel"){showExcerpt=false}.buttonStyle(RelayQuietButtonStyle())
                Spacer()
                Button("Generate from these passages"){
                    guard let original=excerptTarget,let selection=selectedExcerpt else{return}
                    showExcerpt=false;generate(original,selection)
                }.buttonStyle(RelayQuietButtonStyle()).disabled(selectedExcerpt==nil || busy || !snapshot.canGenerate)
            }
        }.padding(28).frame(width:620).background(RelayTheme.base).foregroundStyle(.white).preferredColorScheme(.dark)
    }
    private func rowLabel(_ row:HistoryFinal)->String{
        let source=row.source == .microphone ? "Microphone":"Selected app audio"
        return source+": "+String(Self.visibleQuote(row.text).replacingOccurrences(of:"\n",with:" ").prefix(90))
    }
    @ViewBuilder private func items(_ title:String,_ values:[HistoryNotesItemData])->some View{
        if !values.isEmpty{
            VStack(alignment:.leading,spacing:10){
                Text(title).font(.system(size:12,weight:.semibold)).foregroundStyle(RelayTheme.secondary)
                ForEach(Array(values.enumerated()),id:\.offset){_,item in
                    VStack(alignment:.leading,spacing:8){
                        Text(item.text).font(.system(size:13)).lineSpacing(4).textSelection(.enabled)
                        ForEach(Array(item.citations.enumerated()),id:\.offset){index,citation in
                            Button{showCitation(snapshot,citation)}label:{
                                HStack(alignment:.top,spacing:7){
                                    Image(systemName:"quote.bubble").font(.system(size:11))
                                    Text(Self.visibleQuote(citation.quote)).font(.system(size:11)).lineLimit(3).multilineTextAlignment(.leading)
                                }.foregroundStyle(RelayTheme.muted)
                            }.buttonStyle(.plain).help("Show the original passage")
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(12)
                        .background(RelayTheme.raised,in:RoundedRectangle(cornerRadius:10))
                }
            }
        }
    }
    @ViewBuilder private var editor:some View{
        if editStillVisible,let original=draft.snapshot.target{
            VStack(alignment:.leading,spacing:18){
                Text("Edit meeting notes").font(.system(size:20,weight:.semibold))
                Text("Edit the wording. Original source references stay linked.").font(.system(size:12)).foregroundStyle(RelayTheme.muted)
                if original.recordRevision != snapshot.recordRevision || original.document?.noteRevision != snapshot.document?.noteRevision{
                    Text("Saved notes changed while this draft was open. Your wording is kept; save checks the original version.").font(.system(size:12)).foregroundStyle(.orange)
                }
                ScrollView{VStack(alignment:.leading,spacing:16){editGroup("Summary",group:0,count:draft.snapshot.summary.count);editGroup("Decisions",group:1,count:draft.snapshot.decisions.count);editGroup("Next steps",group:2,count:draft.snapshot.nextSteps.count)}}
                if let editMessage=draft.snapshot.message{Text(editMessage).font(.system(size:12)).foregroundStyle(.orange)}
                HStack{
                    Button("Close"){showEditor=false}.buttonStyle(RelayQuietButtonStyle())
                    if draft.snapshot.isDirty{Button("Discard edits"){draft.discard();showEditor=false}.buttonStyle(.plain).disabled(draft.snapshot.isSaving)}
                    Spacer()
                    Button(draft.snapshot.isSaving ? "Saving…":"Save wording"){
                        Task{do{try await draft.save(using:saveEdits);showEditor=false}catch{}}
                    }.buttonStyle(RelayQuietButtonStyle()).disabled(!snapshot.canEdit || busy || draft.snapshot.isSaving || !draft.snapshot.isDirty)
                }
            }.padding(28).frame(minWidth:620,minHeight:500).background(RelayTheme.base).foregroundStyle(.white).preferredColorScheme(.dark)
        }else{VStack(spacing:12){Text("Reopen the original notes to continue editing.");Text("Your draft is kept until you save or discard it.").font(.system(size:12));Button("Close"){showEditor=false}}.padding(28)}
    }
    @ViewBuilder private func editGroup(_ title:String,group:Int,count:Int)->some View{
        if count>0{
            Text(title).font(.system(size:13,weight:.semibold))
            ForEach(0..<count,id:\.self){index in
                TextEditor(text:Binding(get:{text(group,index)},set:{setText($0,group,index)})).font(.system(size:13))
                    .scrollContentBackground(.hidden).frame(minHeight:70).padding(8)
                    .background(RelayTheme.raised,in:RoundedRectangle(cornerRadius:8)).disabled(draft.snapshot.isSaving)
            }
        }
    }
    private func beginEditing(){
        if draft.prepareEditor(snapshot){showEditor=true}
        else{blockedEditTarget=snapshot;showKeptDraft=true}
    }
    private func text(_ group:Int,_ index:Int)->String{
        let values=group==0 ? draft.snapshot.summary:group==1 ? draft.snapshot.decisions:draft.snapshot.nextSteps
        return values.indices.contains(index) ? values[index]:""
    }
    private func setText(_ value:String,_ group:Int,_ index:Int){draft.edit(value,group:group,index:index)}
    private func scopeLabel(_ selection:HistoryNotesSelectionData)->String{
        selection.kind=="explicit_excerpt" ? "Selected passages · \(selection.includedRows) of \(selection.totalSavedRows)":"Full saved transcript · \(selection.includedRows) \(selection.includedRows==1 ? "passage":"passages")"
    }
    private var phaseLabel:String{
        switch snapshot.phase{case .preparing:"Preparing saved text…";case .generating:"Writing notes…";case .saving:"Saving notes…";case .cancelling:"Stopping…";default:""}
    }
    /// Display escaping never changes the original citation delivered to Model.
    static func visibleQuote(_ value:String)->String{
        value.unicodeScalars.map{scalar in
            switch scalar.properties.generalCategory{
            case .control,.format,.lineSeparator,.paragraphSeparator,.surrogate:
                return scalar=="\n" || scalar=="\t" ? String(scalar):"\\u{\(String(scalar.value,radix:16))}"
            default:return String(scalar)
            }
        }.joined()
    }
}
