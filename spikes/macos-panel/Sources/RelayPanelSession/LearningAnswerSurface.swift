import AppKit
import SwiftUI
import RelaySessionPanel
import RelayContextComposition

/// Inert identity of the card this actual owned view renders. It grants no
/// native lease, source access or indication that the person read the text.
struct LearningAnswerSurfaceIdentity:Equatable {
    let ownerID:UUID,binding:PanelRequestBinding,replacement:UInt64,card:SessionCard
}

@MainActor final class LearningAnswerSurfaceView:NSView {
    var identity:LearningAnswerSurfaceIdentity
    var changed:@MainActor (LearningAnswerSurfaceView)->Void
    init(identity:LearningAnswerSurfaceIdentity,changed:@escaping @MainActor (LearningAnswerSurfaceView)->Void){
        self.identity=identity;self.changed=changed;super.init(frame:.zero)
        postsFrameChangedNotifications=true
        setAccessibilityElement(false)
    }
    required init?(coder:NSCoder){return nil}
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();changed(self)}
    override func viewDidMoveToSuperview(){super.viewDidMoveToSuperview();changed(self)}
    override func layout(){super.layout();changed(self)}
    override func hitTest(_ point:NSPoint)->NSView?{nil}
}

/// The marker covers only the real lead and supporting points. Detail has its
/// own expansion/scroll behavior and never supplies default uptake evidence.
struct LearningAnswerSurfaceAttachment:NSViewRepresentable {
    let identity:LearningAnswerSurfaceIdentity
    let changed:@MainActor (LearningAnswerSurfaceView)->Void
    func makeNSView(context:Context)->LearningAnswerSurfaceView{LearningAnswerSurfaceView(identity:identity,changed:changed)}
    func updateNSView(_ view:LearningAnswerSurfaceView,context:Context){view.identity=identity;view.changed=changed;changed(view)}
}
