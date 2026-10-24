import Foundation
import RelayNativeSession
import RelaySessionPanel
import RelayContextComposition

/// One actual conversation lifetime. Its identity, native authority and source
/// controller never change when the same child is reused for another scope.
final class ConversationOwner:@unchecked Sendable {
    enum Kind {case capture,assistant}
    let id=UUID()
    let kind:Kind
    let helper:HelperTransport
    let helperIdentity:UUID
    let authority:SessionPresentationAuthority
    let assistantController:NativeAssistantSessionController?
    let sourceController:NativeSessionController?
    let preparationIntent:UUID?
    private let lock=NSLock()
    private var retired=false
    private var session:(UUID,UInt64)?
    @MainActor let presentation:ConversationPresentation
    @MainActor var closeTask:Task<Void,Never>?
    @MainActor var opening:NativeAssistantScopeRequest?
    @MainActor var closing:NativeAssistantScopeRequest?
    @MainActor var ready=false
    @MainActor var cleanupFinished=false
    @MainActor init(helper:HelperTransport,helperIdentity:UUID,preparationIntent:UUID) {
        kind = .assistant;self.helper=helper;self.helperIdentity=helperIdentity;self.preparationIntent=preparationIntent
        let controller=NativeAssistantSessionController();assistantController=controller
        authority=controller.authority;sourceController=nil
        presentation=ConversationPresentation(authority:controller.authority)
    }
    @MainActor init(helper:HelperTransport,helperIdentity:UUID,authority:SessionPresentationAuthority,source:NativeSessionController) {
        kind = .capture;self.helper=helper;self.helperIdentity=helperIdentity;self.authority=authority
        preparationIntent=nil;assistantController=nil;sourceController=source
        presentation=ConversationPresentation(authority:authority)
    }
    var isRetired:Bool{lock.withLock{retired}}
    func markRetired(){lock.withLock{retired=true}}
    func retireAdmission(){markRetired();authority.stop()}
    func record(_ lease:PresentationLease){lock.withLock{if session==nil{session=(lease.captureSessionID,lease.sessionEpoch)}}}
    func matches(_ id:UUID,epoch:UInt64)->Bool{lock.withLock{session?.0==id && session?.1==epoch}}
}

/// Sole storage for the current owner and helper generation. The IO failure
/// path retires this same owner synchronously, including after child reuse.
final class ConversationOwnerBox:@unchecked Sendable {
    private let lock=NSLock()
    private var owner:ConversationOwner?
    private var helperIdentity:UUID?
    private var helperFailed=false
    private var retirement:UUID?
    var current:ConversationOwner?{lock.withLock{owner}}
    func activateHelper(_ identity:UUID){lock.withLock{helperIdentity=identity;helperFailed=false}}
    func install(_ value:ConversationOwner)->Bool {
        lock.withLock{
            guard owner==nil,retirement==nil,helperIdentity==value.helperIdentity,!helperFailed else{return false}
            owner=value;return true
        }
    }
    func owns(_ value:ConversationOwner)->Bool{lock.withLock{owner === value && helperIdentity==value.helperIdentity}}
    func remove(_ value:ConversationOwner){lock.withLock{if owner === value{owner=nil}}}
    func failHelper(_ identity:UUID)->Bool {
        let result=lock.withLock{()->(Bool,ConversationOwner?,UUID?) in
            guard helperIdentity==identity,!helperFailed else{return(false,nil,nil)}
            helperFailed=true
            guard let owner,owner.helperIdentity==identity,retirement==nil else{return(true,nil,nil)}
            // One bounded reservation survives helper activation/removal. A
            // delayed old failure cannot race a reused capture controller.
            let ticket=UUID();retirement=ticket;owner.markRetired()
            return(true,owner,ticket)
        }
        // Panel commits can read this box while holding the authority lock.
        // Neither this box nor the owner's flag lock may acquire authority or
        // source locks. Keep the original owner reserved until both retire.
        if let original=result.1{
            original.retireAdmission();original.sourceController?.retire()
        }
        if let ticket=result.2{lock.withLock{if retirement==ticket{retirement=nil}}}
        return result.0
    }
}

@MainActor final class ConversationPresentation {
    let authority:SessionPresentationAuthority
    let panel:SessionPanelController
    let publication:ContextPublicationGate
    var composer:QuestionContextComposer?
    var forwarder:OrderedContextForwarder?
    var responsePreferences:ResponsePreferencesRequestBridge?
    var learning:LearningMemoryRequestBridge?
    var currentBinding:PanelRequestBinding?
    var lastContextRetirement:(PanelRequestBinding,Bool)?
    var acceptedQuestion:String?
    var terminalObserved=false,taskContextUsed=false,imageContextUsed=false
    var manualRequestToShow:UUID?
    var explicitRequestIDs:[UUID]=[]
    var lastForwardedSequence:UInt64=0
    var forwardedSessionID:UUID?
    init(authority:SessionPresentationAuthority){
        self.authority=authority;panel=SessionPanelController(authority:authority)
        publication=ContextPublicationGate(authority:authority)
    }
}
