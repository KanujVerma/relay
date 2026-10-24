import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RelaySessionPanel

/// Constructing and showing this workspace does not read storage or Keychain.
/// Opening, enabling, editing and exporting are explicit user actions.
@MainActor struct RelayHistoryWorkspace:View {
    @ObservedObject var model:SessionApplicationModel
    @ObservedObject private var history:SessionHistoryCoordinator
    @State private var title=""
    @State private var note=""
    @State private var editingID:UUID?
    @State private var editingRevision:Int64=0
    @State private var feedback:String?
    @State private var confirmDelete=false
    @State private var confirmAll=false
    init(model:SessionApplicationModel){
        self.model=model;let coordinator=model.history;history=coordinator
        let record=coordinator.snapshot.selected?.record
        _title=State(initialValue:record?.title ?? "");_note=State(initialValue:record?.note ?? "")
        _editingID=State(initialValue:record?.id);_editingRevision=State(initialValue:record?.revision ?? 0)
    }
    private var snapshot:HistoryWorkspaceSnapshot{history.snapshot}
    var body:some View{
        VStack(spacing:0){
            HStack(spacing:12){
                Image(systemName:"clock.arrow.circlepath");Text("History").font(.system(size:15,weight:.semibold))
                Spacer();Text(history.savingEnabled ? "Saving enabled":"Saving off").font(.system(size:12)).foregroundStyle(RelayTheme.muted)
                if history.isBusy{ProgressView().controlSize(.small)}
                Button("Lock"){clearEditor();history.lock()}.buttonStyle(RelayQuietButtonStyle()).help("Turns saving off and discards unsaved note edits.")
            }.padding(20).background(.white.opacity(0.035))
            Divider().overlay(RelayTheme.line)
            if snapshot.phase == .ready{
                HStack(spacing:0){sessionList.frame(width:272);Divider().overlay(RelayTheme.line);detail.frame(maxWidth:.infinity,maxHeight:.infinity)}
            }else{locked.frame(maxWidth:.infinity,maxHeight:.infinity)}
            Divider().overlay(RelayTheme.line)
            HStack{Text(feedback ?? snapshot.message).font(.system(size:11)).foregroundStyle(RelayTheme.muted).lineLimit(2);Spacer()}.padding(.horizontal,20).frame(minHeight:42)
        }.frame(minWidth:860,minHeight:670).background(RelayTheme.base).foregroundStyle(.white).preferredColorScheme(.dark)
        .onAppear{loadEditor()}
        .onChange(of:snapshot.epoch){_,_ in clearEditor()}
        .onChange(of:snapshot.selected?.record.id){_,_ in loadEditor()}
        .confirmationDialog("Delete this saved session?",isPresented:$confirmDelete){
            Button("Delete session",role:.destructive){if let record=snapshot.selected?.record{clearEditor();perform{try await history.delete(record.id,expectedRevision:record.revision).value}}}
        }message:{Text("Its transcript and notes will be deleted from Relay. Exported copies are unchanged.")}
        .confirmationDialog("Delete all local history?",isPresented:$confirmAll){
            Button("Delete all history",role:.destructive){clearEditor();perform{try await history.deleteAll().value}}
        }message:{Text("Saving will turn off. All saved transcript text and notes will be deleted from Relay. Exported copies are unchanged.")}
    }
    private var locked:some View{
        VStack(alignment:.leading,spacing:18){
            Image(systemName:snapshot.phase == .unavailable ? "exclamationmark.lock":"lock").font(.system(size:32)).foregroundStyle(RelayTheme.muted)
            Text(snapshot.phase == .unavailable ? "History needs attention":"Keep only what you choose.").font(.system(size:26,weight:.semibold))
            Text("Saving is optional and off by default. Enable it while idle to keep audio-session transcript text and your notes on this Mac for 30 days. No raw audio, screenshots or screen text is saved.").font(.system(size:14)).lineSpacing(5).foregroundStyle(RelayTheme.secondary)
            Text("Typed chats and suggested answers are not saved here. Opening saved history never creates a missing vault. History and notes are not approved personal facts.").font(.system(size:12)).foregroundStyle(RelayTheme.muted)
            HStack(spacing:12){
                Button("Open saved history"){perform{try await history.openExisting()}}.buttonStyle(RelayQuietButtonStyle()).disabled(history.isBusy)
                Button("Enable saving"){perform{try await history.enableSaving()}}.buttonStyle(RelayPrimaryButtonStyle()).disabled(!model.canEnableHistory || history.isBusy)
            }
            if history.savingEnabled{Button("Turn saving off"){history.stopSaving()}.buttonStyle(RelayQuietButtonStyle())}
            Text("Lock turns saving off and closes local history. Permission changes do not delete saved history. Expired records are removed the next time history is accessed.").font(.system(size:12)).lineSpacing(4).foregroundStyle(RelayTheme.muted)
        }.frame(maxWidth:560,alignment:.leading).padding(32)
    }
    private var sessionList:some View{
        VStack(alignment:.leading,spacing:12){
            HStack{Text("Saved sessions").font(.system(size:13,weight:.semibold));Spacer();Button{perform{try await history.openExisting()}}label:{Image(systemName:"arrow.clockwise")}.buttonStyle(.plain).disabled(history.isBusy)}
            if snapshot.records.isEmpty{Text("No saved sessions yet.").font(.system(size:13)).foregroundStyle(RelayTheme.muted).padding(.vertical,20)}
            ScrollView{
                LazyVStack(spacing:6){ForEach(snapshot.records){record in
                    Button{perform{try await history.openRecord(record.id);loadEditor()}}label:{
                        VStack(alignment:.leading,spacing:6){Text(record.title).font(.system(size:14,weight:.medium)).lineLimit(2);Text(Date(timeIntervalSince1970:record.createdAt),style:.date).font(.system(size:11)).foregroundStyle(RelayTheme.muted);Text(label(record.state)).font(.system(size:11)).foregroundStyle(record.state == .partial || record.state == .interrupted ? .orange:RelayTheme.muted)}.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(snapshot.selected?.record.id==record.id ? .white.opacity(0.08):.clear,in:RoundedRectangle(cornerRadius:12))
                    }.buttonStyle(.plain).disabled(history.isBusy)
                }
                if snapshot.nextOffset != nil{Button("Load more sessions"){perform{try await history.loadMoreRecords()}}.disabled(history.isBusy)}
                }
            }
            Spacer(minLength:0)
            if history.savingEnabled{Button("Stop saving new text"){history.stopSaving()}.buttonStyle(RelayQuietButtonStyle())}
            else{Button("Enable saving"){perform{try await history.enableSaving()}}.buttonStyle(RelayQuietButtonStyle()).disabled(!model.canEnableHistory || history.isBusy)}
            Button("Delete all…",role:.destructive){confirmAll=true}.font(.system(size:12)).disabled(snapshot.records.isEmpty || snapshot.phase != .ready)
        }.padding(18)
    }
    @ViewBuilder private var detail:some View{
        if let detail=snapshot.selected{
            ScrollView{
                VStack(alignment:.leading,spacing:18){
                    HStack{Text(label(detail.record.state)).font(.system(size:12,weight:.medium)).foregroundStyle(RelayTheme.muted);Spacer();Menu("Export"){Button("Markdown…"){export(detail,format:.markdown)};Button("JSON…"){export(detail,format:.json)}}}.disabled(history.isBusy)
                    TextField("Session title",text:$title).textFieldStyle(.plain).font(.system(size:24,weight:.semibold)).onChange(of:title){_,value in if value.utf8.count>HistoryBounds.title{title=bounded(value,HistoryBounds.title)}}
                    if !detail.record.gaps.isEmpty{Label(detail.record.gaps.map(\.label).joined(separator:". "),systemImage:"exclamationmark.circle").font(.system(size:12)).foregroundStyle(.orange)}
                    Text("Your notes").font(.system(size:14,weight:.semibold))
                    TextEditor(text:$note).font(.system(size:13)).scrollContentBackground(.hidden).frame(minHeight:120).padding(8).background(RelayTheme.raised,in:RoundedRectangle(cornerRadius:10)).onChange(of:note){_,value in if value.utf8.count>HistoryBounds.note{note=bounded(value,HistoryBounds.note)}}
                    HStack{Button("Save notes"){save(detail)}.buttonStyle(RelayQuietButtonStyle()).disabled(history.isBusy || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || (title==detail.record.title && note==detail.record.note));Spacer();Text(title != detail.record.title || note != detail.record.note ? "Unsaved changes · Lock discards edits":"User notes · not personal facts").font(.system(size:11)).foregroundStyle(RelayTheme.muted)}
                    Divider().overlay(RelayTheme.line)
                    HStack{Text("Transcript").font(.system(size:15,weight:.semibold));Spacer();Text("\(detail.rows.count) of \(detail.totalRows) final passages").font(.system(size:11)).foregroundStyle(RelayTheme.muted)}
                    if detail.rows.isEmpty{Text("No final transcript text was saved.").font(.system(size:13)).foregroundStyle(RelayTheme.muted)}
                    ForEach(detail.rows){row in VStack(alignment:.leading,spacing:6){Text(row.source.label).font(.system(size:11,weight:.semibold)).foregroundStyle(RelayTheme.muted);Text(row.text).font(.system(size:13)).lineSpacing(5).textSelection(.enabled)}.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,8)}
                    if detail.nextOffset != nil{Button("Load more transcript"){perform{try await history.loadMoreTranscript()}}.buttonStyle(RelayQuietButtonStyle()).disabled(history.isBusy)}
                    Divider().overlay(RelayTheme.line)
                    ForEach(detail.captures){capture in
                        VStack(alignment:.leading,spacing:6){
                            Text("Audio segment · "+Date(timeIntervalSince1970:capture.observedWallTime).formatted(date:.abbreviated,time:.shortened)).font(.system(size:12)).foregroundStyle(RelayTheme.muted)
                            Text(capture.observedEndUptimeNanoseconds == nil ? "Capture cleanup end not recorded":"Capture cleanup observed · original native receipt").font(.system(size:11)).foregroundStyle(RelayTheme.muted)
                            HStack{ForEach([TranscriptSource.microphone,.selectedAppAudio],id:\.rawValue){source in if detail.rows.contains(where:{$0.captureSessionID==capture.captureSessionID && $0.source==source}){Button("Delete "+source.label){perform{try await history.deleteSource(detail.record.id,expectedRevision:detail.record.revision,captureID:capture.id,source:source).value;loadEditor()}}.font(.system(size:11)).buttonStyle(.plain).foregroundStyle(.orange)}}}
                        }
                    }
                    Button("Delete session…",role:.destructive){confirmDelete=true}.font(.system(size:12)).padding(.top,12)
                }.padding(28)
            }
        }else{VStack(spacing:12){Image(systemName:"text.alignleft").font(.system(size:28));Text("Choose a saved session");Text("Transcript text and your notes stay separate from My Context.").font(.system(size:12))}.foregroundStyle(RelayTheme.muted).padding(28)}
    }
    private func save(_ detail:HistoryDetail){
        let id=detail.record.id,revision=editingRevision,draftTitle=title,draftNote=note
        perform{try await history.saveNotes(id,expectedRevision:revision,title:draftTitle,note:draftNote);loadEditor()}
    }
    private func export(_ detail:HistoryDetail,format:HistoryExportFormat){
        let panel=NSSavePanel();panel.title="Export session history";panel.message="This creates an unencrypted readable file. Relay's Lock, deletion and 30-day retention do not remove exported copies.";panel.nameFieldStringValue="Relay session."+(format == .json ? "json":"md");panel.allowedContentTypes=[format == .json ? .json:.plainText]
        guard panel.runModal() == .OK,let url=panel.url else{return}
        perform{try await history.export(detail.record.id,expectedRevision:detail.record.revision,format:format,to:HistoryFileExportDestination(url:url)).value}
    }
    private func perform(_ operation:@escaping @MainActor ()async throws->Void){feedback=nil;let original=snapshot.epoch;Task{do{try await operation()}catch{if snapshot.epoch==original{feedback="That action could not finish. Reopen the session before retrying if its contents changed."}}}}
    private func loadEditor(){guard let record=snapshot.selected?.record else{clearEditor();return};editingID=record.id;editingRevision=record.revision;title=record.title;note=record.note}
    private func clearEditor(){title="";note="";editingID=nil;editingRevision=0;feedback=nil}
    private func bounded(_ value:String,_ limit:Int)->String{var result="",size=0;for scalar in value.unicodeScalars{let n=scalar.utf8.count;guard size+n<=limit else{break};result.unicodeScalars.append(scalar);size+=n};return result}
    private func label(_ state:HistoryRecordState)->String{switch state{case .recording:"In progress";case .paused:"Paused";case .completed:"Completed";case .partial:"Partial transcript";case .interrupted:"Interrupted"}}
}
