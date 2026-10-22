import Foundation
import RelayAudioBuffer
import XCTest
@testable import RelayLocalASR

/// Fake recognizer means model weights and inference are never requested by CI.
actor FakeEou: LocalEouRecognizer {
    private(set) var accepted = 0
    private(set) var resets = 0
    private(set) var finished = 0
    private(set) var captured = [Float]()
    var eouAtAccept: Int?
    var throwOnAccept = false

    init(eouAt: Int? = nil, throwOnAccept: Bool = false) {
        eouAtAccept = eouAt
        self.throwOnAccept = throwOnAccept
    }

    func accept(_ mono16kSamples: [Float]) async throws -> Bool {
        if throwOnAccept { throw NSError(domain: "fixture", code: 12) }
        accepted += 1
        captured.append(contentsOf: mono16kSamples)
        return eouAtAccept == accepted
    }

    func finish() async throws -> String {
        finished += 1
        return "what is the difference between where and having"
    }

    func reset() async {
        resets += 1
    }
}

final class LocalASRWorkerTests: XCTestCase {
    /// Construct the actual owned capture packets using the merged SPSC ring.
    /// This exercises source/sequence/ownership without exposing an internal
    /// PCMFrame initializer from another SwiftPM package.
    private func packet(
        _ ring: OwnedPCMQueue, frames: Int = 2048,
        sampleRate: Double = 16_000, generation: UInt64 = 1,
        value: Float = 0.125
    ) throws -> PCMFrame {
        let samples = [Float](repeating: value, count: frames)
        let accepted = samples.withUnsafeBufferPointer { src in
            ring.enqueuePlanar(
                first: src.baseAddress!, frames: frames,
                sampleRate: sampleRate, hostTime: UInt64(1000 + frames),
                streamGeneration: generation
            )
        }
        XCTAssertTrue(accepted)
        return try XCTUnwrap(ring.dequeue())
    }

    func testEOUEmitsFinalOnlyAfterRecognizerSignalsEnd() async throws {
        let fake = FakeEou(eouAt: 1)
        let ring = try OwnedPCMQueue(source: .remoteAudio)
        let worker = PCMTranscriptWorker(
            source: .remoteAudio, authorizedCapture: true, backend: fake
        )
        let a = await worker.ingest(try packet(ring))
        let b = await worker.ingest(try packet(ring))
        XCTAssertTrue(a.isEmpty)
        XCTAssertTrue(b.isEmpty)
        let c = await worker.ingest(try packet(ring))
        XCTAssertEqual(c.count, 1)
        let final = try XCTUnwrap(c.first)
        XCTAssertEqual(final.status, .final)
        XCTAssertEqual(final.source, .remoteAudio)
        XCTAssertEqual(final.streamGeneration, 1)
        XCTAssertEqual(final.revision, 1)
        XCTAssertEqual(final.confidence, nil)
        XCTAssertEqual(final.text, "what is the difference between where and having")
        XCTAssertGreaterThan(final.finalizedUptimeNanoseconds, 0)
        let finished = await fake.finished
        XCTAssertEqual(finished, 1)
    }

    func testFinishAtStopFlushesOnlyRecognizedEOU() async throws {
        let fake = FakeEou(eouAt: 1)
        let ring = try OwnedPCMQueue(source: .microphone)
        let worker = PCMTranscriptWorker(
            source: .microphone, authorizedCapture: true, backend: fake
        )
        let isEmptyResult1 = await worker.ingest(try packet(ring))
        XCTAssertTrue(isEmptyResult1.isEmpty)
        let stopped = await worker.finishAtStop()
        let final = try XCTUnwrap(stopped)
        XCTAssertEqual(final.status, .final)
        XCTAssertEqual(final.source, .microphone)
        XCTAssertEqual(final.text, "what is the difference between where and having")
        let nilResult6 = await worker.finishAtStop()
        XCTAssertNil(nilResult6)
    }

    func testTimerStoppedMidQuestionIsUnavailableNotFinal() async throws {
        let fake = FakeEou() // never emits EOU.
        let ring = try OwnedPCMQueue(source: .microphone)
        let worker = PCMTranscriptWorker(
            source: .microphone, authorizedCapture: true, backend: fake
        )
        let before = await worker.ingest(try packet(ring))
        XCTAssertTrue(before.isEmpty)
        let result = await worker.finishAtStop()
        XCTAssertEqual(result?.status, .unavailable)
        XCTAssertNil(result?.text)
        let count = await fake.finished
        XCTAssertEqual(count, 0)
    }

    func testMissingPacketCancelsAndNeverReassemblesOldUtterance() async throws {
        let fake = FakeEou()
        let ring = try OwnedPCMQueue(source: .remoteAudio)
        let worker = PCMTranscriptWorker(
            source: .remoteAudio, authorizedCapture: true, backend: fake
        )
        let isEmptyResult2 = await worker.ingest(try packet(ring))
        XCTAssertTrue(isEmptyResult2.isEmpty)
        _ = try packet(ring) // Lost packet with seq #2.
        let lost = await worker.ingest(try packet(ring)) // seq #3.
        XCTAssertEqual(lost.map(\.status), [.discontinuity])
        XCTAssertEqual(lost.first?.text, nil)
        let isEmptyResult3 = await worker.ingest(try packet(ring))
        XCTAssertTrue(isEmptyResult3.isEmpty)
        let resets = await fake.resets
        XCTAssertGreaterThan(resets, 0)
    }

