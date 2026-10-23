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

private final class MainEventQueue: @unchecked Sendable {
    private let lock=NSLock();private var count=0;private var bytes=0
    private var waiters:[CheckedContinuation<Void,Never>]=[]
    func enqueue(_ ingress:SessionIngress,action:@escaping @MainActor @Sendable(SessionIngress)->Void) throws {
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
    var retired=false
    var helper:HelperTransport?
    func shutdown() async {
        retired=true
        await helper?.shutdownAndWait()
    }
}

@MainActor final class SessionApplicationModel: ObservableObject {
    @Published private(set) var snapshot=SessionPanelSnapshot()
    @Published private(set) var running=false
    @Published private(set) var starting=false
    @Published private(set) var paused=false
    @Published private(set) var stopping=false
    @Published private(set) var contextStatus=""
    @Published var expanded=false
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
    private let authority=SessionPresentationAuthority()
    private let contextCoordinatorOverride:ScreenContextCoordinator?
    private let contextWriteAcknowledged:(@MainActor (Data,PanelRequestBinding) async ->Void)?
    private let ingressEnqueued:(@MainActor (SessionIngress)->Void)?
    let screen=ScreenContextModel()
    let visual=VisualInputSetupState()
    let speechSetup:SpeechSetupCoordinator
    private var hasSelectedText=false
    lazy var selectedText:SelectedTextService = {
        hasSelectedText=true
        return SelectedTextService(currentRequest:{ [weak self] in
            guard let self,let request=self.currentBinding,self.authority.snapshot()==request.lease else { return nil }
            return SelectionRequestIdentity(sessionID:request.lease.captureSessionID,sessionEpoch:request.lease.sessionEpoch,presentationGeneration:request.lease.presentationGeneration,requestID:request.requestID)
        })
    }()
    private var hasContextComposer=false
    private lazy var contextComposer:QuestionContextComposer = {
        hasContextComposer=true
        return QuestionContextComposer(authority:authority,screen:contextCoordinatorOverride ?? screen.coordinator,selection:selectedText)
    }()
    private lazy var publication=ContextPublicationGate(authority:authority)
    private var forwarder:OrderedContextForwarder?
    private var currentBinding:PanelRequestBinding?
    private var lastContextRetirement:(PanelRequestBinding,Bool)?
    private var acceptedQuestion:String?
    private var terminalObserved=false
    private var taskContextUsed=false
    private var imageContextUsed=false
    private var manualRequestToShow:UUID?
    private var lastForwardedSequence:UInt64=0
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
    private let helperFailures=HelperFailureGate()
    private lazy var panel:SessionPanelController = {
        let panel=SessionPanelController(authority:authority)
        panel.onChange={ [weak self,weak panel] in if let panel { self?.snapshot=panel.snapshot } }
        return panel
    }()
    private lazy var native:NativeSessionController = {
        let queue=events
        return NativeSessionController(authority:authority,onEvent:{ [weak self] event in
            try queue.enqueue(.audio(event)) { [weak self] in self?.receive($0) }
        })
    }()
    private lazy var capture:NativeCaptureSession = {
        let queue=events
        return NativeCaptureSession(authority:authority,onEvent:{ [weak self] event in
            try queue.enqueue(.audio(event)) { [weak self] in self?.receive($0) }
        })
    }()
    private var profileStorage:ProfileController?
    private var profileBinding:SharedProfileBinding?
    private var forwardedSessionID:UUID?
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
        let directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Relay",isDirectory:true)
        let controller=ProfileController(client:ProfileClient(port:port),vault:ProfileVault(directory:directory),onInvalidate:{ [weak self] in
            guard let self else { return };self.retireRequest(status:"Background updated");self.authority.invalidate()
        })
        profileStorage=controller;return controller
    }
    private func profileRequest(_ data:Data,binding:SharedProfileBinding) async throws -> Data {
        guard !binding.retired,profileBinding === binding else { throw PanelBridgeError.closed }
        let transport:HelperTransport
        if let bound=binding.helper { transport=bound }
        else { transport=try ensureHelper();binding.helper=transport }
        return try await transport.requestProfile(data)
    }
    private func shutdownProfile(_ binding:SharedProfileBinding) async {
        binding.retired=true
        if let old=binding.helper,old === helper {
            // Close all old admission before the first await. Queued frames and
            // source events cannot cross into a replacement helper lifecycle.
            if fixture { native.beginStop() } else { capture.retireAdmission(reason:.transportClosed) }
            retireOptionalWork();authority.stop();helperIdentity=UUID();helperFailures.activate(helperIdentity)
            visual.retireForHelperChange()
            forwardedSessionID=nil;helper=nil;running=false;paused=false
            panel.clear(status:"Profile unavailable");error="Profile could not be locked. Its helper was stopped. Reopen background to recover."
            old.stop()
            if fixture { await native.waitForQuiescence();native.finishStop(quiesced:true) }
            else { await capture.stop(reason:.transportClosed) }
        }
        await binding.shutdown()
        if profileBinding === binding { profileBinding=nil;profileStorage=nil }
    }

