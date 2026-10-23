import Combine
import Foundation

public typealias VisualInputControlSender = @MainActor (VisualInputAction,@escaping @Sendable(VisualInputResponse)->Void) async throws -> VisualInputResponse

/// In-memory UI reflection and local producer consent. It is never serialized
/// as a capability; the helper independently owns every network image permit.
@MainActor public final class VisualInputSetupState:ObservableObject {
    @Published public private(set) var status:VisualInputStatus = .disabled
    @Published public private(set) var model:String?
    @Published public private(set) var isBusy=false
    @Published public private(set) var mayOfferImages=false
    public var onRetireImages:(@MainActor ()->Void)?
    public var onTransportFailure:(@MainActor ()->Void)?
    private var generation=UUID()
    private var consentAttempt=false
    private var pending:[UUID:VisualInputAction]=[:]
    private var waiters:[CheckedContinuation<Void,Never>]=[]
    public init(){}
    public var needsDisable:Bool{consentAttempt || !pending.isEmpty || mayOfferImages}
    public var hasPendingVerification:Bool{pending.values.contains(.verify)}
    public var hasPendingDisable:Bool{pending.values.contains(.disable)}
    public var offerGeneration:UUID?{mayOfferImages ? generation:nil}
    public func ownsOfferGeneration(_ candidate:UUID)->Bool{mayOfferImages && candidate==generation}

    public func beginVerification(using sender:@escaping VisualInputControlSender) {
        guard pending.isEmpty else{return}
        retireReflection();consentAttempt=true
        submit(.verify,using:sender)
    }
    public func disable(using sender:VisualInputControlSender?) {
        let notify=needsDisable,alreadyDisabling=pending.values.contains(.disable)
        retireReflection(notify:false)
        if notify,!alreadyDisabling,let sender{submit(.disable,using:sender)}
        onRetireImages?()
    }
    public func refreshStatus(using sender:@escaping VisualInputControlSender) {
        guard pending.isEmpty else{return}
        submit(.status,using:sender)
    }
    public func retireForHelperChange(){retireReflection()}
    private func retireReflection(notify:Bool=true) {
        generation=UUID();consentAttempt=false;mayOfferImages=false
        status = .disabled;model=nil
        if notify{onRetireImages?()}
    }
    public func waitForQuiescence()async {
        await withCheckedContinuation{continuation in
            if pending.isEmpty{continuation.resume()}else{waiters.append(continuation)}
        }
    }
    private func submit(_ action:VisualInputAction,using sender:@escaping VisualInputControlSender) {
        let operation=UUID(),scope=generation
        pending[operation]=action;isBusy=true
        if action == .verify{status = .checking}
        Task{@MainActor [weak self] in
            guard let self else{return}
            defer{self.finish(operation)}
            do {
                let reply=try await sender(action,{[weak self] reply in
                    Task{@MainActor [weak self] in
                        guard let self,self.generation==scope,self.pending[operation]==action,!reply.isTerminal else{return}
                        self.status=reply.status;self.model=reply.model
                    }
                })
                guard self.generation==scope,self.pending[operation]==action else{return}
                guard reply.action==action,reply.isTerminal else{throw PanelBridgeError.malformed}
                self.status=reply.status;self.model=reply.model
                if action == .verify {
                    self.mayOfferImages=reply.status == .verified
                } else if reply.status != .verified {
                    self.mayOfferImages=false;self.onRetireImages?()
                }
            } catch {
                guard self.generation==scope else{return}
                self.mayOfferImages=false;self.status = .unavailable;self.model=nil
                self.onRetireImages?();self.onTransportFailure?()
            }
        }
    }
    private func finish(_ operation:UUID) {
        pending.removeValue(forKey:operation)
        isBusy = !pending.isEmpty
        guard pending.isEmpty else{return}
        let ready=waiters;waiters.removeAll();ready.forEach{$0.resume()}
    }
}
