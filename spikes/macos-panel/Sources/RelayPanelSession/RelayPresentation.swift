import Foundation
import RelayControls

/// Presentation/eligibility only. The real owner rechecks every action and lease.
enum RelayUIAction:CaseIterable { case start,pause,resume,end,help,copy,expand,hide,context,settings,cancelPreparation,retryPreparation,showSession }
struct RelaySessionPresentation {
    var running=false,starting=false,paused=false,stopping=false,preparing=false,visualBusy=false
    var cancellingPreparation=false
    var hasQuestion=false,hasAnswer=false,hasSelectedSource=false,hasRemoteSource=false,authorizedConversation=false
    var ownerCanStart=false,ownerCanResume=false
    var assistantActive=false,assistantPreparing=false,assistantClosing=false
    var status:String{stopping || assistantClosing ? "Stopping":paused ? "Paused":running ? "Listening":assistantPreparing ? "Preparing assistant":assistantActive ? "Assistant · not listening":starting || preparing ? "Preparing":visualBusy ? "Image setup busy":"Ready"}
    func allows(_ action:RelayUIAction)->Bool {
        switch action {
        case .start:return ownerCanStart && hasSelectedSource && authorizedConversation && !paused && !running && !starting && !stopping && !preparing && !visualBusy && !assistantPreparing && !assistantClosing
        case .resume:return ownerCanResume && paused && hasSelectedSource && authorizedConversation && !running && !starting && !stopping && !preparing && !visualBusy && !assistantPreparing && !assistantClosing
        case .pause:return (running || starting || assistantActive || assistantPreparing) && !stopping && !assistantClosing
        case .end:return running || starting || paused || stopping || preparing || visualBusy || assistantActive || assistantPreparing || assistantClosing
        case .help:return (running || assistantActive) && !stopping && !assistantClosing && hasQuestion
        case .copy,.expand:return (running || assistantActive) && !stopping && !assistantClosing && hasAnswer
        case .cancelPreparation:return (preparing || starting || assistantPreparing) && !stopping && !assistantClosing && !cancellingPreparation
        case .retryPreparation:return allows(.start)
        case .showSession:return running || paused || stopping || assistantActive || assistantPreparing || assistantClosing
        case .hide,.context,.settings:return true
        }
    }
}
struct RelayPreparationPresentation {
    enum Recovery { case none,retry,openSettings }
    let title:String
    let detail:String?
    let fraction:Double?
    var busy=false
    var recovery:Recovery = .none
    init(title:String,detail:String?=nil,fraction:Double?=nil,busy:Bool=false,recovery:Recovery = .none) {
        self.title=title;self.detail=detail;self.fraction=fraction.flatMap{$0.isFinite && (0...1).contains($0) ? $0:nil}
        self.busy=busy;self.recovery=recovery
    }
}
/// The large empty-card message uses the actual panel status, independently of
/// whether the current question remains visible after a terminal decision.
struct RelayEmptyAnswerPresentation {
    let symbol:String
    let title:String
    let detail:String
    init(state:RelaySessionPresentation,status:String,hasQuestion:Bool) {
        symbol=state.paused ? "pause.circle":state.stopping ? "stop.circle":"waveform"
        if state.paused{title="Take your time."}
        else if state.stopping || state.assistantClosing{title="Finishing the session…"}
        else if status == "Thinking"{title="Thinking it through…"}
        else if !status.isEmpty && (hasQuestion || !["Ready","Ready · not listening","Listening"].contains(status)){title=status}
        else{title=state.running ? "Listening for the next question.":"Ask Relay a question."}
        detail=state.paused ? "Resume starts a fresh conversation. Your saved context stays available.":state.stopping || state.assistantClosing ? "Relay is waiting for active work to finish.":state.running ? "Talking points appear automatically as the conversation develops.":"Audio recording is off. Type a question or follow-up above."
    }
}
@MainActor struct RelayCommandRouter {
    let state:()->RelaySessionPresentation
    let control:(ControlAction)->Void
    let start:()async->Void
    let cancelPreparation:()->Void
    let retryPreparation:()async->Void
    let openContext:()->Void
    let openSettings:()->Void
    let showSession:()->Void
    @discardableResult func perform(_ action:RelayUIAction)->Task<Void,Never>? {
        guard state().allows(action) else{return nil}
        switch action {
        case .start:return Task{@MainActor in await start()}
        case .pause:control(.pause)
        case .resume:control(.resume)
        case .end:control(.endSession)
        case .help:control(.requestHelp)
        case .copy:control(.copyAnswer)
        case .expand:control(.expandAnswer)
        case .hide:control(.hidePanel)
        case .context:openContext()
        case .settings:openSettings()
        case .showSession:showSession()
        case .cancelPreparation:cancelPreparation()
        case .retryPreparation:return Task{@MainActor in await retryPreparation()}
        }
        return nil
    }
}
