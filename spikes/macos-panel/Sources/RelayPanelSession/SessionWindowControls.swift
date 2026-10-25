import AppKit
import SwiftUI
import RelayControls

@MainActor final class SessionHostActions:ControlActionHandling {
    private weak var model:SessionApplicationModel?
    init(model:SessionApplicationModel){self.model=model}
    func perform(_ action:ControlAction)throws { guard let model else { throw ControlsError.closed };try model.perform(action) }
}
@MainActor final class SessionWindowActions:ControlActionHandling {
    let host:SessionHostActions
    var panel:OwnPanelControls?
    init(host:SessionHostActions){self.host=host}
    func perform(_ action:ControlAction)throws {
        if let panel { try panel.perform(action) } else { try host.perform(action) }
    }
}

/// Resolves only Relay's own ordinary window/scroll view. No external app read.
struct SessionWindowAttachment:NSViewRepresentable {
    let resolve:@MainActor (NSWindow,NSScrollView?)->Void
    func makeNSView(context:Context)->NSView { let view=NSView();DispatchQueue.main.async { update(view) };return view }
    func updateNSView(_ view:NSView,context:Context){DispatchQueue.main.async{update(view)}}
    private func update(_ view:NSView) {
        guard let window=view.window else{return}
        resolve(window,view.enclosingScrollView)
    }
}
