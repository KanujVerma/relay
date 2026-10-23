import Dispatch
import Foundation
import RelayAudioBuffer
import RelayLocalASR
import RelayNativeSession

public enum CaptureSessionPhase: Sendable, Equatable { case idle, preparing, starting, running, stopping }

/// Actor-conforming test drivers and real independent microphone/tap drivers
/// share only owned PCM queues. No recording or source mixing is performed.
protocol SessionCaptureDriver: Sendable {
    var source: PCMSource { get }
    var queue: OwnedPCMQueue { get }
    func start() async throws
    func stop() async
    func unavailableReason() async -> SessionReason?
}

@MainActor public final class NativeCaptureSession {
    public let controller: NativeSessionController
    public private(set) var phase: CaptureSessionPhase = .idle
    private let prepare: @Sendable (NativeCaptureConfiguration) async throws -> [UInt32: SourceComponents]
    private let makeDrivers: @MainActor (NativeCaptureConfiguration) throws -> [any SessionCaptureDriver]
    private let stopTimeoutMilliseconds: Int
    private var drivers: [any SessionCaptureDriver] = []
    private var drainer: Task<Void, Never>?
    private var operationID: UUID?
    private var startInProgress = false
    private var shutdown: Task<Void, Never>?

    public convenience init(authority: SessionPresentationAuthority,
                            onEvent: @escaping @Sendable (NativeSessionEvent) throws -> Void) {
        self.init(authority: authority, onEvent: onEvent, prepare: { config in
            try config.validateLocalModels()
            var components: [UInt32: SourceComponents] = [:]
            var sources: [UInt32] = config.microphoneEnabled ? [1] : []
            if config.selectedBundleID != nil { sources.append(2) }
            for source in sources {
                try Task.checkCancellation()
                let vad = try await FluidSpeechActivityDetector.local(compiledModel: config.vadCompiledModel)
                let recognizer = try await FluidClosedActivityRecognizer.local(root: config.asrModelRoot)
                components[source] = SourceComponents(vad: vad, recognizer: recognizer)
            }
            return components
        }, makeDrivers: { config in
            var drivers: [any SessionCaptureDriver] = []
            if config.microphoneEnabled { drivers.append(try MicrophoneSessionDriver()) }
            if let bundle = config.selectedBundleID { drivers.append(try SelectedAppSessionDriver(bundleID: bundle)) }
            return drivers
        }, stopTimeoutMilliseconds: 2000)
    }
    init(authority: SessionPresentationAuthority,
         onEvent: @escaping @Sendable (NativeSessionEvent) throws -> Void,
         prepare: @escaping @Sendable (NativeCaptureConfiguration) async throws -> [UInt32: SourceComponents],
         makeDrivers: @escaping @MainActor (NativeCaptureConfiguration) throws -> [any SessionCaptureDriver],
         stopTimeoutMilliseconds: Int) {
        controller = NativeSessionController(authority: authority, onEvent: onEvent)
        self.prepare = prepare; self.makeDrivers = makeDrivers
        self.stopTimeoutMilliseconds = stopTimeoutMilliseconds
    }
    deinit {
        controller.beginStop(reason: .userStop)
        drainer?.cancel()
        let retainedDrivers = drivers, retainedDrainer = drainer, controller = controller
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for driver in retainedDrivers { group.addTask { await driver.stop() } }
            }
            await retainedDrainer?.value
            await controller.waitForQuiescence()
            controller.finishStop(quiesced: true)
        }
    }
    public func start(configuration: NativeCaptureConfiguration) async throws {
        guard phase == .idle else { throw NativeSessionError.alreadyRunning }
        try configuration.validate()
        let operation = UUID(); operationID = operation
        phase = .preparing; startInProgress = true
        do {
            let components = try await prepare(configuration)
            guard operationID == operation, phase == .preparing else { throw CancellationError() }
            try Task.checkCancellation()
            drivers = try makeDrivers(configuration)
            try controller.start(selectedBundleID: configuration.selectedBundleID,
                                 microphoneEnabled: configuration.microphoneEnabled, components: components)
            phase = .starting
            // Begin consuming before the first source starts, so an awaited
            // permission/start on the second source cannot fill the first ring.
            startDrainer(drivers: drivers, operation: operation)
            for driver in drivers {
                try await driver.start()
                guard operationID == operation, phase == .starting else { throw CancellationError() }
                try Task.checkCancellation()
            }
            startInProgress = false; phase = .running
        } catch {
            startInProgress = false
            controller.beginStop(reason: error is CancellationError ? .userStop : .captureError)
            phase = .stopping
            await beginShutdown(operation: operation)
            throw error
        }
    }
    /// The first operations execute on MainActor before the first await. Pause
    /// is composed by the panel as stop plus a fresh explicit Start, not a timer
    /// toggle. No ASR final is flushed from truncated stop audio.
    public func stop(reason: SessionReason = .userStop) async {
        guard phase != .idle else { return }
        if phase != .stopping { phase = .stopping; controller.beginStop(reason: reason) }
        if startInProgress {
            // The outstanding start retains ownership and must return before
            // producer stop or restart. Its catch path owns eventual shutdown.
            return
        }
        guard let operationID else { return }
        await beginShutdown(operation: operationID)
    }
    private func beginShutdown(operation: UUID) async {
        if let shutdown {
            _ = await waitForShutdown(shutdown, timeoutMilliseconds: stopTimeoutMilliseconds)
            return
        }
        drainer?.cancel()
        let retainedDrivers = drivers, retainedDrainer = drainer
        let controller = controller
        let stopping = Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for driver in retainedDrivers { group.addTask { await driver.stop() } }
            }
            // Both capture callbacks are quiescent before the SPSC consumer and
            // queues can retire. A timeout never establishes this fact.
            await retainedDrainer?.value
            await controller.waitForQuiescence()
        }
        shutdown = stopping
        let quiesced = await waitForShutdown(stopping, timeoutMilliseconds: stopTimeoutMilliseconds)
        controller.finishStop(quiesced: quiesced)
        if quiesced { completeShutdown(operation: operation) }
        else {
            Task { [self] in
                await stopping.value
                completeShutdown(operation: operation)
            }
        }
    }
    private func completeShutdown(operation: UUID) {
        guard operationID == operation else { return }
        drivers.removeAll(); drainer = nil; shutdown = nil; operationID = nil; phase = .idle
    }
    private func startDrainer(drivers: [any SessionCaptureDriver], operation: UUID) {
        let controller = controller
        drainer = Task.detached { [weak self] in
            // Separate converter state per source, never a shared recognizer or
            // combined mic/system waveform. Only this task consumes the rings.
            var converters: [UInt32: ASRMonoConverter] = [:]
            for driver in drivers { converters[driver.source.rawValue] = ASRMonoConverter() }
            var iteration = 0
            var observedGenerations: [UInt32: UInt64] = [:]
            while !Task.isCancelled {
                var consumed = false
                for driver in drivers {
                    // Limit work per source per pass so overlap remains fair.
                    for _ in 0..<8 {
                        guard let frame = driver.queue.dequeue() else { break }
                        consumed = true
                        observedGenerations[frame.source.rawValue] = frame.streamGeneration
                        do {
                            guard let converter = converters[driver.source.rawValue] else { throw NativeSessionError.invalidFrame }
                            let mono = try converter.mono(frame)
                            let samples = try converter.normalizeWindow(mono, from: frame.sampleRate)
                            controller.ingest(SessionAudioPacket(source: frame.source,
                                streamGeneration: frame.streamGeneration, sequence: frame.sequence,
                                hostTime: frame.hostTime, samples: samples, originalSampleRate: frame.sampleRate))
                        } catch {
                            controller.sourceUnavailable(source: driver.source, generation: frame.streamGeneration, reason: .captureError)
                        }
                    }
                    if iteration % 10 == 0, let reason = await driver.unavailableReason() {
                        controller.sourceUnavailable(source: driver.source, generation: observedGenerations[driver.source.rawValue] ?? 1, reason: reason)
                    }
                }
                iteration = (iteration + 1) % 100
                if controller.authority.snapshot() == nil || drivers.contains(where: { !controller.isSourceActive($0.source) }) {
                    // A helper/writer failure halts actual capture as well as UI
                    // authority. Schedule teardown then leave this consumer, so
                    // shutdown never awaits its own task.
                    Task { @MainActor [weak self] in
                        guard self?.operationID == operation else { return }
                        await self?.stop(reason: controller.authority.snapshot() == nil ? .transportClosed : .captureError)
                    }
                    return
                }
                if !consumed { try? await Task.sleep(for: .milliseconds(10)) }
                else { await Task.yield() }
            }
        }
    }
}

