import AppKit
import Combine
import Darwin
import Foundation
import RelayNativeSession
import RelaySessionCapture
import RelayAudioBuffer
import RelaySessionPanel
import RelayProfile
import RelayScreenContext
import RelayControls
import RelayContextComposition
import RelayAccount

private enum ApplicationIngress:Sendable {
    case session(SessionIngress)
    case typed(NativeUserQuestionRequest,PanelRequestBinding?)
    case answerCancel(NativeAnswerCancelRequest,PanelRequestBinding)
    case assistantScope(NativeAssistantScopeRequest)
    func encodedByteCount()throws->Int {
        switch self {
        case .session(let ingress):return try ingress.encodedByteCount()
        case .typed(let request,_):return try request.encodedJSON().count+4
        case .answerCancel(let request,_):return try request.encodedJSON().count+4
        case .assistantScope(let request):return try request.encodedJSON().count+4
        }
    }
}
private final class MainEventQueue: @unchecked Sendable {
    private let lock=NSLock();private var count=0;private var bytes=0
    private var waiters:[CheckedContinuation<Void,Never>]=[]
    func enqueue(_ ingress:ApplicationIngress,action:@escaping @MainActor @Sendable(ApplicationIngress)->Void) throws {
        let size=try ingress.encodedByteCount()
        try lock.withLock { guard count<32,bytes+size<=262144 else { throw PanelBridgeError.overflow };count+=1;bytes+=size }
        DispatchQueue.main.async { [self] in
            defer {
                let ready=lock.withLock { count-=1;bytes-=size;guard count==0 else { return [CheckedContinuation<Void,Never>]() };let ready=waiters;waiters.removeAll();return ready }
                ready.forEach{$0.resume()}
            }
            action(ingress)
        }
    }
    @MainActor func drain() async {
        await withCheckedContinuation { continuation in
            let done=lock.withLock { if count==0{return true};waiters.append(continuation);return false }
            if done { continuation.resume() }
        }
    }
}
private actor FixtureVAD: SpeechActivityDetector {
    nonisolated let chunkSamples=512
    private var count:UInt64=0
    func accept(_ samples:[Float]) async throws -> [SpeechBoundary] {
        count+=1
        return [SpeechBoundary(kind:count%2==1 ? .start:.end,sampleIndex:count%2==1 ? (count-1)*512:count*512)]
    }
}
private actor FixtureRecognizer: ActivityRecognizer {
    private var questions:[String]
    private let fails:Bool
    init(_ questions:[String],fails:Bool=false) { self.questions=questions;self.fails=fails }
    func recognize(_ samples:[Float]) async throws -> String {
        if fails { throw NativeSessionError.modelUnavailable }
        return questions.isEmpty ? "":questions.removeFirst()
    }
}

@MainActor private final class SharedProfileBinding {
    let id=UUID()
    var retired=false
    var helper:HelperTransport?
    private var requests=0
    private var waiters:[CheckedContinuation<Void,Never>]=[]
    func beginRequest()throws{
        guard !retired,requests<4 else{throw PanelBridgeError.closed};requests+=1
    }
    func finishRequest(){
        requests-=1
        if requests==0{let pending=waiters;waiters=[];pending.forEach{$0.resume()}}
    }
    func shutdown() async {
        retired=true
        await helper?.shutdownAndWait()
        // A framed response can already have left the child while its original
        // native owner still awaits delivery. Join that original callback too.
        await withCheckedContinuation{continuation in
            if requests==0{continuation.resume()}else{waiters.append(continuation)}
        }
    }
}
@MainActor private final class FixtureContextPreferences:SessionContextUsePreferences {
    var useInSessions=false
}
@MainActor private final class FixtureHistoryPreferences:HistorySavingPreferences{var savingEnabled=false}
@MainActor private final class FixtureLearningControls:LearningControlPreferences {
    func read()->LearningControlReceipt{LearningControlReceipt(revision:nil,enabled:false,pending:nil)}
    func deny(_ pending:LearningPendingControl)throws->LearningControlReceipt{throw HistoryError.unavailable}
    func commit(_ control:LearningControlRecord)throws->LearningControlReceipt{throw HistoryError.unavailable}
}