    func testGenerationResetRejectsLateOldAudio() async throws {
        let fake = FakeEou()
        let ring = try OwnedPCMQueue(source: .remoteAudio)
        let worker = PCMTranscriptWorker(
            source: .remoteAudio, authorizedCapture: true, backend: fake
        )
        let old = try packet(ring, generation: 1)
        let isEmptyResult4 = await worker.ingest(old)
        XCTAssertTrue(isEmptyResult4.isEmpty)
        let jump = await worker.ingest(try packet(ring, generation: 2))
        XCTAssertEqual(jump.map(\.status), [.discontinuity])
        let stale = await worker.ingest(old)
        XCTAssertTrue(stale.isEmpty)
        let isEmptyResult5 = await worker.ingest(try packet(ring, generation: 2))
        XCTAssertTrue(isEmptyResult5.isEmpty)
    }

    func testExplicitCancelPermanentlyStopsOldWorker() async throws {
        let fake = FakeEou(eouAt: 1)
        let ring = try OwnedPCMQueue(source: .remoteAudio)
        let worker = PCMTranscriptWorker(
            source: .remoteAudio, authorizedCapture: true, backend: fake
        )
        let first = await worker.ingest(try packet(ring, generation: 7))
        XCTAssertTrue(first.isEmpty)
        await worker.cancel()

        // Even a higher generation cannot revive a cancelled capture worker.
        let late = await worker.ingest(try packet(ring, generation: 7))
        let future = await worker.ingest(try packet(ring, generation: 8))
        XCTAssertTrue(late.isEmpty)
        XCTAssertTrue(future.isEmpty)
        let stopped = await worker.finishAtStop()
        XCTAssertNil(stopped)
        let used = await fake.accepted
        XCTAssertEqual(used, 0)
        // A new authorized capture requires a new worker instance.
    }

    func testCancellationBeforeFirstQueuedPacketFailsClosed() async throws {
        let fake = FakeEou(eouAt: 1)
        let ring = try OwnedPCMQueue(source: .microphone)
        let worker = PCMTranscriptWorker(
            source: .microphone, authorizedCapture: true, backend: fake
        )
        await worker.cancel()
        // The producer may have buffered audio before stop took effect.
        let queued = await worker.ingest(try packet(ring, generation: 1))
        XCTAssertTrue(queued.isEmpty)
        let stopped = await worker.finishAtStop()
        XCTAssertNil(stopped)
        let used = await fake.accepted
        XCTAssertEqual(used, 0)
    }

    func testUnauthorizedAndWrongSourceNeverCallASR() async throws {
        let fake = FakeEou(eouAt: 1)
        let ring = try OwnedPCMQueue(source: .microphone)
        let pkt = try packet(ring)
        let unauthorized = PCMTranscriptWorker(
            source: .microphone, authorizedCapture: false, backend: fake
        )
        let wrong = PCMTranscriptWorker(
            source: .remoteAudio, authorizedCapture: true, backend: fake
        )
        let a = await unauthorized.ingest(pkt)
        let b = await wrong.ingest(pkt)
        XCTAssertEqual(a.map(\.status), [.unavailable])
        XCTAssertEqual(b.map(\.status), [.unavailable])
        XCTAssertTrue(a.allSatisfy { $0.text == nil })
        XCTAssertTrue(b.allSatisfy { $0.text == nil })
        let accepted = await fake.accepted
        XCTAssertEqual(accepted, 0)
    }

    func testBackendFailureReturnsUnavailableWithoutLeakingText() async throws {
        let fake = FakeEou(throwOnAccept: true)
        let ring = try OwnedPCMQueue(source: .remoteAudio)
        let worker = PCMTranscriptWorker(
            source: .remoteAudio, authorizedCapture: true, backend: fake
        )
        _ = await worker.ingest(try packet(ring))
        _ = await worker.ingest(try packet(ring))
        let output = await worker.ingest(try packet(ring))
        XCTAssertEqual(output.map(\.status), [.unavailable])
        XCTAssertNil(output.first?.text)
    }

    func testConverterProduces16kMonoWithFiniteAmplitude() throws {
        let converter = ASRMonoConverter()
        let ring = try OwnedPCMQueue(source: .remoteAudio)
        let hz = 440.0
        let sr = 48_000.0
        var pcm = [Float]()
        pcm.reserveCapacity(4096)
        for i in 0..<4096 {
            pcm.append(Float(0.05 * sin(2.0 * .pi * hz * Double(i) / sr)))
        }
        let ok = pcm.withUnsafeBufferPointer { src in
            ring.enqueuePlanar(
                first: src.baseAddress!, frames: pcm.count,
                sampleRate: sr, hostTime: 456,
                streamGeneration: 1
            )
        }
        XCTAssertTrue(ok)
        let frame = try XCTUnwrap(ring.dequeue())
        let mono = try converter.mono(frame)
        let out = try converter.normalizeWindow(mono, from: sr)
        XCTAssertGreaterThan(out.count, 900)
        XCTAssertLessThan(out.count, 2000)
        XCTAssertTrue(out.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(out.map { Double($0 * $0) }.reduce(0, +), 0)
    }

    func testStereoDownmixDoesNotPretendSpeakerDiarization() throws {
        let converter = ASRMonoConverter()
        let ring = try OwnedPCMQueue(source: .remoteAudio)
        let one: [Float] = [0.2, 0.2, 0.2, 0.2]
        let two: [Float] = [0.0, 0.0, 0.0, 0.0]
        let ok = one.withUnsafeBufferPointer { a in
            two.withUnsafeBufferPointer { b in
                ring.enqueuePlanar(
                    first: a.baseAddress!, second: b.baseAddress!,
                    frames: 4, sampleRate: 16_000,
                    hostTime: 8, streamGeneration: 5
                )
            }
        }
        XCTAssertTrue(ok)
        let mono = try converter.mono(try XCTUnwrap(ring.dequeue()))
        XCTAssertEqual(mono, [0.1, 0.1, 0.1, 0.1])
    }
}
