import Dispatch
import FluidAudio
import Foundation
import RelayAudioBuffer

/// Non-real-time normalization; the library's AVAudioConverter-backed path
/// avoids ad-hoc sample dropping/upsampling. Only call from the worker actor.
/// We batch source audio before resampling instead of resampling every 1024
/// frame callback (which can create audible boundaries).
public struct ASRMonoConverter: Sendable {
    private let converter = AudioConverter()

    public init() {}

    public func mono(_ frame: PCMFrame) throws -> [Float] {
        guard frame.frameCount > 0, frame.frameCount <= 8192,
              (1...2).contains(frame.channelCount),
              frame.interleavedSamples.count == frame.frameCount * frame.channelCount,
              [16_000, 24_000, 44_100, 48_000].contains(frame.sampleRate),
              frame.interleavedSamples.allSatisfy(\.isFinite) else {
            throw ASRWorkerError.invalidFrame
        }
        if frame.channelCount == 1 { return frame.interleavedSamples }
        var result = [Float]()
        result.reserveCapacity(frame.frameCount)
        for i in 0..<frame.frameCount {
            result.append(
                (frame.interleavedSamples[2 * i]
                    + frame.interleavedSamples[2 * i + 1]) * 0.5
            )
        }
        return result
    }

    public func normalizeWindow(_ mono: [Float], from sampleRate: Double) throws -> [Float] {
        guard !mono.isEmpty, mono.count <= 48_000,
              [16_000, 24_000, 44_100, 48_000].contains(sampleRate),
              mono.allSatisfy(\.isFinite) else { throw ASRWorkerError.invalidFrame }
        return try converter.resample(mono, from: sampleRate)
    }
}

public enum ASRWorkerError: Error, Equatable {
    case invalidFrame
    case unauthorizedCapture
}