@MainActor final class SessionApplicationModel: ObservableObject {
    @Published private(set) var snapshot=SessionPanelSnapshot()
    @Published private(set) var running=false
    @Published private(set) var assistantActive=false
    @Published private(set) var assistantClosing=false
    @Published private(set) var starting=false
    @Published private(set) var paused=false
    @Published private(set) var stopping=false
    @Published private(set) var contextStatus=""
    @Published var expanded=false
    @Published var settingsSection:RelaySettingsSection = .general
    @Published private(set) var error:String?
    @Published var selectedBundleID=""
    @Published private(set) var selectedTextBundleID=""
    @Published var microphoneEnabled=true
    @Published var authorizedConversation=false
    @Published var modelLicensesAcknowledged=false
    @Published var asrFolder=""
    @Published var vadFolder=""
    let fixture:Bool
    let fixtureSuite:String
    @Published private(set) var oauth:Bool
    let role:String
    let root:URL
    private let helperRuntime:Result<HelperRuntimeLocation,HelperRuntimeError>
    private let captureAuthority=SessionPresentationAuthority()
    private let owners=ConversationOwnerBox()
    private let idlePresentation=ConversationPresentation(authority:SessionPresentationAuthority())
    private var currentOwner:ConversationOwner?{owners.current}
    private var display:ConversationPresentation{currentOwner?.presentation ?? idlePresentation}
    private var authority:SessionPresentationAuthority{display.authority}
    private let explicitAccountPreparation:(@MainActor (UUID,@escaping @MainActor ()->Bool)async throws->Void)?
    func showResponsePreferences(openWindow:()->Void){settingsSection = .responses;openWindow()}
    var responseGuideName:String{responsePreferences.snapshot.guideName}
    var usedResponseGuideName:String?{
        guard let owner=currentOwner,owns(owner),let binding=owner.presentation.currentBinding,
              let revision=owner.presentation.panel.snapshot.responsePreferencesRevision else{return nil}
        return owner.presentation.responsePreferences?.displayName(for:binding,revision:revision)
    }
    private let responsePreferencesStorage:any ProtectedSnapshotStorage
    private let responsePreferencesReceipts:any ResponsePreferencesReceiptStore
    private var hasResponsePreferences=false
    lazy var responsePreferences:ResponsePreferencesCoordinator = {
        hasResponsePreferences=true
        return ResponsePreferencesCoordinator(storage:responsePreferencesStorage,receipts:responsePreferencesReceipts,onRetire:{[weak self] original in self?.retireResponsePreferences(original)})
    }()
    private let contextCoordinatorOverride:ScreenContextCoordinator?
    private let contextWriteAcknowledged:(@MainActor (Data,PanelRequestBinding) async ->Void)?
    private let ingressEnqueued:(@MainActor (SessionIngress)->Void)?
    let screen=ScreenContextModel()
    let visual=VisualInputSetupState()
    let speechSetup:SpeechSetupCoordinator
    private let contextPreferencesOverride:(any SessionContextUsePreferences)?
    private let profileVaultFactory:(@MainActor ()->ProfileVault)?
    private let profileResponseObserved:(@MainActor (Data) async ->Void)?
    private let accountPortsOverride:AccountApplicationPorts?
    private let accountPreferences:any ChatGPTPlanPreferences
    private var accountStorageController:AccountController?
    private var accountObservation:AnyCancellable?
    private var accountPreparationStorage:AccountPreparationController?
    private var accountPreparationObservation:AnyCancellable?
    private var accountStartIntent:UUID?
    private var accountStartCancellation:Task<Void,Never>?
    private var accountHelperRetiring=false
    var accountPreparationActive:Bool{accountPreparationStorage?.isPreparing == true}
    var accountPreparationCancelling:Bool{accountPreparationStorage?.isCancelling == true || accountStartCancellation != nil}
    private var accountMutationOwned:Bool{accountHelperRetiring || accountStorageController?.busy == true || accountPreparationActive || accountPreparationCancelling}
    var account:AccountController {
        if let accountStorageController{return accountStorageController}
        let directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Relay",isDirectory:true)
        let storage=accountPortsOverride?.storage ?? AccountStorage(sharedDirectory:directory)
        let value=AccountController(storage:storage,portFactory:{[weak self] bootstrap in
            guard let self else{throw PanelBridgeError.closed}
            let runtime=try self.helperRuntime.get()
            if let ports=self.accountPortsOverride{return try ports.control(runtime,bootstrap)}
            return PipeAccountPort(python:runtime.executable,repository:runtime.resourceRoot,bootstrap:bootstrap,pythonArguments:runtime.arguments)
        },retireInference:{[weak self] in
            guard let self else{throw PanelBridgeError.closed}
            try await self.retireSessionHelperForAccountChange()
        },openBrowser:{[weak self] url in
            guard let self else{return false}
            return self.accountPortsOverride?.openBrowser(url) ?? NSWorkspace.shared.open(url)
        },aiEnabled:oauth,persistAIEnabled:{[weak self] enabled in
            self?.accountPreferences.enabled=enabled;self?.oauth=enabled
        },isIdle:{[weak self] in self?.accountMutationIdle == true})
        accountStorageController=value
        accountObservation=value.objectWillChange.sink{[weak self] _ in self?.objectWillChange.send()}
        return value
    }
    private var accountPreparation:AccountPreparationController {
        if let accountPreparationStorage{return accountPreparationStorage}
        let value=AccountPreparationController(account:account);accountPreparationStorage=value
        accountPreparationObservation=value.objectWillChange.sink{[weak self] _ in self?.objectWillChange.send()}
        return value
    }
    private var accountMutationIdle:Bool {
        guard !fixture || accountPortsOverride != nil,case .success=helperRuntime else{return false}
        return !running && !stopping && !assistantClosing && !accountHelperRetiring && teardown==nil
            && (!assistant.snapshot.isPreparing || accountPreparationActive)
            && (!starting || accountPreparationActive) && !speechSetup.snapshot.isBusy && !visual.isBusy
            && profileStorage?.busy != true && !(hasContextUse && contextUse.isBusy)
            && (fixture || capture.phase == .idle) && (accountPreparationStorage?.hasCurrentCaller ?? true)
    }
    func prepareAccountForExplicitAction(intentID:UUID,isCurrent:@escaping @MainActor ()->Bool)async throws {
        try Task.checkCancellation();guard isCurrent() else{throw CancellationError()}
        guard oauth else{return}
        try await accountPreparation.prepare(intentID:intentID,isCurrent:isCurrent)
        try Task.checkCancellation();guard isCurrent(),let selection=account.inferenceSelection,account.owns(selection) else{throw CancellationError()}
    }
    func cancelAccountPreparation(intentID:UUID)async{await accountPreparationStorage?.cancel(intentID:intentID)}
    private func denyAccountStart(){
        accountStartIntent=nil
        guard let preparation=accountPreparationStorage,let intent=preparation.intentID,accountStartCancellation==nil else{return}
        accountStartCancellation=Task{[weak self] in
            await preparation.cancel(intentID:intent)
            self?.accountStartCancellation=nil;self?.objectWillChange.send()
        }
    }
    /// Only OLD helper/provider ownership is retired. The explicit Start/Send
    /// preparer has not issued its new native scope and must not await itself.
    func retireSessionHelperForAccountChange()async throws {
        guard !running,!stopping,!assistantClosing,teardown==nil,(fixture || capture.phase == .idle) else{throw PanelBridgeError.closed}
        accountHelperRetiring=true;defer{accountHelperRetiring=false}
        let oldOwner=currentOwner,old=helper,oldProfile=profileStorage,oldBinding=profileBinding
        // Original owner and writer deny admission BEFORE optional callbacks can
        // release an old typed frame/image. Never acquire authority under box lock.
        oldOwner?.retireAdmission();oldOwner?.sourceController?.retire()
        old?.stop()
        helper=nil;helperIdentity=UUID();owners.activateHelper(helperIdentity)
        oldBinding?.retired=true;profileBinding=nil;profileStorage=nil
        if let oldOwner {
            oldOwner.ready=false
            oldOwner.presentation.forwarder?.retire()
            retireOptionalWork(notifyHelper:false)
            oldOwner.presentation.forwardedSessionID=nil
            oldOwner.presentation.panel.clear(status:"ChatGPT connection updated")
        }
        visual.retireForHelperChange();assistant.transcript.end()
        if let oldOwner{rememberLatency(oldOwner);owners.remove(oldOwner)}
        assistantActive=false;assistantClosing=false;paused = paused && hasHistory && history.hasPausedSession
        assistant.refresh() // Keeps CURRENT preparer's draft/basis and task.
        if hasContextUse{contextUse.retireForHelperChange()}
        if let oldProfile,oldProfile.opened || oldProfile.busy{await oldProfile.close()}
        if hasContextUse{await contextUse.waitForQuiescence()}
        await old?.shutdownAndWait();await oldBinding?.shutdown()
        await oldOwner?.closeTask?.value
        oldOwner?.cleanupFinished=true
        panel.clear(status:"ChatGPT connection updated");snapshot=panel.snapshot
    }
    private var hasContextUse=false
    private var contextUseObservation:AnyCancellable?
    private let historyPreferencesOverride:(any HistorySavingPreferences)?
    private let historyStorageFactory:(@Sendable ()throws->any ProtectedSnapshotStorage)?
    private let learningPreferencesOverride:(any LearningControlPreferences)?
    private let fixtureSessionStart:(@MainActor (NativeSessionController)throws->Void)?
    private var learningObservation:AnyCancellable?
    private var hasLearning=false
    lazy var learning:LearningMemoryCoordinator = {
        hasLearning=true
        let controls:any LearningControlPreferences=learningPreferencesOverride ?? (fixture ? FixtureLearningControls():CFPreferencesLearningControls())
        let value=history.makeLearningCoordinator(preferences:controls,canEnable:{[weak self] in self?.canEnableLearning==true})
        value.onRetire={[weak self] epoch in self?.retireLearningProjection(epoch)}
        learningObservation=value.$snapshot.dropFirst().sink{[weak self] _ in self?.objectWillChange.send()}
        return value
    }()
    let historyNoteDraft=HistoryNoteDraft()
    private var historyObservation:AnyCancellable?
    private var hasHistory=false
    private var historyPermit:HistorySessionPermit?
    lazy var history:SessionHistoryCoordinator = {
        hasHistory=true
        let preferences:any HistorySavingPreferences=historyPreferencesOverride ?? (fixture ? FixtureHistoryPreferences():UserDefaultsHistoryPreferences())
        let factory:@Sendable ()throws->any ProtectedSnapshotStorage
        if let historyStorageFactory{factory=historyStorageFactory}
        else if fixture{factory={throw HistoryError.unavailable}}
        else{factory={
            let directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Relay/History",isDirectory:true)
            return HistoryVaultStorage(directory:directory,keys:KeychainProfileKey(purpose:.history))
        }}
        let coordinator=SessionHistoryCoordinator(storageFactory:factory,preferences:preferences,canEnable:{[weak self] in
            self?.canEnableHistory==true
        })
        coordinator.onRecordsUnavailable={ [weak self] in self?.historyNoteDraft.invalidate($0) }
        assistant.transcript.onHistoryObservation={ [weak self,weak coordinator] observation in
            coordinator?.observe(observation);self?.learning.session.observe(observation)
        }
        coordinator.onSourceDenial={[weak self] notice in self?.handleHistorySourceDenial(notice)}
        historyObservation=coordinator.$snapshot.dropFirst().sink{[weak self] _ in self?.objectWillChange.send()}
        return coordinator
    }()
    @discardableResult func stageHistoryNoteDraft(discardingChanges:Bool=false)->Bool{
        let coordinator=history,view=coordinator.snapshot
        guard let record=view.selected?.record,
              coordinator.allowsManualNoteDraft(record.id,revision:record.revision,epoch:view.epoch) else{return false}
        let staged=historyNoteDraft.stage(record:record,epoch:view.epoch,discardingChanges:discardingChanges)
        return staged && coordinator.allowsManualNoteDraft(record.id,revision:record.revision,epoch:view.epoch)
    }
    lazy var contextUse:SessionContextUseCoordinator = {
        hasContextUse=true
        let preferences:any SessionContextUsePreferences=contextPreferencesOverride ?? (fixture ? FixtureContextPreferences():UserDefaultsSessionContextUsePreferences())
        let use=SessionContextUseCoordinator(preferences:preferences,onInvalidate:{[weak self] in self?.retirePersonalContext()})
        contextUseObservation=use.$snapshot.dropFirst().sink{[weak self] _ in self?.objectWillChange.send()}
        return use
    }()
    private var hasSelectedText=false
    lazy var selectedText:SelectedTextService = {
        hasSelectedText=true
        return SelectedTextService(currentRequest:{ [weak self] in
            guard let self,let request=self.currentBinding,self.authority.snapshot()==request.lease else { return nil }
            return SelectionRequestIdentity(sessionID:request.lease.captureSessionID,sessionEpoch:request.lease.sessionEpoch,presentationGeneration:request.lease.presentationGeneration,requestID:request.requestID)
        })
    }()
    private var hasContextComposer:Bool{display.composer != nil}
    private var contextComposer:QuestionContextComposer {
        if let composer=display.composer{return composer}
        let composer=QuestionContextComposer(authority:authority,screen:contextCoordinatorOverride ?? screen.coordinator,selection:selectedText)
        display.composer=composer;return composer
    }
    private var publication:ContextPublicationGate{display.publication}
    private var forwarder:OrderedContextForwarder?{get{display.forwarder}set{display.forwarder=newValue}}
    private var currentBinding:PanelRequestBinding?{get{display.currentBinding}set{display.currentBinding=newValue}}
    private var lastContextRetirement:(PanelRequestBinding,Bool)?{get{display.lastContextRetirement}set{display.lastContextRetirement=newValue}}
    private var acceptedQuestion:String?{get{display.acceptedQuestion}set{display.acceptedQuestion=newValue}}
    private var terminalObserved:Bool{get{display.terminalObserved}set{display.terminalObserved=newValue}}
    private var taskContextUsed:Bool{get{display.taskContextUsed}set{display.taskContextUsed=newValue}}
    private var imageContextUsed:Bool{get{display.imageContextUsed}set{display.imageContextUsed=newValue}}
    private var manualRequestToShow:UUID?{get{display.manualRequestToShow}set{display.manualRequestToShow=newValue}}
    private var explicitRequestIDs:[UUID]{get{display.explicitRequestIDs}set{display.explicitRequestIDs=newValue}}
    private var assistantObservation:AnyCancellable?
    lazy var assistant:TypedAssistantController = {
        let controller=TypedAssistantController(session:{[weak self] in
        self?.currentAssistantLease()
    },currentRequest:{[weak self] in self?.currentBinding},issue:{[weak self] intent,question,basis in
        guard let self else{throw PanelBridgeError.closed}
        return try self.issueAssistantQuestion(intent,question:question,basis:basis)
    },cancel:{[weak self] target in
        guard let self else{throw PanelBridgeError.closed}
        return try await self.cancelAssistantResponse(target)
    },preparation:TypedSessionPreparationPorts(canPrepareSession:{[weak self] in self?.canPrepareAssistant == true},
        prepareSession:{[weak self] intent,current in
            guard let self else{throw PanelBridgeError.closed}
            return try await self.prepareAssistantSession(intent: intent,isCurrent:current)
        },retireUnusedSession:{[weak self] intent,lease in
            guard let self,let owner=self.currentOwner,owner.preparationIntent==intent,
                  owner.matches(lease.captureSessionID,epoch:lease.sessionEpoch) else{return}
            await self.closeAssistantScope(owner)
        }))
        assistantObservation=controller.$snapshot.dropFirst().sink{[weak self] _ in self?.objectWillChange.send()}
        return controller
    }()
    private var lastForwardedSequence:UInt64{get{display.lastForwardedSequence}set{display.lastForwardedSequence=newValue}}
    private var startTask:Task<Void,Never>?
    private var startIdentity=UUID()
    private var teardown:Task<Void,Never>?
    private var endRequested=false
    private var focusObserver:NSObjectProtocol?
    private weak var answerScrollView:NSScrollView?
    private weak var window:NSWindow?
    private var windowObserver:NSObjectProtocol?
    private lazy var hostActions=SessionHostActions(model:self)
    private lazy var windowActions=SessionWindowActions(host:hostActions)
    lazy var controls=ControlsController(registrar:KeyboardShortcutsRegistrar(),actionPort:windowActions)
    private let events=MainEventQueue()
    private let answers=BoundedMainDelivery<Data>()
    private var helper:HelperTransport?
    private var helperIdentity=UUID()

    private var panel:SessionPanelController{display.panel}
    private lazy var native:NativeSessionController = {
        let queue=events,box=owners
        return NativeSessionController(authority:captureAuthority,onEvent:{ [weak self] event in
            guard let owner=box.current,owner.kind == .capture else{return}
            if event.kind == .sessionStarted{owner.record(event.lease)}
            guard owner.matches(event.captureSessionID,epoch:event.sessionEpoch) else{return}
            try queue.enqueue(.session(.audio(event))) { [weak self,weak owner] value in
                guard let self,let owner,self.owners.owns(owner) else{return};self.receiveApplication(value,owner:owner)
            }
        })
    }()
    private lazy var capture:NativeCaptureSession = {
        let queue=events,box=owners
        return NativeCaptureSession(authority:captureAuthority,onEvent:{ [weak self] event in
            guard let owner=box.current,owner.kind == .capture else{return}
            if event.kind == .sessionStarted{owner.record(event.lease)}
            guard owner.matches(event.captureSessionID,epoch:event.sessionEpoch) else{return}
            try queue.enqueue(.session(.audio(event))) { [weak self,weak owner] value in
                guard let self,let owner,self.owners.owns(owner) else{return};self.receiveApplication(value,owner:owner)
            }
        })
    }()
    private var profileStorage:ProfileController?
    private var profileBinding:SharedProfileBinding?
    private var forwardedSessionID:UUID?{get{display.forwardedSessionID}set{display.forwardedSessionID=newValue}}
    var profile:ProfileController {
        if let profileStorage { return profileStorage }
        let binding=SharedProfileBinding();profileBinding=binding
        let port=ClosureProfilePort(request:{ [weak self,binding] data in
            guard let self else { throw PanelBridgeError.closed }
            return try await self.profileRequest(data,binding:binding)
        },emergencyShutdown:{ [weak self,binding] in
            if let self { await self.shutdownProfile(binding) }
            else { await binding.shutdown() }
        })
        let vault:ProfileVault
        if let profileVaultFactory{vault=profileVaultFactory()}
        else{
            let directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Relay",isDirectory:true)
            vault=ProfileVault(directory:directory)
        }
        let controller=ProfileController(client:ProfileClient(port:port),vault:vault,onInvalidate:{[weak self,weak binding] in
            guard let self,let binding,self.profileBinding === binding,!binding.retired else{return}
            self.retirePersonalContext()
        })
        profileStorage=controller;return controller
    }
    private func retirePersonalContext(){retireRequest(status:"Background updated");authority.invalidate()}
    private func profileTarget()->ProfileUseTarget?{
        let controller=profile
        guard let binding=profileBinding else{return nil}
        return ProfileUseTarget(controller:controller,bindingID:binding.id,isCurrent:{[weak self,weak binding,weak controller] in
            guard let self,let binding,let controller else{return false}
            return self.profileBinding === binding && self.profileStorage === controller && !binding.retired
                && (binding.helper == nil || binding.helper === self.helper)
        })
    }
    func openMyContext(){
        guard !stopping,!accountMutationOwned,(!fixture || (contextPreferencesOverride != nil && profileVaultFactory != nil)),let target=profileTarget() else{return}
        contextUse.openFromUserAction(target:target)
    }
    func lockMyContext(){
        assistant.cancelPreparation()
        guard let target=profileTarget() else{return}
        contextUse.lockFromUserAction(target:target)
    }
    private func profileRequest(_ data:Data,binding:SharedProfileBinding) async throws -> Data {
        guard !binding.retired,profileBinding === binding else { throw PanelBridgeError.closed }
        try binding.beginRequest();defer{binding.finishRequest()}
        let transport:HelperTransport
        if let bound=binding.helper { transport=bound }
        else { transport=try ensureHelper(referenceOnly:true);binding.helper=transport }
        let response=try await transport.requestProfile(data)
        if let profileResponseObserved{await profileResponseObserved(data)}
        guard !binding.retired,profileBinding === binding,binding.helper === transport,helper === transport else{throw PanelBridgeError.closed}
        return response
    }
    private func shutdownProfile(_ binding:SharedProfileBinding) async {
        binding.retired=true
        if hasContextUse{contextUse.retireForHelperChange()}
        if let old=binding.helper,old === helper {
            // Close all old admission before the first await. Queued frames and
            // source events cannot cross into a replacement helper lifecycle.
            let oldOwner=currentOwner
            let oldHistory=hasHistory ? history:nil
            let oldHistoryPermit=oldHistory?.retireCurrentSession(gap:.captureFailure)
            oldOwner?.retireAdmission();assistant.cancelPreparation()
            if oldOwner?.kind == .capture{if fixture{native.beginStop()}else{capture.retireAdmission(reason:.transportClosed)}}
            retireOptionalWork();helperIdentity=UUID();owners.activateHelper(helperIdentity)
            visual.retireForHelperChange()
            forwardedSessionID=nil;helper=nil;running=false;assistantActive=false;paused=false
            panel.clear(status:"Profile unavailable");error="Profile could not be locked. Its helper was stopped. Reopen background to recover."
            old.stop()
            if oldOwner?.kind == .capture {
                if fixture{await native.waitForQuiescence();native.finishStop(quiesced:true)}else{await capture.stop(reason:.transportClosed)}
            }
            await events.drain()
            if let oldHistory,let oldHistoryPermit{try? await oldHistory.finishSession(oldHistoryPermit,paused:false);if historyPermit === oldHistoryPermit{historyPermit=nil}}
            if let oldOwner{rememberLatency(oldOwner);owners.remove(oldOwner)}
        }
        await binding.shutdown()
        if profileBinding === binding { profileBinding=nil;profileStorage=nil }
    }