@MainActor private final class MicrophoneSessionDriver: SessionCaptureDriver {
    nonisolated let source = PCMSource.microphone
    nonisolated let queue: OwnedPCMQueue
    private let capture: MicrophoneCapture
    init() throws {
        let ring = try OwnedPCMQueue(source: .microphone, capacityBytes: 1_048_576)
        queue = ring; capture = MicrophoneCapture(queue: ring)
    }
    func start() async throws { _ = try await capture.start() }
    func stop() async { capture.stop() }
    func unavailableReason() async -> SessionReason? { nil }
}
private final class SelectedAppSessionDriver: SessionCaptureDriver, @unchecked Sendable {
    let source = PCMSource.remoteAudio
    let queue: OwnedPCMQueue
    private let capture: SelectedAppProcessTap
    private let bundleID: String
    init(bundleID: String) throws {
        let ring = try OwnedPCMQueue(source: .remoteAudio, capacityBytes: 1_048_576)
        queue = ring; capture = SelectedAppProcessTap(queue: ring); self.bundleID = bundleID
    }
    func start() async throws {
        let capture = capture, bundleID = bundleID
        _ = try await Task.detached { try capture.start(bundleID: bundleID) }.value
    }
    func stop() async { let capture = capture; await Task.detached { capture.stop() }.value }
    func unavailableReason() async -> SessionReason? {
        switch capture.status {
        case .captureError: return .captureError
        case .selectedAppUnavailable: return .selectedAppUnavailable
        case .stopped, .captureAttemptedPermissionUnverified: return nil
        }
    }
}

/// A one-shot deadline releases the UI waiter only. The retained driver task
/// continues to own its queues until real quiescence. Adapted lifecycle rule
/// from Muesli; no recording URLs, wall clock or deletion machinery is adopted.
private final class ShutdownWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
    func finish(_ quiesced: Bool) {
        let value = lock.withLock { let value = continuation; continuation = nil; return value }
        value?.resume(returning: quiesced)
    }
}
private func waitForShutdown(_ task: Task<Void, Never>, timeoutMilliseconds: Int) async -> Bool {
    await withCheckedContinuation { continuation in
        let waiter = ShutdownWaiter(continuation)
        let deadline = DispatchWorkItem { waiter.finish(false) }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(timeoutMilliseconds), execute: deadline)
        Task { await task.value; deadline.cancel(); waiter.finish(true) }
    }
}
