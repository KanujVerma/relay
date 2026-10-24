import Foundation
import SwiftUI
import RelayProfile

struct ResponseGuideEditorState:Equatable {
    var id=UUID(),name="",focus:ResponseGuideFocus = .automatic,guidance=""
    var catalogRevision:UUID?
    init(catalogRevision:UUID?=nil){self.catalogRevision=catalogRevision}
    init(guide:ResponseGuide,catalogRevision:UUID){id=guide.id;name=guide.name;focus=guide.focus;guidance=guide.guidance;self.catalogRevision=catalogRevision}
    func validatedGuide()throws->ResponseGuide{try ResponseGuide(id:id,name:name,focus:focus,guidance:guidance)}
    mutating func applySaveReceipt(submitted:Self,revision:UUID)->Bool{
        guard id==submitted.id,catalogRevision==submitted.catalogRevision else{return false}
        // Acknowledge this same draft's actual earlier save, never replace or
        // merge newer text and never submit it without another explicit Save.
        catalogRevision=revision;return true
    }
}

@MainActor struct ResponsePreferencesSettingsView:View {
    @ObservedObject var model:SessionApplicationModel
    @ObservedObject private var preferences:ResponsePreferencesCoordinator
    @State private var editor=ResponseGuideEditorState()
    @State private var actionID=UUID()
    @State private var actionBusy=false
    @State private var error:String?
    @Environment(\.openWindow) private var openWindow
    init(model:SessionApplicationModel){self.model=model;preferences=model.responsePreferences}
    private var busy:Bool{actionBusy || preferences.snapshot.isBusy}
    private var guides:[ResponseGuide]{preferences.catalog?.guides ?? []}
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            Text("Response guides").font(.system(size:18,weight:.semibold))
            Text("General follows the question automatically. Optional guides shape generated replies; saved facts keep their original sources.").font(.system(size:13)).foregroundStyle(RelayTheme.secondary)
            HStack{Text("Current: "+preferences.snapshot.guideName).font(.system(size:13,weight:.medium));Spacer();if busy{ProgressView().controlSize(.small)}}
            Text(preferences.snapshot.message).font(.system(size:12)).foregroundStyle(RelayTheme.muted)
            if !model.oauth{Text("AI suggestions are off. Your guide is saved for when you enable them.").font(.system(size:12)).foregroundStyle(RelayTheme.muted)}
            HStack(spacing:10){
                Button("Use General"){actionID=UUID();actionBusy=false;error=nil;preferences.useGeneral()}.buttonStyle(RelayQuietButtonStyle())
                Button("Use Coding"){run{try await preferences.useBuiltin(.coding)}}.buttonStyle(RelayQuietButtonStyle()).disabled(busy)
                Button("Use Feature discussion"){run{try await preferences.useBuiltin(.feature)}}.buttonStyle(RelayQuietButtonStyle()).disabled(busy)
            }
            if !guides.isEmpty{
                VStack(spacing:10){ForEach(guides){guide in
                    HStack{Text(guide.name).font(.system(size:13));Spacer()
                        Button("Use"){let revision=preferences.catalog?.revision;run{try await preferences.saveAndUse(guide,expectedCatalogRevision:revision)}}
                        Button("Edit"){if let revision=preferences.catalog?.revision{editor=ResponseGuideEditorState(guide:guide,catalogRevision:revision);error=nil}}
                        Button("Delete"){delete(guide)}
                    }.disabled(busy)
                }}
            }
            HStack{Button("New guide"){editor=ResponseGuideEditorState(catalogRevision:preferences.catalog?.revision);error=nil}.disabled(busy || guides.count>=8)
                Button("Reload guides"){load()}.disabled(busy);Spacer();Button("My Context"){openWindow(id:"relay-context")}}
            Divider().overlay(RelayTheme.line)
            Text("Custom guidance").font(.system(size:15,weight:.medium))
            TextField("Guide name",text:$editor.name)
            Picker("Focus",selection:$editor.focus){Text("Automatic").tag(ResponseGuideFocus.automatic);Text("Coding discussion").tag(ResponseGuideFocus.coding);Text("Feature discussion").tag(ResponseGuideFocus.feature)}
            TextEditor(text:$editor.guidance).font(.system(size:13)).frame(minHeight:110,maxHeight:150).scrollContentBackground(.hidden).padding(8).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
            HStack{Text("\(editor.name.utf8.count)/64 name bytes · \(editor.guidance.utf8.count)/2,048 guidance bytes").font(.system(size:11)).foregroundStyle(RelayTheme.muted);Spacer()}
            Text("Changing or removing a guide stops responses using it. Ask again to use the new guide. Files and personal background belong in My Context.").font(.system(size:12)).foregroundStyle(RelayTheme.muted)
            HStack{Button("Save and use"){save()}.buttonStyle(RelayQuietButtonStyle()).disabled(busy || (try? editor.validatedGuide())==nil)
                Button("Cancel editing"){actionID=UUID();actionBusy=false;preferences.cancel();editor=ResponseGuideEditorState(catalogRevision:preferences.catalog?.revision);error=nil}}
            if let error{Text(error).font(.system(size:12)).foregroundStyle(.orange)}
        }.task{if !model.fixture{load()}}
    }
    private func run(_ operation:@escaping @MainActor ()async throws->Void){
        let id=UUID();actionID=id;actionBusy=true;error=nil
        Task{@MainActor in
            do{try await operation()}catch{if actionID==id{self.error=(error as? LocalizedError)?.errorDescription ?? "Response preferences could not be updated."}}
            if actionID==id{actionBusy=false}
        }
    }
    private func load(){
        let editorID=editor.id
        run{
            try await preferences.open()
            if editor.id==editorID{editor.catalogRevision=preferences.catalog?.revision}
        }
    }
    private func save(){
        let submitted=editor
        do{
            let guide=try submitted.validatedGuide()
            run{
                try await preferences.saveAndUse(guide,expectedCatalogRevision:submitted.catalogRevision)
                if let revision=preferences.catalog?.revision{_ = editor.applySaveReceipt(submitted:submitted,revision:revision)}
            }
        }catch{self.error=(error as? LocalizedError)?.errorDescription ?? "Check the guide name and guidance."}
    }
    private func delete(_ guide:ResponseGuide){
        guard let revision=preferences.catalog?.revision else{return}
        let submitted=editor
        run{
            try await preferences.delete(id:guide.id,expectedCatalogRevision:revision)
            if editor==submitted,editor.id==guide.id{editor=ResponseGuideEditorState(catalogRevision:preferences.catalog?.revision)}
        }
    }
}
