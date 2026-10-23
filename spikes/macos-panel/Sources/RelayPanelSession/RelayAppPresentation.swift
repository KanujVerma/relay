import Foundation
import RelaySessionCapture

extension RelayPreparationPresentation {
    init(_ snapshot:SpeechSetupSnapshot) {
        let title:String
        switch snapshot.stage {
        case .notPrepared:title="Automatic local speech"
        case .checking:title="Checking speech files…"
        case .downloading:title="Preparing local speech…"
        case .validating:title="Verifying speech files…"
        case .ready:title="Local speech files ready"
        case .unavailable:title="Speech setup needs attention"
        case .cancelled:title=snapshot.isBusy ? "Finishing cancellation…":"Preparation cancelled"
        }
        let detail:String
        if let done=snapshot.completedBytes,let total=snapshot.totalBytes,total>0,done<=total {
            detail=ByteCountFormatter.string(fromByteCount:Int64(clamping:done),countStyle:.file)+" of "+ByteCountFormatter.string(fromByteCount:Int64(clamping:total),countStyle:.file)
        }else{detail=snapshot.stage == .notPrepared ? "First setup downloads about 225 MB. Speech then runs locally.":snapshot.userMessage}
        let recovery:Recovery
        switch snapshot.recovery{case .none:recovery = .none;case .retry:recovery = .retry;case .openSettings:recovery = .openSettings}
        self.init(title:title,detail:detail,fraction:snapshot.progressFraction,busy:snapshot.isBusy,recovery:recovery)
    }
}
extension SessionApplicationModel {
    var relayPresentation:RelaySessionPresentation {
        RelaySessionPresentation(running:running,starting:starting,paused:paused,stopping:stopping,preparing:speechSetup.snapshot.isBusy,visualBusy:visual.isBusy,cancellingPreparation:speechSetup.snapshot.stage == .cancelled && speechSetup.snapshot.isBusy,
            hasQuestion:snapshot.question != nil,hasAnswer:snapshot.card != nil,hasSelectedSource:fixture || !selectedBundleID.isEmpty,
            authorizedConversation:fixture || authorizedConversation,ownerCanStart:canStartSession,ownerCanResume:canResume)
    }
    var relayAnswer:RelayAnswerPresentation? {
        snapshot.card.map{RelayAnswerPresentation(lead:$0.lead,points:$0.points,detail:$0.detail?.text,language:$0.detail?.language,isCode:$0.detail?.kind=="code")}
    }
    var relayContextLabel:String {
        if contextStatus.contains("selected text"){return "Selected text"}
        if contextStatus.contains("image and"){return "Viewed screen"}
        if contextStatus.contains("local OCR"){return "Viewed screen text"}
        return screen.isEnabled ? "Window selected":"Screen off"
    }
}
