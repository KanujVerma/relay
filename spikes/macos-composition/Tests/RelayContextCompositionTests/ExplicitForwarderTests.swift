import Foundation
import Testing
import RelayNativeSession
@testable import RelayContextComposition

private actor QuietUserVAD:SpeechActivityDetector {
    nonisolated let chunkSamples=512
    func accept(_ samples:[Float])async throws->[SpeechBoundary]{[]}
}
private actor QuietUserRecognizer:ActivityRecognizer {
    func recognize(_ samples:[Float])async throws->String{"Explain queues."}
}
@MainActor private final class UserCaptureLatch {
    var entered=false
    var continuation:CheckedContinuation<[Data],Never>?
    func capture()async->[Data]{entered=true;return await withCheckedContinuation{continuation=$0}}
    func finish(){continuation?.resume(returning:[]);continuation=nil}
}

@Suite @MainActor struct ExplicitForwarderTests {
    private func controller()throws->NativeSessionController {
        let value=NativeSessionController(onEvent:{_ in})
        try value.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,
            components:[2:SourceComponents(vad:QuietUserVAD(),recognizer:QuietUserRecognizer())])
        return value
    }
    @Test func cancellationRetiresOriginalBeforeReleasingHeldUserAndPreservesLaterAudioOrder()async throws {
        let native=try controller(),latch=UserCaptureLatch();var order:[String]=[]
        let request=try native.issueUserQuestion(expectedLease:try #require(native.authority.snapshot()),intent:.ask,
            question:"Explain queues.",baseRequestID:nil,enqueue:{_ in})
        let target=PanelRequestBinding(lease:request.lease,requestID:request.requestID,eventSequence:request.anchorEventSequence)
        let ports=ExplicitContextForwardingPorts(shouldCapture:{_ in true},capture:{_ in await latch.capture()},
            retire:{binding in #expect(binding==target);order.append("retired")},
            sendQuestion:{value,context in #expect(value==request);#expect(context.isEmpty);order.append("user")},
            sendCancellation:{_ in order.append("cancel")})
        let pump=OrderedContextForwarder(shouldCapture:{_ in false},capture:{_ in []},
            send:{_,_ in order.append("audio")},onFailure:{Issue.record("unexpected forwarding failure")},explicit:ports)
        try pump.enqueueUserQuestion(request)
        for _ in 0..<30 where !latch.entered{await Task.yield()}
        #expect(latch.entered);#expect(order.isEmpty)
        let stopped=try native.issueAnswerCancellation(expectedLease:request.lease,targetRequestID:request.requestID,enqueue:{_ in})
        try pump.enqueueAnswerCancellation(stopped,retiring:target)
        #expect(order==["retired","user","cancel"])
        let later=NativeSessionEvent(captureSessionID:request.lease.captureSessionID,sessionEpoch:1,eventSequence:2,
            presentationGeneration:stopped.lease.presentationGeneration+1,kind:.speechStarted,sourceCode:2,
            streamGeneration:1,emittedUptimeNanoseconds:1,payload:[:])
        try pump.enqueue(later);#expect(order==["retired","user","cancel","audio"])
        latch.finish();await Task.yield();#expect(order.count==4)
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
    }
    @Test func explicitPortsAreRequiredAndFailureCannotReleaseHeldFrame()async throws {
        let native=try controller()
        let request=try native.issueUserQuestion(expectedLease:try #require(native.authority.snapshot()),intent:.ask,
            question:"Explain queues.",baseRequestID:nil,enqueue:{_ in})
        let pump=OrderedContextForwarder(shouldCapture:{_ in false},capture:{_ in []},send:{_,_ in},onFailure:{})
        #expect(throws:ContextForwardingError.self){try pump.enqueueUserQuestion(request)}
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
    }
}