    init(arguments:[String]=CommandLine.arguments,contextCoordinator:ScreenContextCoordinator?=nil,
         contextWriteAcknowledged:(@MainActor (Data,PanelRequestBinding) async ->Void)?=nil,
         ingressEnqueued:(@MainActor (SessionIngress)->Void)?=nil,
         speechSetup:SpeechSetupCoordinator?=nil,
         bundleURL:URL=Bundle.main.bundleURL,
         workingDirectory:URL=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)) {
        self.speechSetup=speechSetup ?? SpeechSetupCoordinator()
        self.contextCoordinatorOverride=contextCoordinator
        self.contextWriteAcknowledged=contextWriteAcknowledged;self.ingressEnqueued=ingressEnqueued
        fixture=arguments.contains("--fixture-suite")
        fixtureSuite=Self.argument("--fixture-suite",arguments) ?? "reviewed"
        role=Self.argument("--role",arguments) ?? (fixture ? "analytics":"developer")
        oauth=arguments.contains("--oauth") && !fixture
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
        if let focusObserver { NSWorkspace.shared.notificationCenter.removeObserver(focusObserver) }
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        if let helper { helper.stop();Task.detached { await helper.shutdownAndWait() } }
    }
    private static func argument(_ key:String,_ args:[String]) -> String? { guard let i=args.firstIndex(of:key),args.indices.contains(i+1) else { return nil };return args[i+1] }
    func ensureHelper() throws -> HelperTransport {
        guard !stopping,profileBinding?.retired != true else { throw PanelBridgeError.closed }
        if let helper { return helper }
        let runtime=try helperRuntime.get()
        visual.retireForHelperChange()
        let identity=UUID();helperIdentity=identity;helperFailures.activate(identity)
        let nativeAuthority=authority;let failures=helperFailures;let delivery=answers
        let sourceController=fixture ? native:capture.controller
        let helper=HelperTransport(root:runtime.resourceRoot,python:runtime.executable,pythonArguments:runtime.arguments,mode:fixture ? .fixture:oauth ? .oauth:.noInference,role:role,onFrame:{ [weak self] data in
            try delivery.enqueue(data,byteCount:data.count) { [weak self] data in
                guard let self,self.helperIdentity==identity else { return }
                do { try self.acceptFrame(data) } catch { self.failSession() }
            }
        },onFailure:{ [weak self] in
            guard failures.withCurrent(identity,perform:{ sourceController.retire();nativeAuthority.stop() }) else { return }
            Task { @MainActor in guard let self,self.helperIdentity==identity else { return };self.failSession() }
        })
        try helper.start();self.helper=helper;return helper
    }
    func receive(_ ingress:SessionIngress) {
        guard helper != nil else { return }
        switch ingress {
        case .audio(let event):
            if event.kind == .sessionStarted {
                guard authority.snapshot()?.captureSessionID==event.captureSessionID else { return }
                forwardedSessionID=event.captureSessionID;lastForwardedSequence=0
            }
            guard forwardedSessionID==event.captureSessionID else { return }
            if let active=authority.snapshot(),active.captureSessionID != event.captureSessionID { return }
            if !stopping && ([.stopping,.stopped].contains(event.kind)
                || (event.sourceCode==2 && [.sourceUnavailable,.discontinuity].contains(event.kind))) {
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
        do { try eventForwarder().enqueue(ingress) } catch { failSession() }
    }
    private func eventForwarder()->OrderedContextForwarder {
        if let forwarder { return forwarder }
        let created=OrderedContextForwarder(shouldCapture:{ [weak self] ingress in
            guard let self,let binding=ingress.binding,self.authority.snapshot()==binding.lease,self.running,!self.stopping else { return false }
            if self.contextCoordinatorOverride?.isEnabled ?? self.screen.isEnabled { return true }
            if case .manual=ingress { return self.selectedText.isEnabled }
            return false
        },capture:{ [weak self] ingress in
            guard let self,let binding=ingress.binding else { return [] }
            self.bind(binding)
            let deadline=DispatchTime.now().uptimeNanoseconds+1_500_000_000
            var writer:(@MainActor (Data) async throws ->Void)?
            if let generation=self.visual.offerGeneration,let helper=self.helper {
                let helperID=self.helperIdentity
                writer={ [weak self] data in
                    try await helper.sendJSONAwaitingWrite(data,deadline:deadline,isCurrent:{ [weak self] in
                        guard let self else{return false}
                        return self.helperIdentity==helperID && self.helper === helper && self.currentBinding==binding
                            && self.visual.ownsOfferGeneration(generation) && self.contextComposer.ownsCurrent(binding)
                    })
                    await self?.contextWriteAcknowledged?(data,binding)
                }
            }
            return await self.contextComposer.captureForForwarding(for:binding,readSelectedText:{if case .manual=ingress{return true};return false}(),imageWriter:writer)
        },send:{ [weak self] ingress,frames in try self?.send(ingress,context:frames) },onFailure:{ [weak self] in self?.failSession() })
        forwarder=created;return created
    }
    private func bind(_ request:PanelRequestBinding) {
        guard authority.snapshot()==request.lease,currentBinding != request else { return }
        currentBinding=request;lastContextRetirement=nil;terminalObserved=false;taskContextUsed=false;imageContextUsed=false
        publication.bind(request);panel.bind(request)
    }
    private func send(_ ingress:SessionIngress,context:[Data]) throws {
        guard let helper else { throw PanelBridgeError.closed }
        if let binding=ingress.binding { bind(binding) }
        for frame in context { try helper.sendJSON(frame) }
        switch ingress {
        case .audio(let event):
            try helper.send(event);lastForwardedSequence=event.eventSequence
            if event.kind != .eou { panel.observe(event) }
        case .manual(let request):try helper.sendJSON(request.encodedJSON())
        }
        ingressEnqueued?(ingress)
    }
    private func acceptFrame(_ data:Data) throws {
        let decision=try SessionAnswerDecision(data:data)
        guard let binding=currentBinding,!terminalObserved,
            decision.sessionID==binding.lease.captureSessionID,decision.epoch==binding.lease.sessionEpoch,
            decision.generation==binding.lease.presentationGeneration,decision.requestID==binding.requestID,
            decision.eventSequence==binding.eventSequence else { return }
        if decision.disposition=="pending",decision.reason=="generating_with_task_context" {
            guard hasContextComposer,contextComposer.ownsCurrent(binding) else { retireDependentRequest(binding);return }
            taskContextUsed=true
            if let use=contextComposer.contextUse { contextStatus="Using "+use.source+(use.provenance=="local_ocr" ? " · local OCR":" · selected text") }
        }
        if decision.disposition != "pending" { terminalObserved=true }
        if decision.disposition=="answer",let use=decision.taskContext {
            guard hasContextComposer,contextComposer.ownsContext(use,for:binding),use.imageDigest==nil || visual.mayOfferImages else { retireDependentRequest(binding);return }
            taskContextUsed=true;imageContextUsed=use.imageDigest != nil
            publication.publish(binding,validate:{ [weak self] in guard let self else{return false};return await self.contextComposer.validateForPublication(binding,requiringImageIdentity:use.imageDigest != nil) },owns:{ [weak self] in
                guard let self else{return false};return self.contextComposer.ownsContext(use,for:binding) && (use.imageDigest==nil || self.visual.mayOfferImages)
            },commit:{ [weak self] in
                guard let self else{return}
                do { if try self.panel.accept(data) { self.acceptedQuestion=decision.question;self.contextStatus="Used "+use.source+(use.imageDigest != nil ? " · image and local OCR":use.provenance=="local_ocr" ? " · local OCR":" · selected text");self.revealManualAnswer(decision.requestID) } }
                catch { self.failSession() }
            },rejected:{ [weak self] in self?.retireDependentRequest(binding) })
        } else {
            if try panel.accept(data) { acceptedQuestion=decision.question.isEmpty ? nil:decision.question;if decision.disposition != "pending" { revealManualAnswer(decision.requestID) } }
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
    private func retireOptionalWork() {
        let notified = !hasContextComposer || contextComposer.binding.map(enqueueContextRetirement) != false
        currentBinding=nil;acceptedQuestion=nil;terminalObserved=true;taskContextUsed=false;imageContextUsed=false;manualRequestToShow=nil
        publication.retire();if hasContextComposer { contextComposer.retire() };if hasSelectedText { selectedText.invalidate() }
        if notified{forwarder?.cancelOptionalWork()}else{forwarder?.retire()}
    }
    private func retireRequest(status:String) { retireOptionalWork();panel.clear(status:status) }
    func contextSourceChanged() {
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
        if let previous=lastContextRetirement,previous.0==old{return previous.1}
        let frame:WireValue = .object(["schemaVersion":.uint(1),"kind":.string("supplemental_context_retired"),"captureSessionID":.string(old.lease.captureSessionID.uuidString.lowercased()),"sessionEpoch":.uint(old.lease.sessionEpoch),"presentationGeneration":.uint(old.lease.presentationGeneration),"requestID":.string(old.requestID.uuidString.lowercased()),"reasonCode":.string("context_changed")])
        do {
            guard let helper else{throw PanelBridgeError.closed}
            try helper.sendJSON(JSONEncoder().encode(frame));lastContextRetirement=(old,true);return true
        } catch {
            lastContextRetirement=(old,false)
            // A failed retirement must never release EOU into that child.
            if fixture{native.beginStop(reason:.transportClosed)}else{capture.retireAdmission(reason:.transportClosed)}
            authority.stop();helper?.stop();forwarder?.retire()
            Task{@MainActor [weak self] in self?.failSession()}
            return false
        }
    }
    func start() async {
        guard canStartSession else { return }
        starting=true;let identity=UUID();startIdentity=identity
        let task=Task { await self.startOwned(identity:identity) };startTask=task
        await task.value
        if startIdentity==identity { startTask=nil }
    }
    func cancelPreparation(){
        guard starting || speechSetup.snapshot.isBusy else{return}
        beginRetirement(end:false)
        paused=false;panel.clear(status:"Preparation cancelled")
    }
    func retryPreparation()async{await start()}
    private func ownsStart(_ identity:UUID)->Bool{startIdentity==identity && !Task.isCancelled && !stopping}
    private func startOwned(identity:UUID) async {
        defer { if startIdentity==identity { starting=false } }
        guard !running,!stopping else { return };error=nil
        var captureAttempted=false
        var preparingManaged=false
        do {
            if !fixture && capture.phase != .idle { error="Waiting for capture to finish stopping.";return }
            if fixture { _=try ensureHelper();try startFixture();return }
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
            _=try ensureHelper();captureAttempted=true
            try await capture.start(configuration:configuration)
            guard ownsStart(identity) else{throw CancellationError()}
            running=capture.phase == .running;paused=false
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
    }
    private func startFixture() throws {
        let question=fixtureSuite=="coding" ? "Write a Python function that returns the first item or None for an empty list." : fixtureSuite=="case" ? "Case study: design a feature for nurse handoffs. What user needs would you clarify first?":"What is the difference between WHERE and HAVING?"
        try native.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,components:[2:SourceComponents(vad:FixtureVAD(),recognizer:FixtureRecognizer([question],fails:fixtureSuite=="source-failure"))])
        running=true;paused=false
        let clock=NativeClockCalibration.now()
        let start=mach_absolute_time()-UInt64(2_000_000_000)*UInt64(clock.nsDenom)/UInt64(clock.nsNumer)
        for sequence:UInt64 in 1...2 {
            ingestFixturePacket(SessionAudioPacket(source:.remoteAudio,streamGeneration:1,sequence:sequence,hostTime:start+(sequence-1)*UInt64(32_000_000)*UInt64(clock.nsDenom)/UInt64(clock.nsNumer),samples:Array(repeating:0.2,count:512)))
        }
    }
    func ingestFixturePacket(_ packet:SessionAudioPacket){guard fixture else{return};native.ingest(packet)}
    var currentSessionID:UUID? { authority.snapshot()?.captureSessionID ?? forwardedSessionID }
    var canStartSession:Bool {
        guard case .success=helperRuntime else{return false}
        return !running && !starting && !stopping && teardown==nil && !speechSetup.snapshot.isBusy && !visual.isBusy && visual.status != .busy && (fixture || capture.phase == .idle)
    }
    var canResume:Bool { paused && canStartSession }
    func beginRetirement(end:Bool) {
        endRequested = endRequested || end
        if end { paused=false }
        startIdentity=UUID();speechSetup.cancel()
        guard teardown==nil else { disableVisualInput();return }
        let sessionID=forwardedSessionID;let oldHelper=helper
        let oldStart=startTask;oldStart?.cancel()
        // Real source/ASR admission and native paint retire before any await.
        if fixture { native.beginStop() } else { capture.retireAdmission(reason:.userStop) }
        authority.stop();running=false;paused = !end;stopping=true
        if hasContextComposer,let old=contextComposer.binding{enqueueContextRetirement(old)}
        disableVisualInput() // Enqueue before its callback can release old EOU.
        retireRequest(status:end ? "Stopped":"Paused · recent conversation will reset on resume")
        teardown=Task { [weak self] in
            guard let self else{return}
            await self.speechSetup.waitForQuiescence()
            await oldStart?.value
            if self.fixture { await self.native.waitForQuiescence();self.native.finishStop(quiesced:true) }
            else {
                await self.capture.stop(reason:.userStop)
                while self.capture.phase != .idle { try? await Task.sleep(for:.milliseconds(10)) }
            }
            await self.events.drain()
            await self.visual.waitForQuiescence()
            do {
                if let sessionID,let oldHelper { try await oldHelper.requestSessionQuiescence(sessionID:sessionID,epoch:1) }
            } catch {
                self.endRequested=true;self.paused=false
                self.error="The old helper did not acknowledge shutdown. Its profile was retired; reopen background to recover."
            }
            if self.endRequested {
                if let profile=self.profileStorage { await profile.close() }
                if let oldHelper {
                    if self.helper === oldHelper { self.helper=nil;self.helperIdentity=UUID();self.helperFailures.activate(self.helperIdentity) }
                    self.profileBinding?.retired=true
                    await oldHelper.shutdownAndWait()
                }
                self.profileBinding=nil;self.profileStorage=nil;self.forwardedSessionID=nil
                self.forwarder?.retire();self.forwarder=nil
                self.endRequested=false;self.paused=false
            }
            self.startTask=nil;self.starting=false;self.stopping=false;self.teardown=nil
        }
    }
    func stop() async { beginRetirement(end:true);await teardown?.value }
    func failSession() {
        // Keep the same actual owner join/reap barrier as End. A failed source
        // or transport cannot be replaced merely because its output is hidden.
        helper?.stop() // Fence the child before any local image-retirement callback.
        visual.retireForHelperChange()
        helperIdentity=UUID();helperFailures.activate(helperIdentity)
        beginRetirement(end:true)
        authority.stop();retireRequest(status:"Session unavailable")
        forwarder?.retire();forwarder=nil;running=false;paused=false
        error="The session ended. Restart after the previous session finishes."
    }
    func perform(_ action:ControlAction)throws {
        switch action {
        case .pause:guard running || starting else { throw ControlsError.actionFailed(action) };beginRetirement(end:false)
        case .endSession:beginRetirement(end:true)
        case .resume:guard canResume else { throw ControlsError.actionFailed(action) };Task { await start() }
        case .requestHelp:
            guard running,!stopping,forwarder?.isIdle != false,let question=acceptedQuestion,let lease=authority.snapshot() else { error="Ask a question first.";window?.makeKeyAndOrderFront(nil);return }
            let queue=events
            do {
                _=try (fixture ? native:capture.controller).issueManualHelp(expectedEventSequence:lastForwardedSequence,expectedLease:lease,question:question,enqueue:{ [weak self] request in
                    try queue.enqueue(.manual(request)) { [weak self] in self?.receive($0) }
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
    var canChangeAIMode:Bool { !fixture && canStartSession && profileStorage?.busy != true }
    func setAIEnabled(_ enabled:Bool) async {
        guard canChangeAIMode,enabled != oauth else { return }
        error=nil
        let oldProfile=profileStorage
        await stop()
        guard !stopping,helper==nil else { return }
        if let oldProfile,oldProfile.closeOutcome != .locked {
            error="Background could not be locked. Its helper was stopped; reopen saved background before trying again."
            return
        }
        oauth=enabled
        contextStatus="AI mode changed. Reopen saved background if needed."
    }
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
    }
    private func currentAnswerText()->String? {
        guard running,!stopping,let binding=currentBinding,authority.snapshot()==binding.lease,let card=snapshot.card else{return nil}
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
