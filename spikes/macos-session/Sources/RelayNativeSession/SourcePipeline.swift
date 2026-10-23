import Dispatch
import Foundation
import RelayAudioBuffer

public enum NativeSessionLimits {
    /// The existing inner wire admits at most 120 seconds. Session duration is
    /// unlimited; each individual continuous activity remains memory bounded.
    public static let maximumActivitySamples = 1_920_000
}

public struct SpeechBoundary: Sendable, Equatable {
    public enum Kind: Sendable { case start, end }
    public let kind: Kind
    /// Absolute 16 kHz input sample index since this source detector was made.
    public let sampleIndex: UInt64
    public init(kind: Kind, sampleIndex: UInt64) { self.kind = kind; self.sampleIndex = sampleIndex }
}
public protocol SpeechActivityDetector: Actor {
    nonisolated var chunkSamples: Int { get }
    func accept(_ samples: [Float]) async throws -> [SpeechBoundary]
}
public protocol ActivityRecognizer: Actor {
    /// Consumes every sample in one complete closed activity before finishing.
    func recognize(_ samples: [Float]) async throws -> String
}
public struct SourceComponents: Sendable {
    public let vad: any SpeechActivityDetector
    public let recognizer: any ActivityRecognizer
    public init(vad: any SpeechActivityDetector, recognizer: any ActivityRecognizer) {
        self.vad = vad; self.recognizer = recognizer
    }
}
public struct SessionAudioPacket: Sendable {
    public let source: PCMSource
    public let streamGeneration: UInt64
    public let sequence: UInt64
    public let hostTime: UInt64
    /// Bounded owned mono 16 kHz samples; normalization occurs off the HAL callback.
    public let samples: [Float]
    public let originalSampleRate: Double
    public init(source: PCMSource, streamGeneration: UInt64, sequence: UInt64,
                hostTime: UInt64, samples: [Float], originalSampleRate: Double = 16_000) {
        self.source = source; self.streamGeneration = streamGeneration; self.sequence = sequence
        self.hostTime = hostTime; self.samples = samples; self.originalSampleRate = originalSampleRate
    }
}
struct ClosedActivity: Sendable {
    let id: UInt64
    let firstSequence: UInt64
    let lastSequence: UInt64
    let startHostTime: UInt64
    let endHostTime: UInt64
    let generation: UInt64
    let samples: [Float]
    let lease: PresentationLease
    let clock: NativeClockCalibration
}

