import AppKit
import SwiftUI

/// Presentation windows only; the session model remains the single owner.
@MainActor final class RelayWindowShell:ObservableObject {
    @Published var expanded=true
    weak var liveWindow:NSWindow?
    private var fixtureStartClaimed=false
    func claimFixtureStart()->Bool {
        guard !fixtureStartClaimed else{return false}
        fixtureStartClaimed=true
        return true
    }
    func attachLive(_ window:NSWindow){
        liveWindow=window
        window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true
        window.isMovableByWindowBackground=true
        window.backgroundColor = .clear;window.isOpaque=false;window.hasShadow=false
    }
    func hideLive(){liveWindow?.orderOut(nil)}
}
struct RelayLiveWindowAttachment:NSViewRepresentable {
    let shell:RelayWindowShell
    let attach:@MainActor (NSWindow)->Void
    func makeNSView(context:Context)->NSView{let view=NSView();DispatchQueue.main.async{resolve(view)};return view}
    func updateNSView(_ view:NSView,context:Context){DispatchQueue.main.async{resolve(view)}}
    private func resolve(_ view:NSView){guard let window=view.window else{return};shell.attachLive(window);attach(window)}
}
