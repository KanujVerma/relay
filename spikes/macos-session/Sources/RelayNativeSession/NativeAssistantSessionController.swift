import Foundation

/// Explicit typed lifetime, independent of every capture/source controller.
/// Root confirms the owned transport receipt before completing open/close.
public final class NativeAssistantSessionController:@unchecked Sendable {
    private enum Phase {case idle,opening,active,closing,failed}
    private let lock=NSLock()
    public let authority=SessionPresentationAuthority()
    private var phase:Phase = .idle
    private var opening:NativeAssistantScopeRequest?
    private var closing:NativeAssistantScopeRequest?
    private var latestLease:PresentationLease?
    private var currentRequestID:UUID?
    public init(){}

    public func begin(enqueue:@Sendable(NativeAssistantScopeRequest)throws->Void)throws->NativeAssistantScopeRequest {
        try lock.withLock {
            if phase == .opening,let opening{return opening}
            guard phase == .idle else{throw NativeSessionError.alreadyRunning}
            let lease=try authority.start()
            let request=NativeAssistantScopeRequest(action:.open,lease:lease,requestID:UUID(),controlSequence:1,
                emittedUptimeNanoseconds:DispatchTime.now().uptimeNanoseconds)
            phase = .opening;opening=request;latestLease=lease
            do{try enqueue(request)}catch{fail();throw NativeSessionError.transportClosed}
            return request
        }
    }
    public func completeOpen(_ request:NativeAssistantScopeRequest)throws {
        try lock.withLock {
            guard phase == .opening,opening==request,request.action == .open,authority.snapshot()==request.lease
            else{throw NativeSessionError.notAuthorized}
            phase = .active
        }
    }
    public func issueUserQuestion(expectedLease:PresentationLease,intent:UserQuestionIntent,
                                  question:String?,baseRequestID:UUID?,
                                  enqueue:@Sendable(NativeUserQuestionRequest)throws->Void)throws->NativeUserQuestionRequest {
        try lock.withLock {
            guard phase == .active,authority.snapshot()==expectedLease else{throw NativeSessionError.notAuthorized}
            switch intent {
            case .ask:
                guard let question,!question.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                      question.utf8.count<=500,!question.unicodeScalars.contains(where:{
                          switch $0.properties.generalCategory{case .control,.format,.lineSeparator,.paragraphSeparator:true;default:false}
                      }) else{throw NativeSessionError.notAuthorized}
            case .helpCurrent:
                guard question==nil,let baseRequestID,baseRequestID==currentRequestID else{throw NativeSessionError.notAuthorized}
            }
            guard let lease=authority.invalidate() else{fail();throw NativeSessionError.counterExhausted}
            let request=NativeUserQuestionRequest(lease:lease,requestID:UUID(),anchorEventSequence:1,
                emittedUptimeNanoseconds:DispatchTime.now().uptimeNanoseconds,intent:intent,question:question,baseRequestID:baseRequestID)
            latestLease=lease;currentRequestID=request.requestID
            do{try enqueue(request)}catch{fail();throw NativeSessionError.transportClosed}
            return request
        }
    }
    public func issueAnswerCancellation(expectedLease:PresentationLease,targetRequestID:UUID,
                                        enqueue:@Sendable(NativeAnswerCancelRequest)throws->Void)throws->NativeAnswerCancelRequest {
        try lock.withLock {
            guard phase == .active,authority.snapshot()==expectedLease,currentRequestID==targetRequestID
            else{throw NativeSessionError.notAuthorized}
            guard let lease=authority.invalidate() else{fail();throw NativeSessionError.counterExhausted}
            let request=NativeAnswerCancelRequest(lease:lease,requestID:UUID(),anchorEventSequence:1,
                emittedUptimeNanoseconds:DispatchTime.now().uptimeNanoseconds,targetRequestID:targetRequestID,targetLease:expectedLease)
            latestLease=lease;currentRequestID=nil
            do{try enqueue(request)}catch{fail();throw NativeSessionError.transportClosed}
            return request
        }
    }
    public func beginClose(enqueue:@Sendable(NativeAssistantScopeRequest)throws->Void)throws->NativeAssistantScopeRequest? {
        try lock.withLock {
            if phase == .idle{return nil}
            if phase == .closing{return closing}
            guard phase == .opening || phase == .active,let previous=authority.snapshot() ?? latestLease,
                  previous.presentationGeneration<UInt64.max else{fail();throw NativeSessionError.notAuthorized}
            let lease=PresentationLease(captureSessionID:previous.captureSessionID,sessionEpoch:previous.sessionEpoch,
                presentationGeneration:previous.presentationGeneration+1)
            let request=NativeAssistantScopeRequest(action:.close,lease:lease,requestID:UUID(),controlSequence:2,
                emittedUptimeNanoseconds:DispatchTime.now().uptimeNanoseconds)
            // Retire before the enqueue callback or any transport await.
            authority.stop();phase = .closing;closing=request;latestLease=lease;currentRequestID=nil
            do{try enqueue(request)}catch{throw NativeSessionError.transportClosed}
            return request
        }
    }
    public func completeClose(_ request:NativeAssistantScopeRequest)throws {
        try lock.withLock {
            guard phase == .closing,closing==request,request.action == .close else{throw NativeSessionError.notAuthorized}
            phase = .idle;opening=nil;closing=nil;latestLease=nil;currentRequestID=nil
        }
    }
    private func fail(){authority.stop();phase = .failed;currentRequestID=nil}
}
