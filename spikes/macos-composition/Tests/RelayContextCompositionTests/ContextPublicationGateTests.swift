import Foundation
import Testing
import RelayNativeSession
@testable import RelayContextComposition

@Suite @MainActor struct ContextPublicationGateTests {
    @Test func changedLeaseDuringObservationCannotCommitAnAnswer() async throws {
        let authority=SessionPresentationAuthority();let lease=try authority.start()
        let request=PanelRequestBinding(lease:lease,requestID:UUID(),eventSequence:3)
        let gate=ContextPublicationGate(authority:authority);gate.bind(request)
        var continuation:CheckedContinuation<Bool,Never>?
        var checked=false;var commits=0
        gate.publish(request,validate:{ checked=true;return await withCheckedContinuation { continuation=$0 } },owns:{true},commit:{commits+=1})
        for _ in 0..<20 where !checked { await Task.yield() }
        authority.invalidate();continuation?.resume(returning:true)
        for _ in 0..<10 { await Task.yield() }
        #expect(commits==0)
    }
    @Test func successfulReobservationStillRequiresSynchronousSourceOwnership() async throws {
        let authority=SessionPresentationAuthority();let request=PanelRequestBinding(lease:try authority.start(),requestID:UUID(),eventSequence:3)
        let gate=ContextPublicationGate(authority:authority);gate.bind(request)
        var owns=true;var commits=0
        gate.publish(request,validate:{owns=false;return true},owns:{owns},commit:{commits+=1})
        for _ in 0..<10 { await Task.yield() }
        #expect(commits==0)
    }
    @Test func oneTerminalObservationAndRetirementNeverRevivesIt() async throws {
        let authority=SessionPresentationAuthority();let request=PanelRequestBinding(lease:try authority.start(),requestID:UUID(),eventSequence:3)
        let gate=ContextPublicationGate(authority:authority);gate.bind(request)
        var checks=0;var commits=0
        let validate:@MainActor () async -> Bool = { checks+=1;return true }
        gate.publish(request,validate:validate,owns:{true},commit:{commits+=1})
        gate.publish(request,validate:validate,owns:{true},commit:{commits+=1})
        for _ in 0..<10 { await Task.yield() }
        #expect(checks==1);#expect(commits==1)
        gate.retire();gate.publish(request,validate:validate,owns:{true},commit:{commits+=1})
        for _ in 0..<10 { await Task.yield() }
        #expect(commits==1)
    }
    @Test func terminalDeadlineRejectsWithoutWaitingForUncooperativeObservation() async throws {
        let authority=SessionPresentationAuthority();let request=PanelRequestBinding(lease:try authority.start(),requestID:UUID(),eventSequence:3)
        let gate=ContextPublicationGate(authority:authority);gate.bind(request)
        var continuation:CheckedContinuation<Bool,Never>?;var rejected=0;var commits=0
        gate.publish(request,budgetNanoseconds:5_000_000,validate:{await withCheckedContinuation{continuation=$0}},owns:{true},commit:{commits+=1},rejected:{rejected+=1})
        for _ in 0..<100 where rejected==0{try await Task.sleep(for:.milliseconds(5))}
        #expect(rejected==1);#expect(commits==0)
        continuation?.resume(returning:true);for _ in 0..<10{await Task.yield()}
        #expect(rejected==1);#expect(commits==0)
    }

}