    init(arguments:[String]=CommandLine.arguments,contextCoordinator:ScreenContextCoordinator?=nil,
         contextWriteAcknowledged:(@MainActor (Data,PanelRequestBinding) async ->Void)?=nil,
         ingressEnqueued:(@MainActor (SessionIngress)->Void)?=nil,
         speechSetup:SpeechSetupCoordinator?=nil,
         contextPreferences:(any SessionContextUsePreferences)?=nil,
         profileVaultFactory:(@MainActor ()->ProfileVault)?=nil,
         profileResponseObserved:(@MainActor (Data) async ->Void)?=nil,
         historyPreferences:(any HistorySavingPreferences)?=nil,
         historyStorageFactory:(@Sendable ()throws->any ProtectedSnapshotStorage)?=nil,
         learningPreferences:(any LearningControlPreferences)?=nil,
         fixtureSessionStart:(@MainActor (NativeSessionController)throws->Void)?=nil,
         explicitAccountPreparation:(@MainActor (UUID,@escaping @MainActor ()->Bool)async throws->Void)?=nil,
         responsePreferencesStorage:(any ProtectedSnapshotStorage)?=nil,
         responsePreferencesReceipts:(any ResponsePreferencesReceiptStore)?=nil,
         accountPorts:AccountApplicationPorts?=nil,
         bundleURL:URL=Bundle.main.bundleURL,
         workingDirectory:URL=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)) {
        self.speechSetup=speechSetup ?? SpeechSetupCoordinator()
        self.explicitAccountPreparation=explicitAccountPreparation
        self.responsePreferencesStorage=responsePreferencesStorage ?? DefaultResponsePreferencesStorage()
        self.responsePreferencesReceipts=responsePreferencesReceipts ?? UserDefaultsResponsePreferencesReceipts()
        contextPreferencesOverride=contextPreferences;self.profileVaultFactory=profileVaultFactory
        self.profileResponseObserved=profileResponseObserved
        historyPreferencesOverride=historyPreferences;self.historyStorageFactory=historyStorageFactory
        learningPreferencesOverride=learningPreferences;self.fixtureSessionStart=fixtureSessionStart
        accountPortsOverride=accountPorts
        self.contextCoordinatorOverride=contextCoordinator
        self.contextWriteAcknowledged=contextWriteAcknowledged;self.ingressEnqueued=ingressEnqueued
        fixture=arguments.contains("--fixture-suite")
        fixtureSuite=Self.argument("--fixture-suite",arguments) ?? "reviewed"
        role=Self.argument("--role",arguments) ?? (fixture ? "analytics":"developer")
        let preferences:any ChatGPTPlanPreferences
        if let accountPorts{preferences=accountPorts.preferences}
        else if fixture{preferences=FixtureChatGPTPlanPreferences()}
        else{preferences=UserDefaultsChatGPTPlanPreferences()}
        accountPreferences=preferences
        oauth=(!fixture || accountPorts != nil) && (arguments.contains("--oauth") || preferences.enabled)
        do {
            let location=try HelperRuntimeResolver.resolve(bundleURL:bundleURL,arguments:arguments,workingDirectory:workingDirectory)
            helperRuntime = .success(location);root=location.resourceRoot
        }catch{
            let failure=(error as? HelperRuntimeError) ?? .invalidBundledRuntime
            helperRuntime = .failure(failure);root=bundleURL
            self.error=failure.localizedDescription
        }
        asrFolder=Self.argument("--asr-models",arguments) ?? ""
        vadFolder=Self.argument("--vad-model",arguments) ?? ""
        modelLicensesAcknowledged=arguments.contains("--acknowledge-local-model-licenses")
        visual.onRetireImages={ [weak self] in self?.retireVisualImages() }
        visual.onTransportFailure={ [weak self] in self?.failSession() }
        screen.onInvalidation={ [weak self] _ in self?.contextSourceChanged() }
        contextCoordinator?.onInvalidation={ [weak self] _ in self?.contextSourceChanged() }
        focusObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self,self.hasContextComposer,self.contextComposer.contextUse?.provenance=="selected_accessibility_text" else { return }
                self.contextSourceChanged()
            }
        }
    }
    isolated deinit {
        startTask?.cancel()
        speechSetup.cancel()
        if hasContextUse{contextUse.retireForHelperChange()}
        if let focusObserver { NSWorkspace.shared.notificationCenter.removeObserver(focusObserver) }
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        if let windowVisibilityObserver{NotificationCenter.default.removeObserver(windowVisibilityObserver)}
        surfaceObservation?.cancel()
        if let helper { helper.stop();Task.detached { await helper.shutdownAndWait() } }
    }
    private static func argument(_ key:String,_ args:[String]) -> String? { guard let i=args.firstIndex(of:key),args.indices.contains(i+1) else { return nil };return args[i+1] }
    func ensureHelper(referenceOnly:Bool=false) throws -> HelperTransport {
        guard !stopping,!accountHelperRetiring,accountStorageController?.busy != true,profileBinding?.retired != true else { throw PanelBridgeError.closed }
        if let helper { return helper }
        let runtime=try helperRuntime.get()
        visual.retireForHelperChange()
        let identity=UUID();helperIdentity=identity;owners.activateHelper(identity)
        let box=owners,delivery=answers
        let mode:HelperMode;let bootstrap:AccountSecretBootstrap?;let model:String?
        if oauth,let selected=accountStorageController?.inferenceSelection,accountStorageController?.owns(selected)==true,
           let packet=try accountStorageController?.sessionBootstrap(){mode = .protectedOAuth;bootstrap=packet;model=selected.model}
        else{
            guard !oauth || referenceOnly else{throw AccountError.unavailable}
            mode = fixture ? .fixture:.noInference;bootstrap=nil;model=nil
        }
        let arguments=accountPortsOverride?.sessionArguments(runtime,mode) ?? runtime.arguments
        let helper=HelperTransport(root:runtime.resourceRoot,python:runtime.executable,pythonArguments:arguments,mode:mode,
            accountBootstrap:bootstrap,model:model,role:role,onFrame:{ [weak self] data in
            let decision=try SessionAnswerDecision(data:data)
            guard let owner=box.current,owner.helperIdentity==identity,
                  owner.matches(decision.sessionID,epoch:decision.epoch) else{return}
            try delivery.enqueue(data,byteCount:data.count) { [weak self,weak owner] data in
                guard let self,let owner,self.owners.owns(owner),!owner.isRetired,self.helperIdentity==identity else{return}
                do{try self.acceptFrame(data,owner:owner)}catch{self.failSession()}
            }
        },onFailure:{ [weak self] in
            guard box.failHelper(identity) else{return}
            Task{@MainActor in guard let self,self.helperIdentity==identity else{return};self.failSession()}
        })
        try helper.start();self.helper=helper;return helper
    }
    private func owns(_ owner:ConversationOwner,allowRetired:Bool=false)->Bool {
        owners.owns(owner) && helper === owner.helper && helperIdentity==owner.helperIdentity && (allowRetired || !owner.isRetired)
    }
    private func configure(_ owner:ConversationOwner){
        owner.presentation.responsePreferences=ResponsePreferencesRequestBridge(capture:{[weak self] in
            guard let self else{return nil};return self.responsePreferences.capture()
        },owns:{[weak self] value in self?.responsePreferences.owns(value)==true},send:{[weak self,weak owner] data in
            guard let self,let owner,self.owns(owner) else{throw PanelBridgeError.closed};try owner.helper.sendJSON(data)
        },isCurrent:{[weak self,weak owner] in guard let self,let owner else{return false};return self.owns(owner)})
        owner.presentation.learning=LearningMemoryRequestBridge(capture:{[weak self] question in self?.learning.capture(question:question)},owns:{[weak self] value in
            self?.learning.owns(value)==true
        },send:{[weak self,weak owner] data in
            guard let self,let owner,self.owns(owner) else{throw PanelBridgeError.closed};try owner.helper.sendJSON(data)
        },isCurrent:{[weak self,weak owner] in guard let self,let owner else{return false};return self.owns(owner)})
        contextStatus=""
        owner.presentation.panel.onChange={[weak self,weak owner] in
            // Failure changes the helper generation before clearing this still
            // current owner's display. Only replacement of the owner fences it.
            guard let self,let owner,self.currentOwner === owner else{return}
            self.publishPanelSnapshot(from:owner)
        }
    }
    private var publishingPanelSnapshot=false,panelSnapshotPending=false
    private func publishPanelSnapshot(from owner:ConversationOwner){
        guard currentOwner === owner else{return}
        panelSnapshotPending=true
        guard !publishingPanelSnapshot else{return}
        publishingPanelSnapshot=true;defer{publishingPanelSnapshot=false}
        while panelSnapshotPending{
            panelSnapshotPending=false
            let original=currentOwner
            // @Published notifies before storing. A synchronous subscriber may
            // retire this card; drain its actual panel after that setter returns.
            snapshot=(original?.presentation ?? idlePresentation).panel.snapshot
            if currentOwner !== original{panelSnapshotPending=true}
        }
    }
    private func installCaptureOwner(_ transport:HelperTransport)throws {
        let owner=ConversationOwner(helper:transport,helperIdentity:helperIdentity,authority:captureAuthority,
            source:fixture ? native:capture.controller)
        guard owners.install(owner) else{throw PanelBridgeError.closed};configure(owner)
    }
    private func currentAssistantLease()->PresentationLease? {
        guard let owner=currentOwner,owns(owner),!stopping else{return nil}
        if owner.kind == .assistant{return owner.ready ? owner.authority.snapshot():nil}
        guard running,!paused,
              owner.sourceController?.isSourceActive(.microphone)==true || owner.sourceController?.isSourceActive(.remoteAudio)==true else{return nil}
        return owner.authority.snapshot()
    }
    private var canPrepareAssistant:Bool {
        guard case .success=helperRuntime else{return false}
        return !running && !starting && !stopping && !assistantClosing && !accountMutationOwned && teardown==nil && currentOwner==nil
            && !speechSetup.snapshot.isBusy && !visual.isBusy && visual.status != .busy
            && profileStorage?.busy != true && !(hasContextUse && contextUse.isBusy) && !(hasResponsePreferences && responsePreferences.isBusy)
    }
    private func prepareAssistantSession(intent:UUID,isCurrent:@escaping @MainActor ()->Bool)async throws->PresentationLease {
        guard canPrepareAssistant,isCurrent() else{throw CancellationError()}
        error=nil
        if let explicitAccountPreparation{try await explicitAccountPreparation(intent,isCurrent)}
        else{try await prepareAccountForExplicitAction(intentID:intent,isCurrent:isCurrent)}
        try Task.checkCancellation()
        if !fixture{try await responsePreferences.prepareForExplicitAction(intentID:intent,isCurrent:isCurrent)}
        guard canPrepareAssistant,isCurrent(),!Task.isCancelled else{throw CancellationError()}
        if (try? await learning.needsRetainedSourcePreparation())==true{
            guard canPrepareAssistant,isCurrent(),!Task.isCancelled else{throw CancellationError()}
            if history.savingEnabled{await history.waitForQuiescence();_=try? await history.openExisting()}
            guard canPrepareAssistant,isCurrent(),!Task.isCancelled else{throw CancellationError()}
            _=try? await learning.restore()
        }
        guard canPrepareAssistant,isCurrent(),!Task.isCancelled else{throw CancellationError()}
        let use=contextUse,intendedUse=contextUse.useInSessions
        let target=intendedUse ? profileTarget():nil
        if intendedUse {
            guard let target else{throw PanelBridgeError.closed}
            let result=await use.restoreBeforeSession(target:target,startIntentID:intent,isStartCurrent:{[weak self] in
                guard let self else{return false};return isCurrent() && !self.stopping && !self.starting
            })
            guard result == .ready else{
                if isCurrent(){error=use.snapshot.message};throw PanelBridgeError.closed
            }
        }
        let profileIsCurrent={ [weak self] in
            guard let self,!use.isBusy,self.profileStorage?.busy != true,use.useInSessions==intendedUse else{return false}
            guard intendedUse else{return true}
            guard let target,let binding=self.profileBinding else{return false}
            return target.controller.opened && !target.controller.busy && self.profileStorage === target.controller
                && binding.id==target.bindingID && !binding.retired && binding.helper === self.helper
        }
        guard isCurrent(),!Task.isCancelled,!stopping,!starting,currentOwner==nil,profileIsCurrent() else{throw CancellationError()}
        let transport=try ensureHelper()
        let owner=ConversationOwner(helper:transport,helperIdentity:helperIdentity,preparationIntent:intent)
        guard owners.install(owner) else{throw PanelBridgeError.closed};configure(owner)
        do {
            guard let controller=owner.assistantController else{throw PanelBridgeError.closed}
            let queue=events
            let opening=try controller.begin(enqueue:{[weak self,weak owner] request in
                guard let owner else{throw PanelBridgeError.closed};owner.record(request.lease)
                _=try transport.registerAssistantScope(request)
                try queue.enqueue(.assistantScope(request)){[weak self,weak owner] value in
                    guard let self,let owner else{return};self.receiveApplication(value,owner:owner)
                }
            })
            owner.opening=opening
            let response=try await transport.registerAssistantScope(opening).value()
            guard response.status == .ready,isCurrent(),!Task.isCancelled,owns(owner),!stopping,!starting,profileIsCurrent() else{throw CancellationError()}
            try controller.completeOpen(opening);owner.ready=true
            forwardedSessionID=opening.assistantSessionID;assistantActive=true;paused=false
            assistant.transcript.end()
            panel.clear(status:"Ready · not listening");assistant.refresh()
            return opening.lease
        }catch{
            await closeAssistantScope(owner)
            throw error
        }
    }
    /// Local authority and matching staged data retire before this returns. The
    /// returned task owns the actual helper close receipt or process-reap fallback.
    private func beginClosingAssistantScope(_ owner:ConversationOwner)->Task<Void,Never> {
        if let task=owner.closeTask{return task}
        if owner.cleanupFinished{return Task{}}
        owner.retireAdmission();owner.ready=false
        if owners.owns(owner){assistantActive=false;assistantClosing=true}
        let transport=owner.helper,queue=events
        var pending:PendingAssistantScopeResponse?
        do {
            if owns(owner,allowRetired:true){
                if let old=currentBinding{try transport.sendJSON(old.retirementJSON());guard enqueueContextRetirement(old) else{throw PanelBridgeError.closed}}
                disableVisualInput();retireRequest(status:"Ready · not listening")
            }
            if let controller=owner.assistantController,
               let closing=try controller.beginClose(enqueue:{[weak self,weak owner] request in
                   _=try transport.registerAssistantScope(request)
                   try queue.enqueue(.assistantScope(request)){[weak self,weak owner] value in
                       guard let self,let owner else{return};self.receiveApplication(value,owner:owner)
                   }
               }) {
                owner.closing=closing;pending=try transport.registerAssistantScope(closing)
            }
        }catch{transport.stop()}
        let receipt=pending
        let task=Task{@MainActor [weak self,owner] in
            guard let self else{await transport.shutdownAndWait();return}
            var closed=false
            if let receipt,let closing=owner.closing {
                do {
                    let result=try await receipt.value()
                    guard result.status == .closed,result.quiesced == true else{throw PanelBridgeError.closed}
                    try owner.assistantController?.completeClose(closing);closed=true
                }catch{}
            }
            if !closed {
                transport.stop();await transport.shutdownAndWait()
                if self.helper === transport {
                    let binding=self.profileBinding,profile=self.profileStorage
                    let use=self.hasContextUse ? self.contextUse:nil
                    self.helper=nil;self.helperIdentity=UUID();self.owners.activateHelper(self.helperIdentity)
                    binding?.retired=true;use?.retireForHelperChange()
                    await binding?.shutdown()
                    if let profile,profile.opened || profile.busy{await profile.close()}
                    await use?.waitForQuiescence()
                    if self.profileBinding === binding{self.profileBinding=nil;self.profileStorage=nil}
                    self.error="The old assistant helper was stopped. Reopen saved context before retrying."
                }
            }
            await self.events.drain()
            owner.presentation.forwarder?.retire();owner.presentation.composer?.retire();owner.presentation.publication.retire();owner.presentation.responsePreferences?.close();owner.presentation.learning?.close()
            if self.currentOwner === owner{self.rememberLatency(owner);self.owners.remove(owner);self.assistantActive=false;self.assistantClosing=false;self.assistant.refresh()}
            owner.cleanupFinished=true
            owner.closeTask=nil
        }
        owner.closeTask=task;return task
    }
    private func closeAssistantScope(_ owner:ConversationOwner)async{await beginClosingAssistantScope(owner).value}
    private func issueAssistantQuestion(_ intent:UserQuestionIntent,question:String?,basis:UUID?)throws->NativeUserQuestionRequest {
        guard let owner=currentOwner,owns(owner),!stopping,let lease=currentAssistantLease() else{throw NativeSessionError.notAuthorized}
        let queue=events,old=currentBinding
        do {
            let enqueue:@Sendable(NativeUserQuestionRequest)throws->Void = {[weak self,weak owner] request in
                try queue.enqueue(.typed(request,old)){[weak self,weak owner] value in
                    guard let self,let owner else{return};self.receiveApplication(value,owner:owner)
                }
            }
            let issued:NativeUserQuestionRequest
            if let controller=owner.assistantController{issued=try controller.issueUserQuestion(expectedLease:lease,intent:intent,question:question,baseRequestID:basis,enqueue:enqueue)}
            else if let controller=owner.sourceController{issued=try controller.issueUserQuestion(expectedLease:lease,intent:intent,question:question,baseRequestID:basis,enqueue:enqueue)}
            else{throw NativeSessionError.notAuthorized}
            explicitRequestIDs.append(issued.requestID)
            if explicitRequestIDs.count>8{explicitRequestIDs.removeFirst()}
            return issued
        }catch NativeSessionError.notAuthorized{throw NativeSessionError.notAuthorized}
        catch{failSession();throw error}
    }
    private func cancelAssistantResponse(_ target:PanelRequestBinding)async throws->AnswerCancellationResponse {
        guard let owner=currentOwner,owns(owner),!stopping,currentBinding==target,let helper else{throw PanelBridgeError.closed}
        let queue=events
        do {
            let enqueue:@Sendable(NativeAnswerCancelRequest)throws->Void = {[weak self,weak owner] request in
                _=try helper.registerAnswerCancellation(request)
                try queue.enqueue(.answerCancel(request,target)){[weak self,weak owner] value in
                    guard let self,let owner else{return};self.receiveApplication(value,owner:owner)
                }
            }
            let issued:NativeAnswerCancelRequest
            if let controller=owner.assistantController{issued=try controller.issueAnswerCancellation(expectedLease:target.lease,targetRequestID:target.requestID,enqueue:enqueue)}
            else if let controller=owner.sourceController{issued=try controller.issueAnswerCancellation(expectedLease:target.lease,targetRequestID:target.requestID,enqueue:enqueue)}
            else{throw NativeSessionError.notAuthorized}
            return try await helper.registerAnswerCancellation(issued).value()
        }catch NativeSessionError.notAuthorized{throw NativeSessionError.notAuthorized}
        catch{
            if self.owns(owner),!self.stopping{failSession()}
            throw error
        }
    }
    private func receiveApplication(_ ingress:ApplicationIngress,owner:ConversationOwner) {
        guard owns(owner,allowRetired:true) else{return}
        switch ingress {
        case .assistantScope(let request):
            guard owner.kind == .assistant,owner.matches(request.assistantSessionID,epoch:request.lease.sessionEpoch) else{return}
            do{try owner.helper.sendJSON(request.encodedJSON())}catch{failSession()}
        case .session(let event):receive(event,owner:owner)
        case .typed(let request,let original):
            guard helper != nil,forwardedSessionID==request.lease.captureSessionID else{return}
            do {
                let binding=PanelRequestBinding(lease:request.lease,requestID:request.requestID,eventSequence:request.anchorEventSequence)
                let learningQuestion=request.question ?? owner.presentation.acceptedQuestion ?? ""
                if let original{try retireExplicitOriginal(original)}
                if owner.authority.snapshot()==binding.lease{
                    try owner.presentation.responsePreferences?.freeze(binding)
                    try owner.presentation.learning?.freeze(binding,question:learningQuestion)
                }
                try eventForwarder(for:owner).enqueueUserQuestion(request,retiring:original)
            }catch{failSession()}
        case .answerCancel(let request,let original):
            guard helper != nil,forwardedSessionID==request.lease.captureSessionID else{return}
            do {
                try retireExplicitOriginal(original)
                try eventForwarder(for:owner).enqueueAnswerCancellation(request,retiring:original)
            }catch{failSession()}
        }
        assistant.refresh()
    }
    /// Deny the original request before callbacks can flush a held EOU/PNG.
    private func retireExplicitOriginal(_ original:PanelRequestBinding)throws {
        guard let helper else{throw PanelBridgeError.closed}
        try helper.sendJSON(original.retirementJSON())
        currentOwner?.presentation.responsePreferences?.retireNative(original)
        currentOwner?.presentation.learning?.retireNative(original)
        guard enqueueContextRetirement(original) else{throw PanelBridgeError.closed}
        if currentBinding==original{retireRequest(status:currentOwner?.kind == .assistant ? "Ready · not listening":"Listening")}
    }
    func receive(_ ingress:SessionIngress) {
        guard let owner=currentOwner else{return};receive(ingress,owner:owner)
    }
    private func receive(_ ingress:SessionIngress,owner:ConversationOwner) {
        guard owns(owner,allowRetired:true),owner.kind == .capture else{return}
        do{if let binding=ingress.binding,owner.authority.snapshot()==binding.lease{
            // A fresh native Manual Help lease supersedes only its original
            // request record. Keep the selected guide available to this request.
            if case .manual=ingress,let original=owner.presentation.currentBinding,original != binding{
                owner.presentation.responsePreferences?.retireNative(original)
                owner.presentation.learning?.retireNative(original)
            }
            try owner.presentation.responsePreferences?.freeze(binding)
            try owner.presentation.learning?.freeze(binding,question:learningQuestion(ingress))
        }}
        catch{if owns(owner,allowRetired:true){failSession()};return}
        switch ingress {
        case .audio(let event):
            owner.presentation.panel.latency.observeNative(event)
            if event.kind == .sessionStarted {
                guard authority.snapshot()?.captureSessionID==event.captureSessionID else { return }
                forwardedSessionID=event.captureSessionID;lastForwardedSequence=0
                explicitRequestIDs=[]
            }
            guard forwardedSessionID==event.captureSessionID else { return }
            if let active=authority.snapshot(),active.captureSessionID != event.captureSessionID { return }
            assistant.observeNative(event)
            let sourceFailed=[SessionEventKind.sourceUnavailable,.discontinuity].contains(event.kind)
            let allSourcesUnavailable=sourceFailed && owner.sourceController?.isSourceActive(.microphone) != true
                && owner.sourceController?.isSourceActive(.remoteAudio) != true
            if !stopping && ([.stopping,.stopped].contains(event.kind)
                || (event.sourceCode==2 && sourceFailed) || allSourcesUnavailable) {
                // Spontaneous native failure takes the same real owner join and
                // helper admission barrier as End, before allowing a fresh Start.
                beginRetirement(end:true)
                error="The audio session ended. Start a new session when ready."
            }
            if event.sourceCode != 1 && [.speechStarted,.sourceUnavailable,.discontinuity,.stopping,.stopped].contains(event.kind) {
                retireOptionalWork();panel.observe(event)
            }
        case .manual(let request):
            guard running,!stopping,forwardedSessionID==request.lease.captureSessionID else { return }
            manualRequestToShow=request.requestID
        }
        do { try eventForwarder(for:owner).enqueue(ingress) } catch { failSession() }
    }
    private func eventForwarder(for owner:ConversationOwner)->OrderedContextForwarder {
        if let forwarder=owner.presentation.forwarder{return forwarder}
        let created=OrderedContextForwarder(shouldCapture:{ [weak self,weak owner] ingress in
            guard let self,let owner,self.owns(owner,allowRetired:true),let binding=ingress.binding,self.authority.snapshot()==binding.lease,self.currentAssistantLease() != nil,!self.stopping else { return false }
            if self.contextCoordinatorOverride?.isEnabled ?? self.screen.isEnabled { return true }
            if case .manual=ingress { return self.selectedText.isEnabled }
            return false
        },capture:{ [weak self,weak owner] ingress in
            guard let self,let owner,self.owns(owner,allowRetired:true),let binding=ingress.binding else { return [] }
            self.bind(binding)
            let deadline=DispatchTime.now().uptimeNanoseconds+1_500_000_000
            var writer:(@MainActor (Data) async throws ->Void)?
            if let generation=self.visual.offerGeneration,let helper=self.helper {
                let helperID=self.helperIdentity
                writer={ [weak self,weak owner] data in
                    try await helper.sendJSONAwaitingWrite(data,deadline:deadline,isCurrent:{ [weak self,weak owner] in
                        guard let self,let owner,self.owns(owner,allowRetired:true) else{return false}
                        return self.helperIdentity==helperID && self.helper === helper && self.currentBinding==binding
                            && self.visual.ownsOfferGeneration(generation) && self.contextComposer.ownsCurrent(binding)
                    })
                    await self?.contextWriteAcknowledged?(data,binding)
                }
            }
            return await self.contextComposer.captureForForwarding(for:binding,readSelectedText:{if case .manual=ingress{return true};return false}(),imageWriter:writer)
        },send:{ [weak self,weak owner] ingress,frames in guard let self,let owner,self.owns(owner,allowRetired:true) else{throw PanelBridgeError.closed};try self.send(ingress,context:frames) },onFailure:{ [weak self,weak owner] in if let self,let owner,self.owns(owner,allowRetired:true){self.failSession()} },explicit:ExplicitContextForwardingPorts(shouldCapture:{[weak self,weak owner] request in
            guard let self,let owner,self.owns(owner,allowRetired:true),self.currentAssistantLease() != nil,!self.stopping,self.authority.snapshot()==request.lease else{return false}
            return (self.contextCoordinatorOverride?.isEnabled ?? self.screen.isEnabled) || self.selectedText.isEnabled
        },capture:{[weak self,weak owner] request in
            guard let self,let owner,self.owns(owner,allowRetired:true) else{return []}
            return await self.captureExplicitContext(request,owner:owner)
        },retire:{[weak self,weak owner] original in
            guard let self,let owner,self.owns(owner,allowRetired:true) else{throw PanelBridgeError.closed}
            try self.retireExplicitOriginal(original)
        },sendQuestion:{[weak self,weak owner] request,frames in
            guard let self,let owner,self.owns(owner,allowRetired:true),let helper=self.helper else{throw PanelBridgeError.closed}
            let binding=PanelRequestBinding(lease:request.lease,requestID:request.requestID,eventSequence:request.anchorEventSequence)
            if self.authority.snapshot() != binding.lease{try helper.sendJSON(binding.retirementJSON());owner.presentation.responsePreferences?.retireNative(binding);owner.presentation.learning?.retireNative(binding)}
            self.bind(binding)
            try owner.presentation.responsePreferences?.sendOffer(for:binding)
            try owner.presentation.learning?.sendOffer(for:binding)
            for frame in frames{try helper.sendJSON(frame)}
            let enqueueStarted=DispatchTime.now().uptimeNanoseconds
            try helper.sendJSON(request.encodedJSON());owner.presentation.panel.latency.recordForwarded(binding:binding,at:enqueueStarted)
        },sendCancellation:{[weak self,weak owner] request in
            guard let self,let owner,self.owns(owner,allowRetired:true),let helper=self.helper else{throw PanelBridgeError.closed}
            try helper.sendJSON(request.encodedJSON())
        }))
        owner.presentation.forwarder=created;return created
    }
    private func bind(_ request:PanelRequestBinding) {
        guard authority.snapshot()==request.lease,currentBinding != request else { return }
        currentBinding=request;lastContextRetirement=nil;terminalObserved=false;taskContextUsed=false;imageContextUsed=false
        publication.bind(request);panel.bind(request)
        assistant.observeRequest(request)
    }
    private func captureExplicitContext(_ request:NativeUserQuestionRequest,owner:ConversationOwner)async->[Data] {
        guard owns(owner) else{return []}
        let binding=PanelRequestBinding(lease:request.lease,requestID:request.requestID,eventSequence:request.anchorEventSequence)
        bind(binding)
        let deadline=DispatchTime.now().uptimeNanoseconds+1_500_000_000
        var writer:(@MainActor (Data)async throws->Void)?
        if let generation=visual.offerGeneration,let helper {
            let identity=helperIdentity
            writer={[weak self,weak owner] data in
                try await helper.sendJSONAwaitingWrite(data,deadline:deadline,isCurrent:{[weak self,weak owner] in
                    guard let self,let owner,self.owns(owner) else{return false}
                    return self.helperIdentity==identity && self.helper === helper && self.currentBinding==binding
                        && self.visual.ownsOfferGeneration(generation) && self.contextComposer.ownsCurrent(binding)
                })
                await self?.contextWriteAcknowledged?(data,binding)
            }
        }
        let composer=contextComposer
        return await composer.captureForForwarding(for:binding,readSelectedText:true,imageWriter:writer)
    }
    private func send(_ ingress:SessionIngress,context:[Data]) throws {
        guard let helper else { throw PanelBridgeError.closed }
        if let binding=ingress.binding {
            if authority.snapshot() != binding.lease{try helper.sendJSON(binding.retirementJSON());currentOwner?.presentation.responsePreferences?.retireNative(binding);currentOwner?.presentation.learning?.retireNative(binding)}
            bind(binding)
            try currentOwner?.presentation.responsePreferences?.sendOffer(for:binding)
            try currentOwner?.presentation.learning?.sendOffer(for:binding)
        }
        for frame in context { try helper.sendJSON(frame) }
        switch ingress {
        case .audio(let event):
            let enqueueStarted=DispatchTime.now().uptimeNanoseconds
            try helper.send(event);lastForwardedSequence=event.eventSequence
            if let binding=ingress.binding{panel.latency.recordForwarded(binding:binding,at:enqueueStarted)}
            if event.kind != .eou { panel.observe(event) }
        case .manual(let request):
            let enqueueStarted=DispatchTime.now().uptimeNanoseconds
            try helper.sendJSON(request.encodedJSON());if let binding=ingress.binding{panel.latency.recordForwarded(binding:binding,at:enqueueStarted)}
        }
        ingressEnqueued?(ingress)
    }
    private func retireResponsePreferences(_ original:ResponsePreferenceSnapshot){
        guard let owner=currentOwner,owns(owner),let bridge=owner.presentation.responsePreferences else{return}
        let binding=owner.presentation.currentBinding
        let affected=binding.map{bridge.capturedRevision(for:$0)==original.revision} ?? false
        do{try bridge.retire(original)}catch{if owns(owner){failSession()};return}
        guard affected,let binding,owns(owner) else{return}
        if owner.presentation.panel.snapshot.responsePreferencesRevision==original.revision{
            owner.presentation.panel.withholdGuideAnswer(for:binding,status:"Response guide changed. Ask again.")
        }else{
            owner.presentation.panel.showPendingStatus(for:binding,status:"Response guide changed. Ask again.")
        }
    }
    private func responsePreferencesAllow(_ decision:SessionAnswerDecision,for binding:PanelRequestBinding,owner:ConversationOwner)->Bool{
        guard let revision=decision.responsePreferencesRevision else{return true}
        return owner.presentation.responsePreferences?.permits(binding,revision:revision)==true
    }
    private func learningQuestion(_ ingress:SessionIngress)->String{
        switch ingress{
        case .manual(let request):return request.question
        case .audio(let event):
            if case .object(let fields)=event.payload["event"],case .string(let text)=fields["text"]{return text};return ""
        }
    }
    private func handleHistorySourceDenial(_ notice:HistorySourceDenial){
        if hasLearning{learning.handleHistorySourceDenial(notice)}
        // Notes adds its independent original-source retirement here; this
        // remains one owned fanout, never a readiness or membership publisher.
    }
    private func learningAllow(_ decision:SessionAnswerDecision,for binding:PanelRequestBinding,owner:ConversationOwner)->Bool{
        guard let revision=decision.learningMemoryRevision else{return true}
        return owner.presentation.learning?.permits(binding,revision:revision)==true
    }
    private func optionalPresentationAllows(_ decision:SessionAnswerDecision,for binding:PanelRequestBinding,owner:ConversationOwner)->Bool{
        responsePreferencesAllow(decision,for:binding,owner:owner) && learningAllow(decision,for:binding,owner:owner)
    }
    private func retireLearningProjection(_ epoch:UUID){
        guard let owner=currentOwner,owns(owner),let bridge=owner.presentation.learning else{return}
        let binding=owner.presentation.currentBinding
        let affected=binding.map{bridge.lifetime(for:$0)==epoch} ?? false
        do{try bridge.retire(lifetime:epoch)}catch{if owns(owner){failSession()};return}
        guard affected,let binding,owns(owner) else{return}
        if owner.presentation.panel.snapshot.learningMemoryRevision==bridge.revision(for:binding){
            owner.presentation.panel.withholdGuideAnswer(for:binding,status:"Learning changed. Ask again.")
        }else{owner.presentation.panel.showPendingStatus(for:binding,status:"Learning changed. Ask again.")}
    }
    private func withholdLearning(_ binding:PanelRequestBinding,owner:ConversationOwner){
        guard owns(owner),owner.presentation.currentBinding==binding else{return}
        owner.presentation.panel.withholdGuideAnswer(for:binding,status:"Learning changed. Ask again.")
    }
    var activeLearningExplanation:String?{
        guard let owner=currentOwner,let binding=owner.presentation.currentBinding,let revision=snapshot.learningMemoryRevision else{return nil}
        return owner.presentation.learning?.explanation(for:binding,revision:revision)
    }
    private var retiredResponseLatencySamples:[ResponseLatencySample]=[]
    var responseLatencySamples:[ResponseLatencySample]{Array((retiredResponseLatencySamples+display.panel.latency.samples).suffix(32))}
    private func rememberLatency(_ owner:ConversationOwner){retiredResponseLatencySamples=Array((retiredResponseLatencySamples+owner.presentation.panel.latency.samples).suffix(32))}
    private struct CardCommit {
        let id=UUID(),ownerID:UUID,binding:PanelRequestBinding,replacement:UInt64,card:SessionCard
        let modelAvailableAt:UInt64
        var learningObserved=false
    }
    private var cardCommit:CardCommit?,surfaceObservation:Task<Void,Never>?
    private var windowVisibilityObserver:NSObjectProtocol?
    /// Called only after the outer reducer accept returns, outside authority's
    /// non-recursive lock and after Model's reentrant publication drain.
    private func observeAcceptedCard(_ decision:SessionAnswerDecision,binding:PanelRequestBinding,owner:ConversationOwner){
        guard decision.disposition=="answer",let card=decision.card,owns(owner),currentOwner === owner,
              owner.presentation.currentBinding==binding,owner.authority.snapshot()==binding.lease,
              snapshot.card==card,owner.presentation.panel.snapshot.card==card,
              snapshot.replacement==owner.presentation.panel.snapshot.replacement else{return}
        let now=DispatchTime.now().uptimeNanoseconds
        let marker=CardCommit(ownerID:owner.id,binding:binding,replacement:snapshot.replacement,card:card,modelAvailableAt:now)
        cardCommit=marker
        owner.presentation.panel.latency.recordAvailable(binding:binding,replacement:marker.replacement,availableAt:now,visible:false)
        scheduleSurfaceObservation(marker)
    }
    private func scheduleSurfaceObservation(_ marker:CardCommit?=nil){
        guard let marker=marker ?? cardCommit else{return}
        surfaceObservation?.cancel()
        surfaceObservation=Task{[weak self] in
            await Task.yield()
            guard !Task.isCancelled,let self,!self.publishingPanelSnapshot,self.cardCommit?.id==marker.id,
                  let owner=self.currentOwner,owner.id==marker.ownerID,self.owns(owner),
                  owner.presentation.currentBinding==marker.binding,owner.authority.snapshot()==marker.binding.lease,
                  self.snapshot.card==marker.card,owner.presentation.panel.snapshot.card==marker.card,
                  self.snapshot.replacement==marker.replacement,owner.presentation.panel.snapshot.replacement==marker.replacement,
                  let window=self.window,window.isVisible,!window.isMiniaturized,window.occlusionState.contains(.visible),
                  let scroll=self.answerScrollView,scroll.window === window else{return}
            let now=DispatchTime.now().uptimeNanoseconds
            owner.presentation.panel.latency.recordAvailable(binding:marker.binding,replacement:marker.replacement,availableAt:now,visible:true)
            guard self.cardCommit?.learningObserved==false,owner.kind == .capture,!owner.presentation.explicitRequestIDs.contains(marker.binding.requestID) else{return}
            // Typed requests remain labelled request data, never synthetic audio
            // uptake. Collapsed detail contributes to identity, not uptake text.
            let detail=marker.card.detail.map{"\($0.kind):\($0.language ?? "")\n\($0.text)"}
            self.learning.session.available(binding:marker.binding,replacement:marker.replacement,lead:marker.card.lead,points:marker.card.points,
                detail:detail,guideRevision:self.snapshot.responsePreferencesRevision,visible:true,at:now)
            if self.cardCommit?.id==marker.id{self.cardCommit?.learningObserved=true}
        }
    }
    private func withholdResponsePreferences(_ binding:PanelRequestBinding,owner:ConversationOwner){
        guard owns(owner),owner.presentation.currentBinding==binding else{return}
        owner.presentation.panel.withholdGuideAnswer(for:binding,status:"Response guide changed. Ask again.")
    }
    private func acceptFrame(_ data:Data,owner:ConversationOwner) throws {
        guard owns(owner) else{return}
        let decision=try SessionAnswerDecision(data:data)
        assistant.observeDecision(decision)
        guard let binding=currentBinding,!terminalObserved,
            decision.sessionID==binding.lease.captureSessionID,decision.epoch==binding.lease.sessionEpoch,
            decision.generation==binding.lease.presentationGeneration,decision.requestID==binding.requestID,
            decision.eventSequence==binding.eventSequence else { return }
        if decision.disposition != "pending"{owner.presentation.panel.latency.recordHelperReceived(binding:binding,at:DispatchTime.now().uptimeNanoseconds)}
        guard responsePreferencesAllow(decision,for:binding,owner:owner) else{withholdResponsePreferences(binding,owner:owner);return}
        guard learningAllow(decision,for:binding,owner:owner) else{withholdLearning(binding,owner:owner);return}
        if decision.disposition=="pending",decision.reason=="generating_with_task_context" {
            guard hasContextComposer,contextComposer.ownsCurrent(binding) else { retireDependentRequest(binding);return }
            taskContextUsed=true
            if let use=contextComposer.contextUse { contextStatus="Using "+use.source+(use.provenance=="local_ocr" ? " · local OCR":" · selected text") }
        }
        if decision.disposition != "pending" { terminalObserved=true }
        if decision.disposition=="answer",let use=decision.taskContext {
            guard hasContextComposer,contextComposer.ownsContext(use,for:binding),use.imageDigest==nil || visual.mayOfferImages else { retireDependentRequest(binding);return }
            taskContextUsed=true;imageContextUsed=use.imageDigest != nil
            publication.publish(binding,validate:{ [weak self,weak owner] in guard let self,let owner,self.owns(owner),self.optionalPresentationAllows(decision,for:binding,owner:owner) else{return false};return await self.contextComposer.validateForPublication(binding,requiringImageIdentity:use.imageDigest != nil) },owns:{ [weak self,weak owner] in
                guard let self,let owner,self.owns(owner) else{return false};return self.contextComposer.ownsContext(use,for:binding) && (use.imageDigest==nil || self.visual.mayOfferImages) && self.optionalPresentationAllows(decision,for:binding,owner:owner)
            },commit:{ [weak self,weak owner] in
                guard let self,let owner,self.owns(owner) else{return}
                guard self.responsePreferencesAllow(decision,for:binding,owner:owner) else{self.withholdResponsePreferences(binding,owner:owner);return}
                guard self.learningAllow(decision,for:binding,owner:owner) else{self.withholdLearning(binding,owner:owner);return}
                do { if try self.panel.accept(data) { self.acceptedQuestion=decision.question;self.contextStatus="Used "+use.source+(use.imageDigest != nil ? " · image and local OCR":use.provenance=="local_ocr" ? " · local OCR":" · selected text");self.revealManualAnswer(decision.requestID);self.observeAcceptedCard(decision,binding:binding,owner:owner) } }
                catch { self.failSession() }
            },rejected:{ [weak self,weak owner] in if let self,let owner,self.owns(owner){
                if !self.learningAllow(decision,for:binding,owner:owner){self.withholdLearning(binding,owner:owner)}
                else if self.responsePreferencesAllow(decision,for:binding,owner:owner){self.retireDependentRequest(binding)}
                else{self.withholdResponsePreferences(binding,owner:owner)}
            } })
        } else {
            if try panel.accept(data) { acceptedQuestion=decision.question.isEmpty ? nil:decision.question;if decision.disposition != "pending" { revealManualAnswer(decision.requestID);observeAcceptedCard(decision,binding:binding,owner:owner) } }
            if decision.disposition != "pending" { taskContextUsed=false;contextStatus="";if hasContextComposer { contextComposer.retire() } }
        }
    }
    private func revealManualAnswer(_ requestID:UUID) {
        guard manualRequestToShow==requestID else{return}
        // Ordinary orderFront does not make Relay key or change the source app
        // focus which still owns selected-text evidence.
        window?.orderFront(nil);manualRequestToShow=nil
    }
    private func retireDependentRequest(_ binding:PanelRequestBinding) {
        guard currentBinding==binding else{return}
        if authority.snapshot()==binding.lease { authority.invalidate() }
        retireRequest(status:"Context changed. Ask again.")
    }
    private func retireOptionalWork(notifyHelper:Bool=true) {
        let notified = !notifyHelper || !hasContextComposer || contextComposer.binding.map(enqueueContextRetirement) != false
        if let binding=currentBinding{currentOwner?.presentation.responsePreferences?.retireNative(binding);currentOwner?.presentation.learning?.retireNative(binding)}
        cardCommit=nil;surfaceObservation?.cancel();surfaceObservation=nil
        currentBinding=nil;acceptedQuestion=nil;terminalObserved=true;taskContextUsed=false;imageContextUsed=false;manualRequestToShow=nil
        publication.retire();if hasContextComposer { contextComposer.retire() };if hasSelectedText { selectedText.invalidate() }
        if notifyHelper && notified{forwarder?.cancelOptionalWork()}else{forwarder?.retire()}
        assistant.refresh()
    }
    private func retireRequest(status:String) { retireOptionalWork();panel.clear(status:status) }
    func contextSourceChanged() {
        guard !accountHelperRetiring else{return}
        guard hasContextComposer,let old=contextComposer.binding else { return }
        let used=taskContextUsed && currentBinding==old
        let notified=enqueueContextRetirement(old)
        contextComposer.retire() // source/consent authority retires before helper callbacks
        if used { retireDependentRequest(old) }
        else if notified{forwarder?.cancelOptionalWork()}
        contextStatus="Context changed. The next question can use a fresh observation."
    }
    /// The original staged identity must reach the same bounded writer before
    /// a cancellation callback can release its held EOU. No native restamping.
    @discardableResult private func enqueueContextRetirement(_ old:PanelRequestBinding)->Bool {
        guard !accountHelperRetiring else{return false} // Old helper is already fenced, and will be reaped before any mutation.
        if let previous=lastContextRetirement,previous.0==old{return previous.1}
        let frame:WireValue = .object(["schemaVersion":.uint(1),"kind":.string("supplemental_context_retired"),"captureSessionID":.string(old.lease.captureSessionID.uuidString.lowercased()),"sessionEpoch":.uint(old.lease.sessionEpoch),"presentationGeneration":.uint(old.lease.presentationGeneration),"requestID":.string(old.requestID.uuidString.lowercased()),"reasonCode":.string("context_changed")])
        do {
            guard let helper else{throw PanelBridgeError.closed}
            try helper.sendJSON(JSONEncoder().encode(frame));lastContextRetirement=(old,true);return true
        } catch {
            lastContextRetirement=(old,false)
            // A failed retirement must never release EOU into that child.
            currentOwner?.retireAdmission()
            if currentOwner?.kind == .capture{if fixture{native.beginStop(reason:.transportClosed)}else{capture.retireAdmission(reason:.transportClosed)}}
            helper?.stop();forwarder?.retire()
            let owner=currentOwner
            Task{@MainActor [weak self,weak owner] in
                guard let self,let owner,self.currentOwner === owner else{return};self.failSession()
            }
            return false
        }
    }
    func start() async {
        guard canStartSession else { return }
        if oauth {
            if !fixture {
                guard authorizedConversation else{error="Confirm this is a permitted conversation before starting.";return}
                guard microphoneEnabled || !selectedBundleID.isEmpty else{error="Choose microphone audio or a meeting app before starting.";return}
            }
            let intent=UUID(),microphone=microphoneEnabled,bundle=selectedBundleID,authorized=authorizedConversation
            accountStartIntent=intent
            do{
                try await prepareAccountForExplicitAction(intentID:intent,isCurrent:{[weak self] in
                    guard let self else{return false}
                    return self.accountStartIntent==intent && self.microphoneEnabled==microphone && self.selectedBundleID==bundle
                        && self.authorizedConversation==authorized && !self.running
                })
                try Task.checkCancellation()
                guard accountStartIntent==intent else{throw CancellationError()}
            }catch{
                if accountStartIntent==intent{accountStartIntent=nil;if !(error is CancellationError){self.error=account.message}}
                return
            }
            accountStartIntent=nil
            guard canStartSession else{return}
        }
        starting=true;let identity=UUID();startIdentity=identity
        let task=Task { await self.startOwned(identity:identity) };startTask=task
        await task.value
        if startIdentity==identity { startTask=nil }
    }
    func cancelPreparation(){
        if assistant.snapshot.isPreparing{assistant.cancelPreparation();return}
        guard starting || speechSetup.snapshot.isBusy || accountPreparationActive else{return}
        beginRetirement(end:false)
        paused=false;panel.clear(status:"Preparation cancelled")
    }
    func retryPreparation()async{await start()}
    private func ownsStart(_ identity:UUID)->Bool{startIdentity==identity && !Task.isCancelled && !stopping}
    private func restoreHistoryForStart(_ identity:UUID,sourceIsCurrent:@escaping @MainActor ()->Bool)async->Bool{
        do{
            if hasLearning{await learning.waitForQuiescence();guard ownsStart(identity),sourceIsCurrent() else{return false}}
            let coordinator=history
            let permit=try await coordinator.beginSession(intentID:identity,resuming:paused,isCurrent:{[weak self] in self?.ownsStart(identity)==true && sourceIsCurrent()})
            guard ownsStart(identity),sourceIsCurrent(),!coordinator.isBusy,
                  permit.map({coordinator.owns($0)}) ?? !coordinator.savingEnabled else{
                if let permit{coordinator.retireCurrentSession();try? await coordinator.finishSession(permit,paused:false)}
                return false
            }
            historyPermit=permit
            _=try? await learning.restore()
            return ownsStart(identity) && sourceIsCurrent() && (permit.map({coordinator.owns($0)}) ?? !coordinator.savingEnabled)
        }catch{
            if ownsStart(identity){
                if case HistoryError.inUse=error{self.error="Local history is in use. Close or lock another Relay app, or turn saving off here before starting."}
                else{self.error="Local history could not open. Open History to retry, or turn saving off and start again."}
            }
            return false
        }
    }
    private func restoreContextForStart(_ identity:UUID,sourceIsCurrent:@escaping @MainActor ()->Bool)async->Bool{
        let use=contextUse
        guard use.useInSessions else{return !use.isBusy && profileStorage?.busy != true && ownsStart(identity) && sourceIsCurrent()}
        guard let target=profileTarget() else{error="Saved context is unavailable. Open My Context, or lock it and retry.";return false}
        let result=await use.restoreBeforeSession(target:target,startIntentID:identity,isStartCurrent:{[weak self] in
            self?.ownsStart(identity)==true && sourceIsCurrent()
        })
        guard ownsStart(identity),sourceIsCurrent() else{return false}
        guard result == .ready,use.useInSessions,!use.isBusy,target.controller.opened,!target.controller.busy,
              profileStorage === target.controller,let binding=profileBinding,binding.id==target.bindingID,!binding.retired,
              binding.helper === helper else{
            error=result == .missing || result == .unavailable ? use.snapshot.message:"Saved context changed while starting. Start again, or open My Context."
            return false
        }
        return true
    }
    private func startOwned(identity:UUID) async {
        defer { if startIdentity==identity { starting=false } }
        guard !running,!stopping else{return};error=nil
        if let owner=currentOwner,owner.kind == .assistant{await closeAssistantScope(owner)}
        guard ownsStart(identity),currentOwner==nil else{return}
        var captureAttempted=false
        var preparingManaged=false
        do {
            if !fixture && capture.phase != .idle { error="Waiting for capture to finish stopping.";return }
            if fixture {
                guard await restoreContextForStart(identity,sourceIsCurrent:{true}) else{return}
                guard await restoreHistoryForStart(identity,sourceIsCurrent:{true}) else{return}
                let transport=try ensureHelper();try installCaptureOwner(transport);try startFixture();return
            }
            guard authorizedConversation else {
                error="Confirm this is a permitted conversation before starting.";return
            }
            let microphone=microphoneEnabled,bundle=selectedBundleID
            guard (microphone || !bundle.isEmpty),(bundle.isEmpty || SelectedAppProcesses.isValidBundleID(bundle)) else {
                error="Choose microphone audio or a meeting app before starting.";return
            }
            let configuration:NativeCaptureConfiguration
            if !asrFolder.isEmpty || !vadFolder.isEmpty {
                guard !asrFolder.isEmpty,!vadFolder.isEmpty,modelLicensesAcknowledged else{throw SpeechSetupError.advancedOverrideInvalid}
                configuration=NativeCaptureConfiguration(microphoneEnabled:microphone,selectedBundleID:bundle.isEmpty ? nil:bundle,asrModelRoot:URL(fileURLWithPath:asrFolder),vadCompiledModel:URL(fileURLWithPath:vadFolder),authorizedConversation:true,localModelLicensesAcknowledged:modelLicensesAcknowledged)
            }else{
                preparingManaged=true
                let assets=try await speechSetup.prepare()
                preparingManaged=false
                guard ownsStart(identity) else{throw CancellationError()}
                configuration=NativeCaptureConfiguration(microphoneEnabled:microphone,selectedBundleID:bundle.isEmpty ? nil:bundle,preparedSpeechAssets:assets,authorizedConversation:authorizedConversation)
            }
            guard ownsStart(identity) else{throw CancellationError()}
            guard authorizedConversation,microphoneEnabled==microphone,selectedBundleID==bundle else{
                error="Audio choices changed during preparation. Check them and start again.";return
            }
            try configuration.validateLocalModels()
            try await responsePreferences.prepareForExplicitAction(intentID:identity,isCurrent:{[weak self] in self?.ownsStart(identity)==true})
            guard ownsStart(identity),!responsePreferences.isBusy else{throw CancellationError()}
            guard await restoreContextForStart(identity,sourceIsCurrent:{[weak self] in
                guard let self else{return false}
                return self.authorizedConversation && self.microphoneEnabled==microphone && self.selectedBundleID==bundle
            }) else{return}
            guard await restoreHistoryForStart(identity,sourceIsCurrent:{[weak self] in
                guard let self else{return false}
                return self.authorizedConversation && self.microphoneEnabled==microphone && self.selectedBundleID==bundle
            }) else{return}
            let transport=try ensureHelper();try installCaptureOwner(transport);captureAttempted=true
            try await capture.start(configuration:configuration)
            guard ownsStart(identity) else{throw CancellationError()}
            running=capture.phase == .running;paused=false
            refreshAssistantAfterStart()
        } catch is CancellationError { if ownsStart(identity){panel.clear(status:"Stopped")} }
        catch {
            guard ownsStart(identity) else{return}
            if captureAttempted || fixture {
                failSession()
                self.error="Audio could not start. Check microphone and meeting-app access, then start again."
            }else{
                self.error=preparingManaged ? speechSetup.snapshot.userMessage:
                    ((error as? SpeechSetupError)?.localizedDescription ?? SpeechSetupError.advancedOverrideInvalid.localizedDescription)
            }
        }
        if !running,let permit=historyPermit,permit.intentID==identity{
            history.retireCurrentSession();try? await history.finishSession(permit,paused:false)
            if historyPermit === permit{historyPermit=nil}
        }
    }
    private func startFixture() throws {
        if let fixtureSessionStart{
            try fixtureSessionStart(native);running=true;paused=false;refreshAssistantAfterStart();return
        }
        let question:String
        if fixtureSuite=="personal-memory" {question="What did you personally do on your Fictional Northstar project?"}
        else{question=fixtureSuite=="coding" ? "Write a Python function that returns the first item or None for an empty list." : fixtureSuite=="case" ? "Case study: design a feature for nurse handoffs. What user needs would you clarify first?":"What is the difference between WHERE and HAVING?"}
        let microphoneFixture=fixtureSuite=="microphone-source-failure"
        let source:PCMSource=microphoneFixture ? .microphone:.remoteAudio
        try native.start(selectedBundleID:microphoneFixture ? nil:"com.example.fixture",microphoneEnabled:microphoneFixture,
            components:[source.rawValue:SourceComponents(vad:FixtureVAD(),recognizer:FixtureRecognizer([question],fails:fixtureSuite=="source-failure" || microphoneFixture))])
        running=true;paused=false
        refreshAssistantAfterStart()
        let clock=NativeClockCalibration.now()
        let start=mach_absolute_time()-UInt64(2_000_000_000)*UInt64(clock.nsDenom)/UInt64(clock.nsNumer)
        for sequence:UInt64 in 1...2 {
            ingestFixturePacket(SessionAudioPacket(source:source,streamGeneration:1,sequence:sequence,hostTime:start+(sequence-1)*UInt64(32_000_000)*UInt64(clock.nsDenom)/UInt64(clock.nsNumer),samples:Array(repeating:0.2,count:512)))
        }
    }
    func ingestFixturePacket(_ packet:SessionAudioPacket){guard fixture else{return};native.ingest(packet)}
    private func refreshAssistantAfterStart(){
        assistant.refresh()
        guard running,let currentBinding else{return}
        if !terminalObserved{assistant.observeRequest(currentBinding)}
        if let acceptedQuestion{assistant.recordQuestion(currentBinding,question:acceptedQuestion)}
    }
    var currentSessionID:UUID?{authority.snapshot()?.captureSessionID ?? forwardedSessionID}
    var canStartSession:Bool {
        guard case .success=helperRuntime else{return false}
        return !running && !starting && !stopping && !assistantClosing && !assistant.snapshot.isPreparing && !accountMutationOwned && teardown==nil && !speechSetup.snapshot.isBusy && !visual.isBusy && visual.status != .busy && profileStorage?.busy != true && !(hasContextUse && contextUse.isBusy) && !(hasHistory && history.isBusy) && !(hasResponsePreferences && responsePreferences.isBusy) && (fixture || capture.phase == .idle)
    }
    var canResume:Bool { paused && canStartSession }
    var canEnableHistory:Bool{(!fixture || historyStorageFactory != nil) && !running && !starting && !stopping && !paused && !assistantActive && !assistantClosing && !assistant.snapshot.isPreparing && !accountMutationOwned && !speechSetup.snapshot.isBusy && !visual.isBusy && !(hasResponsePreferences && responsePreferences.isBusy)}
    var canEnableLearning:Bool{canEnableHistory && (!fixture || (historyStorageFactory != nil && learningPreferencesOverride != nil))}
    func beginRetirement(end:Bool,historyGap:HistoryGap?=nil) {
        denyAccountStart()
        endRequested = endRequested || end
        if end{paused=false}
        startIdentity=UUID();speechSetup.cancel();assistant.cancelPreparation()
        guard teardown==nil else{disableVisualInput();return}
        let oldOwner=currentOwner,oldHelper=helper,oldBinding=profileBinding
        let oldHistory=hasHistory ? history:nil
        let activity=assistant.transcript.snapshot
        let unfinished=[activity.microphone,activity.selectedAudio].contains{value in switch value{case .speechDetected,.transcribing:true;default:false}}
        let oldHistoryPermit=oldHistory?.retireCurrentSession(gap:historyGap ?? (unfinished ? .unfinishedSpeech:nil))
        let sessionID=oldOwner?.kind == .capture ? forwardedSessionID:nil
        let oldStart=startTask;oldStart?.cancel()
        // Source/assistant admission retires before cancellation can flush an
        // old optional frame. The exact original owner survives through join.
        let scopeClose:Task<Void,Never>?
        if let oldOwner,oldOwner.kind == .assistant{scopeClose=beginClosingAssistantScope(oldOwner)}
        else{
            scopeClose=nil
            if oldOwner?.kind == .capture {
                if fixture{native.beginStop()}else{capture.retireAdmission(reason:.userStop)}
                oldOwner?.retireAdmission()
            }
            if hasContextComposer,let old=contextComposer.binding{enqueueContextRetirement(old)}
            disableVisualInput();retireRequest(status:end ? "Stopped":"Paused · recent conversation will reset on resume")
        }
        if hasLearning{if endRequested{learning.endSession()}else{learning.pauseSession()}}
        cardCommit=nil;surfaceObservation?.cancel();surfaceObservation=nil
        running=false;assistantActive=false;paused = !end;stopping=true
        if end{assistant.transcript.end()}else{assistant.transcript.pause()}
        assistant.refresh()
        let oldContextUse=hasContextUse ? contextUse:nil
        oldContextUse?.retireForHelperChange()
        teardown=Task{[weak self] in
            guard let self else{return}
            await self.speechSetup.waitForQuiescence();await oldStart?.value
            await self.assistant.waitForPreparationQuiescence()
            await oldContextUse?.waitForQuiescence()
            if oldOwner?.kind == .capture {
                if self.fixture{await self.native.waitForQuiescence();self.native.finishStop(quiesced:true)}
                else{
                    await self.capture.stop(reason:.userStop)
                    while self.capture.phase != .idle{try? await Task.sleep(for:.milliseconds(10))}
                }
            }
            await self.events.drain();await self.visual.waitForQuiescence();await scopeClose?.value
            do{
                if let sessionID,let oldHelper{try await oldHelper.requestSessionQuiescence(sessionID:sessionID,epoch:1)}
            }catch{
                self.endRequested=true;self.paused=false
                self.error="The old helper did not acknowledge shutdown. Its profile was retired; reopen background to recover."
            }
            if let oldHistory,let oldHistoryPermit{
                do{
                    try await oldHistory.finishSession(oldHistoryPermit,paused:!self.endRequested)
                    // End may escalate a Pause while its actual history save is
                    // in flight. Finish the SAME still-current private permit;
                    // a concurrent Lock/replacement never regains ownership.
                    if self.endRequested,oldHistory.owns(oldHistoryPermit),oldHistory.hasPausedSession{
                        oldHistory.retireCurrentSession()
                        try await oldHistory.finishSession(oldHistoryPermit,paused:false)
                    }
                }
                catch{self.error="Local history could not finish saving. Open History to recover its saved prefix."}
                if self.historyPermit === oldHistoryPermit{self.historyPermit=nil}
            }
            if self.hasLearning{await self.learning.waitForQuiescence()}
            if let oldOwner,self.currentOwner === oldOwner {
                oldOwner.presentation.forwarder?.retire();oldOwner.presentation.composer?.retire();oldOwner.presentation.publication.retire();oldOwner.presentation.responsePreferences?.close();oldOwner.presentation.learning?.close()
                self.rememberLatency(oldOwner);self.owners.remove(oldOwner)
            }
            if self.endRequested {
                if let profile=self.profileStorage,profile.opened || profile.busy{await profile.close()}
                if let oldHelper {
                    if self.helper === oldHelper{self.helper=nil;self.helperIdentity=UUID();self.owners.activateHelper(self.helperIdentity)}
                    oldBinding?.retired=true
                    await oldHelper.shutdownAndWait()
                }
                if self.profileBinding === oldBinding{self.profileBinding=nil;self.profileStorage=nil}
                self.endRequested=false;self.paused=false
            }
            self.startTask=nil;self.starting=false;self.assistantClosing=false;self.stopping=false;self.teardown=nil
            self.assistant.refresh()
        }
    }
    func stop() async { beginRetirement(end:true);await teardown?.value;await accountStartCancellation?.value }
    func shutdown()async{await stop();if hasLearning{await learning.waitForQuiescence()};if hasHistory{await history.closeForOwnerRetirement()};await accountStorageController?.close()}
    func failSession() {
        // Keep the same actual owner join/reap barrier as End. A failed source
        // or transport cannot be replaced merely because its output is hidden.
        helper?.stop() // Fence the child before any local image-retirement callback.
        visual.retireForHelperChange()
        helperIdentity=UUID();owners.activateHelper(helperIdentity)
        beginRetirement(end:true,historyGap:.captureFailure)
        authority.stop();retireRequest(status:"Session unavailable")
        forwarder?.retire();forwarder=nil;running=false;paused=false
        error="The session ended. Restart after the previous session finishes."
    }
    func perform(_ action:ControlAction)throws {
        switch action {
        case .pause:guard running || starting || assistantActive || assistant.snapshot.isPreparing else { throw ControlsError.actionFailed(action) };beginRetirement(end:false)
        case .endSession:beginRetirement(end:true)
        case .resume:guard canResume else { throw ControlsError.actionFailed(action) };Task { await start() }
        case .requestHelp:
            if let currentBinding,explicitRequestIDs.contains(currentBinding.requestID){assistant.requestCurrentQuestionHelp();return}
            guard running,!stopping,forwarder?.isIdle != false,let question=acceptedQuestion,let lease=authority.snapshot() else { error="Ask a question first.";window?.makeKeyAndOrderFront(nil);return }
            let queue=events
            do {
                _=try (fixture ? native:capture.controller).issueManualHelp(expectedEventSequence:lastForwardedSequence,expectedLease:lease,question:question,enqueue:{ [weak self] request in
                    try queue.enqueue(.session(.manual(request))) { [weak self] value in
                        guard let self,let owner=self.currentOwner,owner.matches(request.lease.captureSessionID,epoch:request.lease.sessionEpoch) else{return}
                        self.receiveApplication(value,owner:owner)
                    }
                })
            } catch { self.error="The discussion changed. Help will be available after the current question." }
        default:throw ControlsError.actionFailed(action)
        }
    }
    func setSelectedTextEnabled(_ enabled:Bool,requestPermission:Bool=true) {
        contextSourceChanged()
        do {
            if enabled { try selectedText.enable(allowedBundleIDs:selectedTextBundleID.isEmpty ? []:[selectedTextBundleID],requestPermission:requestPermission) }
            else { selectedText.revoke() }
        } catch { self.error=error.localizedDescription }
    }
    func chooseSelectedTextApp(_ bundleID:String) {
        contextSourceChanged()
        if hasSelectedText { selectedText.revoke() }
        selectedTextBundleID=bundleID
    }
    private func visualSender(_ transport:HelperTransport)->VisualInputControlSender {
        {action,update in try await transport.requestVisualInput(action,onUpdate:update)}
    }
    var canTestVisualInput:Bool { !fixture && oauth && canStartSession && profileStorage?.busy != true }
    func beginVisualVerification() {
        guard canTestVisualInput else{return}
        do{visual.beginVerification(using:visualSender(try ensureHelper()))}catch{failSession()}
    }
    func disableVisualInput(){
        guard visual.needsDisable,!visual.hasPendingDisable,let helper else{visual.disable(using:nil);return}
        do {
            let response=try helper.issueVisualInput(.disable,onUpdate:{_ in})
            visual.disable(using:{_,_ in try await response.value()})
        }catch{
            helper.stop()
            // Register the failed join before local retirement callbacks;
            // the existing state error path performs actual session teardown.
            visual.disable(using:{_,_ in throw error})
        }
    }
    private func retireVisualImages() {
        guard hasContextComposer else{return}
        contextComposer.retireImageOffer()
        if imageContextUsed,let binding=currentBinding{retireDependentRequest(binding)}
        else{forwarder?.cancelOptionalWork()}
    }
    var canChangeAIMode:Bool { (!fixture || accountPortsOverride != nil) && canStartSession && profileStorage?.busy != true }
    func setAIEnabled(_ enabled:Bool) async {
        guard canChangeAIMode,enabled != oauth else { return }
        error=nil;await account.setAIEnabled(enabled)
        contextStatus=oauth ? "Using ChatGPT plan":"AI is off. Local reference cards remain available."
    }
    /// Navigation only. Showing the existing account controller performs no
    /// readiness or authorization; its explicit login action remains separate.
    func showAISettings(openWindow:()->Void){settingsSection = .ai;openWindow()}
    func showLearningSettings(openWindow:()->Void){settingsSection = .learning;openWindow()}
    func performWindowAction(_ action:ControlAction) {
        do { try windowActions.perform(action) } catch { self.error=error.localizedDescription }
    }
    func attachWindow(_ window:NSWindow,scrollView:NSScrollView?) {
        self.window=window;if let scrollView { answerScrollView=scrollView }
        windowActions.panel=OwnPanelControls(window:window,sessionActions:hostActions,answerText:{ [weak self] in self?.currentAnswerText() },expandAnswer:{ [weak self] in self?.expanded=true },scrollAnswer:{ [weak self] delta in self?.scrollAnswer(delta) })
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:window,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { try? self.controls.setEnabled(false);self.beginRetirement(end:true) } }
        }
        if let windowVisibilityObserver{NotificationCenter.default.removeObserver(windowVisibilityObserver)}
        windowVisibilityObserver=NotificationCenter.default.addObserver(forName:NSWindow.didChangeOcclusionStateNotification,object:window,queue:.main){[weak self] _ in
            MainActor.assumeIsolated{self?.scheduleSurfaceObservation()}
        }
        scheduleSurfaceObservation()
    }
    private func currentAnswerText()->String? {
        guard (running || assistantActive),!stopping,let binding=currentBinding,authority.snapshot()==binding.lease,let card=snapshot.card else{return nil}
        return ([card.lead]+card.points+(card.detail.map{[$0.text]} ?? [])).joined(separator:"\n\n")
    }
    private func scrollAnswer(_ delta:Double) {
        guard let scroll=answerScrollView,let document=scroll.documentView else{return}
        let visible=scroll.contentView.bounds
        let y=min(max(visible.origin.y+delta,0),max(document.bounds.height-visible.height,0))
        scroll.contentView.scroll(to:NSPoint(x:visible.origin.x,y:y));scroll.reflectScrolledClipView(scroll.contentView)
    }
    func restoreShortcuts() {
        guard !fixture,let data=UserDefaults.standard.data(forKey:"relay.shortcut-choices.v1"),let saved=try? JSONDecoder().decode([String:ControlShortcut].self,from:data) else{return}
        for (key,value) in saved { if let action=ControlAction(rawValue:key) { try? controls.configure(value,for:action) } }
    }
    func saveShortcuts() {
        guard !fixture else{return}
        let choices=Dictionary(uniqueKeysWithValues:controls.shortcuts.map{($0.key.rawValue,$0.value)})
        if let data=try? JSONEncoder().encode(choices) { UserDefaults.standard.set(data,forKey:"relay.shortcut-choices.v1") }
    }
}