/// One serial non-realtime actor consumes a single owned SPSC queue.
/// Finalized model strings remain untrusted and are NEVER added to Personal Brain.
/// A channel is a capture source, not a claim about biometric speaker identity.
public actor PCMTranscriptWorker {
    private let source: PCMSource
    private let backend: any LocalEouRecognizer
    private let converter = ASRMonoConverter()
    private let authorized: Bool
    private let windowSeconds = 0.32
    private let maximumUtteranceSeconds = 20.0

    private var generation: UInt64?
    private var previousSequence: UInt64?
    private var sampleRate: Double?
    private var startHostTime: UInt64?
    private var endHostTime: UInt64?
    private var pendingMono: [Float] = []
    private var utteranceFrames: Int = 0
    private var segmentID: UInt64 = 0
    // Swift actors are reentrant across awaits. Invalidate in-flight ASR
    // before cancelled/replaced audio can return a stale final transcript.
    private var invalidationEpoch: UInt64 = 0
    // Cancellation is terminal for this worker: a new authorized capture
    // must create a NEW worker, so queued old frames can never restart ASR.
    private var cancelled = false
    private var resetInProgress = false

    /// 'authorizedCapture' must come from a real host consent event in the
    /// shipping app. This prototype accepts an explicit caller assertion only.
    public init(
        source: PCMSource, authorizedCapture: Bool,
        backend: any LocalEouRecognizer
    ) {
        self.source = source
        self.authorized = authorizedCapture
        self.backend = backend
    }

    public func ingest(_ frame: PCMFrame) async -> [FinalTranscriptEvent] {
        guard !cancelled, !resetInProgress else { return [] }
        guard authorized else {
            return [event(.unavailable, generation: frame.streamGeneration)]
        }
        guard frame.source == source else {
            // Fail closed and invalidate any partial pending source context.
            let marker = event(.unavailable, generation: frame.streamGeneration)
            await reset()
            return [marker]
        }
        if let generation, frame.streamGeneration < generation {
            // Old callback after device restart. No state mutation.
            return []
        }
        var transition: FinalTranscriptEvent?
        let sequenceChanged = previousSequence.map {
            frame.sequence != ($0 &+ 1)
        } ?? false
        if (generation != nil && generation != frame.streamGeneration)
            || sequenceChanged
            || (sampleRate != nil && sampleRate != frame.sampleRate) {
            // Invalidate incomplete prior audio, but reuse this valid first
            // packet of the new segment instead of discarding it as well.
            let priorEpoch = invalidationEpoch
            await reset()
            guard !cancelled, invalidationEpoch == priorEpoch &+ 1 else {
                // reset() is async; a concurrent stop/turn correction could
                // have superseded this ingestion during the backend reset.
                return []
            }
            // Reset has cleared previous-generation timestamps. Do not label
            // old host ticks as belonging to the new generation.
            transition = event(.discontinuity, generation: frame.streamGeneration)
        }

        do {
            let samples = try converter.mono(frame)
            if generation == nil { generation = frame.streamGeneration }
            if sampleRate == nil { sampleRate = frame.sampleRate }
            if startHostTime == nil, frame.hostTime != 0 {
                startHostTime = frame.hostTime
            }
            if frame.hostTime != 0 { endHostTime = frame.hostTime }
            previousSequence = frame.sequence
            utteranceFrames += frame.frameCount
            if Double(utteranceFrames) / frame.sampleRate > maximumUtteranceSeconds {
                let state = event(.unavailable, generation: frame.streamGeneration)
                await reset()
                return [state]
            }
            pendingMono.append(contentsOf: samples)
            let window = max(1, Int(frame.sampleRate * windowSeconds))
            let ticket = invalidationEpoch
            var finals: [FinalTranscriptEvent] = transition.map { [$0] } ?? []
            while pendingMono.count >= window {
                let piece = Array(pendingMono.prefix(window))
                pendingMono.removeFirst(window)
                let mono16k = try converter.normalizeWindow(piece, from: frame.sampleRate)
                let reachedEou = try await backend.accept(mono16k)
                guard ticket == invalidationEpoch,
                      generation == frame.streamGeneration else {
                    // Cancel/correction or stream switch while CoreML awaited.
                    return []
                }
                if reachedEou {
                    if let final = await finalize(
                        generation: frame.streamGeneration, ticket: ticket
                    ) {
                        finals.append(final)
                    }
                }
            }
            return finals
        } catch {
            let marker = event(.unavailable, generation: frame.streamGeneration)
            await reset()
            return [marker]
        }
    }

    /// A caller ends an explicitly authorized capture. Any remaining samples
    /// are flushed on the worker, never from a HAL callback. No text from a
    /// cancelled/discontinuous generation is reconstructed from stale buffers.
    public func finishAtStop() async -> FinalTranscriptEvent? {
        guard authorized, !cancelled, !resetInProgress,
              let generation, let sampleRate else {
            await reset()
            return nil
        }
        do {
            let ticket = invalidationEpoch
            guard utteranceFrames > 0 else {
                await reset()
                return nil
            }
            var reachedEou = false
            if !pendingMono.isEmpty {
                let audio = try converter.normalizeWindow(pendingMono, from: sampleRate)
                reachedEou = try await backend.accept(audio)
                guard ticket == invalidationEpoch,
                      self.generation == generation else { return nil }
                pendingMono.removeAll(keepingCapacity: true)
            }
            guard reachedEou else {
                // Time-limit stop may interrupt a live sentence. Do NOT
                // present an arbitrary decoder hypothesis as a final question.
                let marker = event(.unavailable, generation: generation)
                await reset()
                return marker
            }
            return await finalize(generation: generation, ticket: ticket)
        } catch {
            let marker = event(.unavailable, generation: generation)
            await reset()
            return marker
        }
    }

    public func cancel() async {
        // Explicit stop/consent revocation is TERMINAL, even if no first
        // frame has arrived yet. Create a new worker on a new authorized start.
        cancelled = true
        await reset()
    }

    private func finalize(generation: UInt64, ticket: UInt64) async -> FinalTranscriptEvent? {
        do {
            let result = try await backend.finish()
            guard ticket == invalidationEpoch,
                  self.generation == generation else { return nil }
            let text = result.trimmingCharacters(in: .whitespacesAndNewlines)
            segmentID &+= 1
            let final = text.isEmpty ? nil : event(
                .final, generation: generation, text: text
            )
            // This reset clears decoder context, not the model weights.
            await backend.reset()
            guard ticket == invalidationEpoch,
                  self.generation == generation else { return nil }
            pendingMono.removeAll(keepingCapacity: true)
            utteranceFrames = 0
            startHostTime = nil
            endHostTime = nil
            return final
        } catch {
            let marker = event(.unavailable, generation: generation)
            await reset()
            return marker
        }
    }

    private func event(
        _ status: FinalTranscriptEvent.Status,
        generation: UInt64,
        text: String? = nil
    ) -> FinalTranscriptEvent {
        FinalTranscriptEvent(
            status: status,
            source: source,
            streamGeneration: generation,
            segmentID: segmentID,
            startHostTime: startHostTime,
            endHostTime: endHostTime,
            finalizedUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            text: text
        )
    }

    private func reset() async {
        invalidationEpoch &+= 1
        let ticket = invalidationEpoch
        resetInProgress = true
        pendingMono.removeAll(keepingCapacity: true)
        utteranceFrames = 0
        startHostTime = nil
        endHostTime = nil
        previousSequence = nil
        sampleRate = nil
        generation = nil
        await backend.reset()
        if invalidationEpoch == ticket { resetInProgress = false }
    }
}
