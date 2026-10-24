import CoreFoundation
import Darwin
import Foundation
import XCTest
@testable import RelaySessionPanel

private final class FailingLearningPreferenceBytes:LearningPreferenceBytes,@unchecked Sendable {
    private let lock=NSLock();private var data:Data?
    func load()throws->Data?{lock.withLock{data}}
    func save(_ value:Data)throws{throw HistoryError.unavailable}
}
@MainActor final class LearningCFPreferencesTests:XCTestCase {
    private let key="relay.learning.control-receipt.v1"
    private var childMode:Bool{ProcessInfo.processInfo.environment["RELAY_LEARNING_CF_CHILD"]=="1"}
    private func domain()->String{"com.relay.fixture.learning."+UUID().uuidString.lowercased()}
    private func clear(_ domain:String){CFPreferencesSetAppValue(key as CFString,nil,domain as CFString);_ = CFPreferencesAppSynchronize(domain as CFString)}
    private func witness(domain:String,expected:LearningControlReceipt)async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("relay-learning-control-child-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false);defer{try? FileManager.default.removeItem(at:root)}
        let proof=root.appendingPathComponent("receipt.json"),child=Process()
        child.executableURL=URL(fileURLWithPath:"/usr/bin/xcrun")
        child.arguments=["xctest","-XCTest","RelaySessionPanelTests.LearningCFPreferencesTests/testOwnedFreshProcessWitness",Bundle(for:LearningCFPreferencesTests.self).bundleURL.path]
        var environment=ProcessInfo.processInfo.environment
        environment["RELAY_LEARNING_CF_CHILD"]="1";environment["RELAY_LEARNING_CF_DOMAIN"]=domain;environment["RELAY_LEARNING_CF_PROOF"]=proof.path
        child.environment=environment
        let output=Pipe();child.standardOutput=output;child.standardError=output
        var launchError:(any Error)?
        let timeout=Task{@MainActor in
            try? await Task.sleep(for:.seconds(10));guard !Task.isCancelled,child.isRunning else{return}
            child.terminate();try? await Task.sleep(for:.seconds(1));if child.isRunning{_ = Darwin.kill(child.processIdentifier,SIGKILL)}
        }
        await withCheckedContinuation{(continuation:CheckedContinuation<Void,Never>) in
            child.terminationHandler={_ in continuation.resume()}
            do{try child.run()}catch{launchError=error;continuation.resume()}
        }
        timeout.cancel();if let launchError{throw launchError}
        let log=output.fileHandleForReading.readDataToEndOfFile()
        XCTAssertEqual(child.terminationStatus,0,String(decoding:log.prefix(8192),as:UTF8.self))
        let actual=try HistoryJSON.decode(LearningControlReceipt.self,Data(contentsOf:proof))
        XCTAssertEqual(actual,expected)
    }
    func testActualCommittedReceiptAndPendingDenialSurviveAnOwnedFreshProcess()async throws{
        guard !childMode else{return}
        let domain=domain();defer{clear(domain)}
        let controls=CFPreferencesLearningControls(domain:domain)
        let on=LearningControlRecord(revision:UUID(),enabled:true,suppressedRuleIDs:["technical:concise_lead"])
        let committed=try await controls.commit(on);try await witness(domain:domain,expected:committed)
        let pending=LearningPendingControl(target:LearningControlRecord(revision:UUID(),enabled:false,suppressedRuleIDs:on.suppressedRuleIDs),expectedRevision:on.revision,clearExamples:true)
        let denied=try await controls.deny(pending)
        XCTAssertFalse(denied.enabled);XCTAssertNotNil(denied.pending);try await witness(domain:domain,expected:denied)
    }
    func testInertConstructionAndMissingReceiptReadDoNotCreateOwnedControlValue()async throws{
        guard !childMode else{return}
        let domain=domain();defer{clear(domain)}
        XCTAssertNil(CFPreferencesCopyAppValue(key as CFString,domain as CFString))
        let controls=CFPreferencesLearningControls(domain:domain)
        XCTAssertNil(CFPreferencesCopyAppValue(key as CFString,domain as CFString))
        let receipt=try await controls.read();XCTAssertFalse(receipt.enabled);XCTAssertNil(receipt.pending)
        XCTAssertNil(CFPreferencesCopyAppValue(key as CFString,domain as CFString))
    }
    func testFailedByteWriteAndMalformedActualPreferenceNeverIssuePositiveReceipt()async throws{
        guard !childMode else{return}
        let failing=CFPreferencesLearningControls(bytes:FailingLearningPreferenceBytes())
        do{_=try await failing.commit(LearningControlRecord(revision:UUID(),enabled:true,suppressedRuleIDs:[]));XCTFail("Failure is not an acknowledgment")}catch{}
        let domain=domain();defer{clear(domain)}
        CFPreferencesSetAppValue(key as CFString,"not a control receipt" as CFString,domain as CFString)
        XCTAssertTrue(CFPreferencesAppSynchronize(domain as CFString))
        do{_=try await CFPreferencesLearningControls(domain:domain).read();XCTFail("Malformed control cannot become default-on or default-off success")}catch{}
    }
    func testOwnedFreshProcessWitness()async throws{
        let environment=ProcessInfo.processInfo.environment
        guard childMode,let domain=environment["RELAY_LEARNING_CF_DOMAIN"],domain.hasPrefix("com.relay.fixture.learning."),
              let path=environment["RELAY_LEARNING_CF_PROOF"],URL(fileURLWithPath:path).lastPathComponent=="receipt.json" else{throw XCTSkip("Owned control-receipt subprocess only")}
        let receipt=try await CFPreferencesLearningControls(domain:domain).read()
        try HistoryJSON.encode(receipt).write(to:URL(fileURLWithPath:path),options:.atomic)
    }
}
