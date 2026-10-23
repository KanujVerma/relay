import Foundation
import Testing
import RelayNativeSession
@testable import RelayContextComposition

@MainActor private final class CaptureLatch {
    var continuation: CheckedContinuation<[Data], Never>?
    var entered = false
    func capture() async -> [Data] {
        entered = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(returning: [Data("late context".utf8)]); continuation = nil }
}

@Suite @MainActor struct OrderedContextForwarderTests {
    private func event(_ sequence: UInt64, _ kind: SessionEventKind = .eou, generation: UInt64 = 2) -> NativeSessionEvent {
        NativeSessionEvent(captureSessionID: UUID(uuidString:"00000000-0000-0000-0000-000000000001")!, sessionEpoch: 1,
            eventSequence: sequence, presentationGeneration: generation, kind: kind, sourceCode: 2,
            streamGeneration: 1, emittedUptimeNanoseconds: 1, payload: [:], requestID: kind == .eou ? UUID():nil)
    }
    @Test func obsoleteCaptureCannotReorderOriginalNativeEvents() async throws {
        let latch = CaptureLatch(); var sent: [NativeSessionEvent] = []; var frames: [Data] = []
        let pump = OrderedContextForwarder(shouldCapture: { _ in true }, capture: { _ in await latch.capture() },
            send: { event, context in sent.append(event); frames += context }, onFailure: {})
        let original = event(3), onset = event(4, .speechStarted, generation: 3)
        try pump.enqueue(original)
        for _ in 0..<20 where !latch.entered { await Task.yield() }
        #expect(latch.entered); #expect(sent.isEmpty)
        try pump.enqueue(onset)
        #expect(sent == [original, onset]); #expect(frames.isEmpty)
        latch.finish(); for _ in 0..<10 { await Task.yield() }
        #expect(sent == [original, onset]); #expect(frames.isEmpty)
    }
    @Test func contextIsDeliveredImmediatelyBeforeItsOriginalEvent() async throws {
        var sent: [NativeSessionEvent] = []; var contextCounts: [Int] = []
        let pump = OrderedContextForwarder(shouldCapture: { _ in true }, capture: { _ in [Data("context".utf8)] },
            send: { event, context in sent.append(event); contextCounts.append(context.count) }, onFailure: {})
        let original = event(3)
        try pump.enqueue(original)
        for _ in 0..<20 where sent.isEmpty { await Task.yield() }
        #expect(sent == [original]); #expect(contextCounts == [1]); #expect(pump.isIdle)
    }
    @Test func retirementPreventsAnUncooperativeCaptureFromSending() async throws {
        let latch = CaptureLatch(); var sent: [NativeSessionEvent] = []
        let pump = OrderedContextForwarder(shouldCapture: { _ in true }, capture: { _ in await latch.capture() },
            send: { event, _ in sent.append(event) }, onFailure: {})
        try pump.enqueue(event(3)); for _ in 0..<20 where !latch.entered { await Task.yield() }
        pump.retire(); latch.finish(); for _ in 0..<10 { await Task.yield() }
        #expect(sent.isEmpty); #expect(pump.isIdle)
    }
    @Test func queueOverflowRetiresRatherThanDroppingAControl() async throws {
        let latch = CaptureLatch(); var failed = false; var sent = 0
        let pump = OrderedContextForwarder(maximumFrames: 2, shouldCapture: { _ in true }, capture: { _ in await latch.capture() },
            send: { _, _ in sent += 1 }, onFailure: { failed = true })
        try pump.enqueue(event(3)); for _ in 0..<20 where !latch.entered { await Task.yield() }
        try pump.enqueue(event(4, .speechEnded))
        #expect(throws: ContextForwardingError.overflow) { try pump.enqueue(event(5, .speechEnded)) }
        #expect(failed); latch.finish(); for _ in 0..<10 { await Task.yield() }
        #expect(sent == 0)
    }
    @Test func captureDeadlineForwardsQuestionWithoutWaitingForOSQuiescence() async throws {
        let latch=CaptureLatch();var sent=0;var contextCount=0
        let pump=OrderedContextForwarder(captureBudgetNanoseconds:5_000_000,shouldCapture:{_ in true},capture:{_ in await latch.capture()},
            send:{_,context in sent+=1;contextCount+=context.count},onFailure:{})
        try pump.enqueue(event(3));try await Task.sleep(for:.milliseconds(30))
        #expect(sent==1);#expect(contextCount==0);#expect(pump.isIdle)
        latch.finish();for _ in 0..<10 { await Task.yield() }
        #expect(sent==1)
    }

}
