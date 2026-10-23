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
    // Swift actors can accept new calls while CoreML finish()/reset() awaits.
    // Those later packets must never be appended to the ending utterance.
    private var processingInProgress = false
    // A transition reset clears generation before it creates a terminal.
    // Keep that identity only across this reset; failure/limit resets
    // already own a terminal that the original operation will return.
    private var transitionGeneration: UInt64?
    private var processingInterrupted = false

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
        if processingInProgress {
            // Discard foreign-source or older-generation callbacks before
            // treating a competing packet as an interruption. A stale Core
            // Audio callback must not invalidate a legitimate in-flight EOU.
            guard frame.source == source else { return [] }
            if let generation, frame.streamGeneration < generation { return [] }
            // Never append audio while an existing ingest/finish awaits.
            // Explicitly invalidate that final if a concurrent caller drops
            // samples here. The worker remains bounded and discards no content
            // while pretending it completed a question.
            let firstInterruption = !processingInterrupted
            processingInterrupted = true
            if !firstInterruption { return [] }
            return [FinalTranscriptEvent(
                status: .discontinuity,
                source: source,
                streamGeneration: frame.streamGeneration,
                segmentID: segmentID,
                startHostTime: nil,
                endHostTime: nil,
                finalizedUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
            )]
        }
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
        processingInProgress = true
        defer {
            processingInProgress = false
            processingInterrupted = false
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
            transitionGeneration = frame.streamGeneration
            await reset()
            transitionGeneration = nil
            guard !cancelled, !processingInterrupted,
                  invalidationEpoch == priorEpoch &+ 1 else {
                // reset() is async; a concurrent stop/turn correction could
                // have superseded this ingestion during the backend reset.
                return []
            }
            // Reset has cleared previous-generation timestamps. Do not label
            // old host ticks as belonging to the new generation.
            transition = event(.discontinuity, generation: frame.streamGeneration)
        }

        let operationEpoch = invalidationEpoch
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
            let ticket = operationEpoch
            var finals: [FinalTranscriptEvent] = transition.map { [$0] } ?? []
            while pendingMono.count >= window {
                let piece = Array(pendingMono.prefix(window))
                pendingMono.removeFirst(window)
                let mono16k = try converter.normalizeWindow(piece, from: frame.sampleRate)
                let reachedEou = try await backend.accept(mono16k)
                guard !cancelled, !processingInterrupted,
                      ticket == invalidationEpoch,
                      generation == frame.streamGeneration else {
                    // Do not publish an old accept() result or retain samples
                    // after a concurrent ingest/cancel invalidated this call.
                    if processingInterrupted, !cancelled,
                       ticket == invalidationEpoch {
                        await reset()
                    }
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
            // An older backend request may fail only AFTER cancellation or
            // a newer generation has activated. Never erase that newer state.
            guard !cancelled, operationEpoch == invalidationEpoch,
                  generation == nil || generation == frame.streamGeneration
            else { return [] }
            if processingInterrupted {
                await reset()
                return []
            }
            let marker = event(.unavailable, generation: frame.streamGeneration)
            await reset()
            return [marker]
        }
    }

    /// A caller ends an explicitly authorized capture. Any remaining samples
    /// are flushed on the worker, never from a HAL callback. No text from a
    /// cancelled/discontinuous generation is reconstructed from stale buffers.
    public func finishAtStop() async -> FinalTranscriptEvent? {
        if processingInProgress {
            // A timer stop overlapping CoreML must still invalidate any
            // previous answer; returning nil would silently drop that terminal.
            // Another concurrent frame already published a discontinuity.
            let firstInterruption = !processingInterrupted
            processingInterrupted = true
            guard firstInterruption, authorized, !cancelled,
                  let generation = generation ?? transitionGeneration else { return nil }
            return event(.unavailable, generation: generation)
        }
        guard authorized, !cancelled, !resetInProgress,
              let generation, let sampleRate else {
            await reset()
            return nil
        }
        processingInProgress = true
        defer {
            processingInProgress = false
            processingInterrupted = false
        }
        let ticket = invalidationEpoch
        do {
            guard utteranceFrames > 0 else {
                await reset()
                return nil
            }
            var reachedEou = false
            if !pendingMono.isEmpty {
                let audio = try converter.normalizeWindow(pendingMono, from: sampleRate)
                reachedEou = try await backend.accept(audio)
                guard !cancelled, !processingInterrupted,
                      ticket == invalidationEpoch,
                      self.generation == generation else {
                    if processingInterrupted, !cancelled,
                       ticket == invalidationEpoch {
                        await reset()
                    }
                    return nil
                }
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
            guard !cancelled, ticket == invalidationEpoch,
                  self.generation == generation else { return nil }
            if processingInterrupted {
                await reset()
                return nil
            }
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
        // The caller owns processingInProgress across every backend await.
        guard processingInProgress, !cancelled else { return nil }
        do {
            let result = try await backend.finish()
            guard !cancelled, ticket == invalidationEpoch,
                  self.generation == generation else { return nil }
            if processingInterrupted {
                await reset()
                return nil
            }
            let text = result.trimmingCharacters(in: .whitespacesAndNewlines)
            // This resets decoder context, not loaded model weights.
            await backend.reset()
            guard !cancelled, ticket == invalidationEpoch,
                  self.generation == generation else { return nil }
            if processingInterrupted {
                await reset()
                return nil
            }
            segmentID &+= 1
            // A successful finish() with zero recognized words is NOT
            // silence: the downstream turn adapter must receive an explicit
            // terminal and invalidate any prior answer. Represent it as a
            // final event whose text is exactly "" (never fabricated words).
            // The native wire validator maps this to blank_final; no actual
            // Swift -> Python transport is implemented by this slice.
            let final = event(.final, generation: generation, text: text)
            pendingMono.removeAll(keepingCapacity: true)
            utteranceFrames = 0
            startHostTime = nil
            endHostTime = nil
            return final
        } catch {
            guard !cancelled, ticket == invalidationEpoch,
                  self.generation == generation else { return nil }
            if processingInterrupted {
                // finish() can throw while a second call waits. Reset the
                // decoder before returning, but never expose old text.
                await reset()
                return nil
            }
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