/// Narrow adaptation of Muesli's generation/single-drainer pattern, with a
/// capped queue, no Date/timers/recording and independent recognition ownership.
/// See THIRD_PARTY_NOTICES.md. All mutable VAD state has exactly one drainer.
final class SourcePipeline: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private var pending: [SessionAudioPacket] = []
    private var pendingSamples = 0
    private var draining = false
    private var drainerTask: Task<Void, Never>?
    private var previous: SessionAudioPacket?
    private let source: PCMSource
    private let processor: ActivityProcessor
    private let failure: @Sendable (SessionReason, UInt64) -> Void

    init(source: PCMSource, components: SourceComponents,
         onStart: @escaping @Sendable (UInt64, UInt64, UInt64, NativeClockCalibration) -> PresentationLease?,
         onEnd: @escaping @Sendable (ClosedActivity) -> Void,
         onFinal: @escaping @Sendable (ClosedActivity, String) -> Void,
         onFailure: @escaping @Sendable (SessionReason, UInt64) -> Void) {
        self.source = source; self.failure = onFailure
        self.processor = ActivityProcessor(components: components, onStart: onStart, onEnd: onEnd,
                                          onFinal: onFinal, onFailure: onFailure)
    }
    func enqueue(_ packet: SessionAudioPacket) {
        var reason: SessionReason?
        let kick = lock.withLock { () -> Bool in
            guard active else { return false }
            guard packet.source == source, packet.streamGeneration > 0, packet.sequence > 0,
                  packet.hostTime > 0, !packet.samples.isEmpty, packet.samples.count <= 8192,
                  packet.samples.allSatisfy(\.isFinite), packet.originalSampleRate.isFinite,
                  [16_000, 24_000, 44_100, 48_000].contains(packet.originalSampleRate) else {
                reason = .captureError; active = false; return false
            }
            if let prior = previous {
                if packet.streamGeneration < prior.streamGeneration { return false }
                if packet.streamGeneration != prior.streamGeneration || packet.originalSampleRate != prior.originalSampleRate {
                    reason = .deviceChanged; active = false; return false
                }
                if prior.sequence == UInt64.max || packet.sequence != prior.sequence + 1 {
                    reason = .sequenceGap; active = false; return false
                }
                if packet.hostTime < prior.hostTime { reason = .clockInvalid; active = false; return false }
            }
            // At most one second of queued normalized audio, plus one in-flight
            // bounded packet. No task per callback and no hidden AsyncStream.
            guard pendingSamples + packet.samples.count <= 16_000, pending.count < 64 else {
                reason = .queueOverflow; active = false; return false
            }
            previous = packet
            pending.append(packet); pendingSamples += packet.samples.count
            guard !draining else { return false }
            draining = true
            return true
        }
        if let reason { stop(); failure(reason, packet.streamGeneration) }
        if kick {
            let task = Task { await drain() }
            lock.withLock {
                drainerTask = task
                if !active { task.cancel() }
            }
        }
    }
    func stop() {
        lock.withLock { active = false; pending.removeAll(); pendingSamples = 0; drainerTask?.cancel() }
        Task { await processor.cancel() }
        // No backend.reset() races a still-running accept/finish. The drainer
        // and recognizer own their references until the operations quiesce.
    }
    func waitForQuiescence() async {
        let task = lock.withLock { drainerTask }
        await task?.value
        await processor.waitForQuiescence()
    }
    private var isActive: Bool { lock.withLock { active } }
    private func drain() async {
        while true {
            let next = lock.withLock { () -> SessionAudioPacket? in
                guard active, !pending.isEmpty else { draining = false; return nil }
                let packet = pending.removeFirst(); pendingSamples -= packet.samples.count
                return packet
            }
            guard let next else { return }
            await processor.accept(next, isActive: { self.isActive })
        }
    }
}

