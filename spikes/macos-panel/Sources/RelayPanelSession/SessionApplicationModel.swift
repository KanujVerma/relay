import AppKit
import Combine
import Darwin
import Foundation
import RelayNativeSession
import RelaySessionCapture
import RelayAudioBuffer
import RelaySessionPanel
import RelayProfile

private final class MainEventQueue: @unchecked Sendable {
    private let lock=NSLock();private var count=0;private var bytes=0
    func enqueue(_ event:NativeSessionEvent,action:@escaping @MainActor @Sendable(NativeSessionEvent)->Void) throws {
        let size=try event.encodedFrame().count
        try lock.withLock { guard count<32,bytes+size<=262144 else { throw PanelBridgeError.overflow };count+=1;bytes+=size }
        DispatchQueue.main.async { [self] in
            defer { lock.withLock { count-=1;bytes-=size } };action(event)
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
    init(_ questions:[String]) { self.questions=questions }
    func recognize(_ samples:[Float]) async throws -> String { questions.isEmpty ? "":questions.removeFirst() }
}

@MainActor final class SessionApplicationModel: ObservableObject {
    @Published private(set) var snapshot=SessionPanelSnapshot()
    @Published private(set) var running=false
    @Published private(set) var starting=false
    @Published private(set) var error:String?
    @Published var selectedBundleID=""
    @Published var microphoneEnabled=true
    @Published var authorizedConversation=false
    @Published var modelLicensesAcknowledged=false
    @Published var asrFolder=""
    @Published var vadFolder=""
    let fixture:Bool
    let fixtureSuite:String
    let oauth:Bool
    let role:String
    let root:URL
    private let python:URL
    private let pythonArguments:[String]
    private let authority=SessionPresentationAuthority()
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
            try queue.enqueue(event) { [weak self] in self?.forward($0) }
        })
    }()
    private lazy var capture:NativeCaptureSession = {
        let queue=events
        return NativeCaptureSession(authority:authority,onEvent:{ [weak self] event in
            try queue.enqueue(event) { [weak self] in self?.forward($0) }
        })
    }()
    private var profileWasCreated=false
    lazy var profile:ProfileController = {
        profileWasCreated=true
        let port=ClosureProfilePort(request:{ [weak self] data in
            guard let self else { throw PanelBridgeError.closed }
            let command=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
            if command?["command"] as? String == "lock",await self.helper==nil { throw PanelBridgeError.closed }
            let helper=try await self.ensureHelper()
            return try await helper.requestProfile(data)
        })
        let directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Relay",isDirectory:true)
        return ProfileController(client:ProfileClient(port:port),vault:ProfileVault(directory:directory),onInvalidate:{ [weak self] in
            guard let self else { return };self.authority.invalidate();self.panel.clear(status:"Background updated")
        })
    }()

    init(arguments:[String]=CommandLine.arguments) {
        fixture=arguments.contains("--fixture-suite")
        fixtureSuite=Self.argument("--fixture-suite",arguments) ?? "reviewed"
        role=Self.argument("--role",arguments) ?? (fixture ? "analytics":"developer")
        oauth=arguments.contains("--oauth") && !fixture
        let pythonPath=Self.argument("--python",arguments)
        python=URL(fileURLWithPath:pythonPath ?? "/usr/bin/env")
        pythonArguments=pythonPath==nil ? ["python3"]:[]
        root=URL(fileURLWithPath:Self.argument("--repository",arguments) ?? FileManager.default.currentDirectoryPath)
        asrFolder=Self.argument("--asr-models",arguments) ?? ""
        vadFolder=Self.argument("--vad-model",arguments) ?? ""
    }
    private static func argument(_ key:String,_ args:[String]) -> String? { guard let i=args.firstIndex(of:key),args.indices.contains(i+1) else { return nil };return args[i+1] }
    func ensureHelper() throws -> HelperTransport {
        if let helper { return helper }
        let identity=UUID();helperIdentity=identity;helperFailures.activate(identity)
        let nativeAuthority=authority;let failures=helperFailures;let delivery=answers
        let helper=HelperTransport(root:root,python:python,pythonArguments:pythonArguments,mode:fixture ? .fixture:oauth ? .oauth:.noInference,role:role,onFrame:{ [weak self] data in
            try delivery.enqueue(data,byteCount:data.count) { [weak self] data in
                guard let self,self.helperIdentity==identity else { return }
                do { _=try self.panel.accept(data) } catch { self.failSession() }
            }
        },onFailure:{ [weak self] in
            guard failures.withCurrent(identity,perform:{ nativeAuthority.stop() }) else { return }
            Task { @MainActor in guard let self,self.helperIdentity==identity else { return };self.failSession() }
        })
        try helper.start();self.helper=helper;return helper
    }
    private func forward(_ event:NativeSessionEvent) {
        panel.observe(event)
        do { try helper?.send(event) } catch { failSession() }
    }
    func start() async {
        guard !running,!starting else { return };error=nil;starting=true;defer { starting=false }
        do {
            if !fixture && capture.phase != .idle { error="Waiting for capture to finish stopping.";return }
            _=try ensureHelper()
            if fixture { try startFixture();return }
            guard authorizedConversation,modelLicensesAcknowledged,!asrFolder.isEmpty,!vadFolder.isEmpty else {
                error="Choose local speech models and confirm this is a permitted conversation before starting.";return
            }
            let configuration=NativeCaptureConfiguration(microphoneEnabled:microphoneEnabled,selectedBundleID:selectedBundleID.isEmpty ? nil:selectedBundleID,asrModelRoot:URL(fileURLWithPath:asrFolder),vadCompiledModel:URL(fileURLWithPath:vadFolder),authorizedConversation:authorizedConversation,localModelLicensesAcknowledged:modelLicensesAcknowledged)
            try configuration.validateLocalModels()
            try await capture.start(configuration:configuration)
            running=capture.phase == .running
        } catch is CancellationError { panel.clear(status:"Stopped") }
        catch { failSession() }
    }
    private func startFixture() throws {
        let question=fixtureSuite=="coding" ? "Write a Python function that returns the first item or None for an empty list." : fixtureSuite=="case" ? "Case study: design a feature for nurse handoffs. What user needs would you clarify first?":"What is the difference between WHERE and HAVING?"
        try native.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,components:[2:SourceComponents(vad:FixtureVAD(),recognizer:FixtureRecognizer([question]))])
        running=true
        let clock=NativeClockCalibration.now()
        let start=mach_absolute_time()-UInt64(2_000_000_000)*UInt64(clock.nsDenom)/UInt64(clock.nsNumer)
        for sequence:UInt64 in 1...2 {
            native.ingest(SessionAudioPacket(source:.remoteAudio,streamGeneration:1,sequence:sequence,hostTime:start+(sequence-1)*UInt64(32_000_000)*UInt64(clock.nsDenom)/UInt64(clock.nsNumer),samples:Array(repeating:0.2,count:512)))
        }
    }
    func stop() async {
        if fixture { native.beginStop();panel.clear(status:"Stopped");running=false;await native.waitForQuiescence();native.finishStop(quiesced:true) }
        else { panel.clear(status:"Stopped");running=false;await capture.stop(reason:.userStop) }
    }
    func failSession() {
        authority.stop()
        if fixture { native.retire() } else { capture.controller.retire();Task { await capture.stop(reason:.transportClosed) } }
        panel.clear(status:"Session unavailable");running=false;error="The session ended. Restart when you are ready."
        helper?.stop();helper=nil;helperIdentity=UUID();helperFailures.activate(helperIdentity)
        if profileWasCreated { Task { await profile.close() } }
    }
}
