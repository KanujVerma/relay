import Foundation
import RelayControls

/// Presentation/eligibility only. The real owner rechecks every action and lease.
enum RelayUIAction:CaseIterable { case start,pause,resume,end,help,copy,expand,hide,context,settings,cancelPreparation,retryPreparation,showSession }
struct RelaySessionPresentation {
    var running=false,starting=false,paused=false,stopping=false,preparing=false,visualBusy=false
    var cancellingPreparation=false
    var hasQuestion=false,hasAnswer=false,hasSelectedSource=false,authorizedConversation=false
    var ownerCanStart=false,ownerCanResume=false
    var status:String{stopping ? "Stopping":paused ? "Paused":running ? "Listening":starting || preparing ? "Preparing":visualBusy ? "Image setup busy":"Ready"}
    func allows(_ action:RelayUIAction)->Bool {
        switch action {
        case .start:return ownerCanStart && hasSelectedSource && authorizedConversation && !paused && !running && !starting && !stopping && !preparing && !visualBusy
        case .resume:return ownerCanResume && paused && hasSelectedSource && authorizedConversation && !running && !starting && !stopping && !preparing && !visualBusy
        case .pause:return (running || starting) && !stopping
        case .end:return running || starting || paused || stopping || preparing || visualBusy
        case .help:return running && !stopping && hasQuestion
        case .copy,.expand:return running && !stopping && hasAnswer
        case .cancelPreparation:return (preparing || starting) && !stopping && !cancellingPreparation
        case .retryPreparation:return allows(.start)
        case .showSession:return running || paused || stopping
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