private actor ActivityProcessor {
    private struct Span: Sendable { let first: UInt64; let end: UInt64; let packet: SessionAudioPacket }
    private let components: SourceComponents
    private let onStart: @Sendable (UInt64, UInt64, UInt64, NativeClockCalibration) -> PresentationLease?
    private let onEnd: @Sendable (ClosedActivity) -> Void
    private let onFinal: @Sendable (ClosedActivity, String) -> Void
    private let onFailure: @Sendable (SessionReason, UInt64) -> Void
    private var history: [Float] = []
    private var historyBase: UInt64 = 0
    private var totalSamples: UInt64 = 0
    private var pending: [Float] = []
    private var spans: [Span] = []
    private var activityStart: UInt64?
    private var activityLease: PresentationLease?
    private var activityID: UInt64 = 0
    private var recognizing = false
    private var recognitionTask: Task<Void, Never>?
    private var failed = false
    private var clock = NativeClockCalibration.now()

    init(components: SourceComponents,
         onStart: @escaping @Sendable (UInt64, UInt64, UInt64, NativeClockCalibration) -> PresentationLease?,
         onEnd: @escaping @Sendable (ClosedActivity) -> Void,
         onFinal: @escaping @Sendable (ClosedActivity, String) -> Void,
         onFailure: @escaping @Sendable (SessionReason, UInt64) -> Void) {
        self.components = components; self.onStart = onStart; self.onEnd = onEnd
        self.onFinal = onFinal; self.onFailure = onFailure
    }
    func accept(_ packet: SessionAudioPacket, isActive: @escaping @Sendable () -> Bool) async {
        guard isActive(), !failed else { return }
        let chunkSize = components.vad.chunkSamples
        guard (1...8192).contains(chunkSize), totalSamples <= UInt64.max - UInt64(packet.samples.count) else {
            fail(.vadUnavailable, packet.streamGeneration); return
        }
        spans.append(Span(first: totalSamples, end: totalSamples + UInt64(packet.samples.count), packet: packet))
        totalSamples += UInt64(packet.samples.count)
        history.append(contentsOf: packet.samples); pending.append(contentsOf: packet.samples)
        do {
            while pending.count >= chunkSize {
                let chunk = Array(pending.prefix(chunkSize)); pending.removeFirst(chunkSize)
                let events = try await components.vad.accept(chunk)
                guard isActive(), !failed else { return }
                let processed = totalSamples - UInt64(pending.count)
                for boundary in events {
                    guard boundary.sampleIndex <= processed, boundary.sampleIndex >= historyBase else {
                        fail(.vadUnavailable, packet.streamGeneration); return
                    }
                    switch boundary.kind {
                    case .start:
                        guard activityStart == nil, activityID < UInt64.max,
                              let span = span(at: boundary.sampleIndex) else {
                            fail(.vadUnavailable, packet.streamGeneration); return
                        }
                        activityID += 1; activityStart = boundary.sampleIndex
                        clock = .now()
                        let ticks = try clock.hostTicks(after: span.packet.hostTime,
                            sampleOffset: Int(boundary.sampleIndex - span.first), rate: 16_000)
                        activityLease = onStart(activityID, packet.streamGeneration, ticks, clock)
                    case .end:
                        guard let start = activityStart, let lease = activityLease,
                              boundary.sampleIndex > start,
                              let first = span(at: start), let last = span(at: boundary.sampleIndex - 1) else {
                            fail(.vadUnavailable, packet.streamGeneration); return
                        }
                        guard boundary.sampleIndex - start <= UInt64(NativeSessionLimits.maximumActivitySamples) else {
                            fail(.queueOverflow, packet.streamGeneration); return
                        }
                        let activity = ClosedActivity(id: activityID, firstSequence: first.packet.sequence,
                            lastSequence: last.packet.sequence,
                            startHostTime: try clock.hostTicks(after: first.packet.hostTime, sampleOffset: Int(start - first.first), rate: 16_000),
                            endHostTime: try clock.hostTicks(after: last.packet.hostTime, sampleOffset: Int(boundary.sampleIndex - last.first), rate: 16_000),
                            generation: packet.streamGeneration,
                            samples: Array(history[Int(start - historyBase)..<Int(boundary.sampleIndex - historyBase)]),
                            lease: lease, clock: clock)
                        activityStart = nil; activityLease = nil
                        onEnd(activity)
                        guard !recognizing else { fail(.asrUnavailable, packet.streamGeneration); return }
                        recognizing = true
                        recognitionTask = Task { await recognize(activity, isActive: isActive) }
                    }
                }
                if let start = activityStart, processed - start > UInt64(NativeSessionLimits.maximumActivitySamples) {
                    fail(.queueOverflow, packet.streamGeneration); return
                }
                // Retain 512 ms pre-roll while idle. A longer VAD lookback must
                // fail provenance rather than invent earlier samples.
                let keepFrom = activityStart ?? (processed > 8192 ? processed - 8192 : 0)
                if keepFrom > historyBase {
                    history.removeFirst(Int(keepFrom - historyBase)); historyBase = keepFrom
                    spans.removeAll { $0.end <= historyBase }
                }
            }
        } catch { fail(.vadUnavailable, packet.streamGeneration) }
    }
    func cancel() {
        failed = true
        recognitionTask?.cancel()
        history.removeAll(); pending.removeAll(); spans.removeAll()
        activityStart = nil; activityLease = nil
    }
    func waitForQuiescence() async { await recognitionTask?.value }
    private func span(at sample: UInt64) -> Span? { spans.first { $0.first <= sample && sample < $0.end } }
    private func recognize(_ activity: ClosedActivity, isActive: @escaping @Sendable () -> Bool) async {
        defer { recognizing = false; recognitionTask = nil }
        do {
            let text = try await components.recognizer.recognize(activity.samples)
            guard isActive(), !failed else { return }
            // A later onset never stamps this result with a newer lease. The
            // host may retain it as context, but cannot paint it as current.
            onFinal(activity, text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            guard isActive(), !failed else { return }
            fail(.asrUnavailable, activity.generation)
        }
    }
    private func fail(_ reason: SessionReason, _ generation: UInt64) {
        guard !failed else { return }
        failed = true; history.removeAll(); pending.removeAll(); spans.removeAll()
        activityStart = nil; activityLease = nil
        onFailure(reason, generation)
    }
}
