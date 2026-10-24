import Darwin
import Foundation
import XCTest
import RelayNativeSession
import RelaySessionPanel
import RelayContextComposition
@testable import RelayPanelSession

private final class OwnerRetirementFlag:@unchecked Sendable {
    private let lock=NSLock();private var done=false
    func finish(){lock.withLock{done=true}}
    var finished:Bool{lock.withLock{done}}
}
private actor LockQuietVAD:SpeechActivityDetector {
    nonisolated let chunkSamples=512
    func accept(_ samples:[Float])async throws->[SpeechBoundary]{[]}
}
private actor LockQuietASR:ActivityRecognizer {
    func recognize(_ samples:[Float])async throws->String{""}
}

@MainActor final class ConversationOwnerLockOrderTests:XCTestCase {
    func testActualPanelCommitAndCurrentFailureDoNotDeadlock()async throws{try await runChild("active")}
    func testActualPanelCommitIgnoresStaleHelperFailure()async throws{try await runChild("stale")}
    func testReservedRetirementBlocksReusedCaptureUntilOriginalFailureFinishes()async throws{try await runChild("replacement")}

    private func runChild(_ schedule:String)async throws {
        if ProcessInfo.processInfo.environment["RELAY_OWNER_RETIREMENT_CHILD"]==schedule{
            try await exercise(schedule);return
        }
        let testName=schedule=="active" ? "testActualPanelCommitAndCurrentFailureDoNotDeadlock":schedule=="stale" ? "testActualPanelCommitIgnoresStaleHelperFailure":"testReservedRetirementBlocksReusedCaptureUntilOriginalFailureFinishes"
        let child=Process(),finished=OwnerRetirementFlag(),errors=Pipe()
        child.executableURL=URL(fileURLWithPath:"/usr/bin/xcrun")
        child.arguments=["xctest","-XCTest","RelaySessionApplicationTests.ConversationOwnerLockOrderTests/"+testName,Bundle(for:Self.self).bundleURL.path]
        var environment=["PATH":"/usr/bin:/bin","RELAY_OWNER_RETIREMENT_CHILD":schedule]
        for key in ["DYLD_LIBRARY_PATH","DYLD_FRAMEWORK_PATH","DEVELOPER_DIR","TMPDIR"]{
            if let value=ProcessInfo.processInfo.environment[key]{environment[key]=value}
        }
        child.environment=environment;child.standardOutput=FileHandle.nullDevice;child.standardError=errors
        child.terminationHandler={_ in finished.finish()}
        try child.run();try errors.fileHandleForWriting.close()
        for _ in 0..<2500{if finished.finished{break};try await Task.sleep(for:.milliseconds(2))}
        if !finished.finished{child.terminate()}
        for _ in 0..<500{if finished.finished{break};try await Task.sleep(for:.milliseconds(2))}
        guard finished.finished else{_=Darwin.kill(child.processIdentifier,SIGKILL);XCTFail("Watchdog child did not exit");return}
        let diagnostic=String(data:errors.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8) ?? ""
        XCTAssertTrue(diagnostic.contains("OWNER_RETIREMENT_CHILD_STARTED \(schedule)"),"Child must execute the requested actual schedule")
        XCTAssertEqual(child.terminationStatus,0,"Actual panel/owner schedule \(schedule): \(diagnostic)")
    }
    private func exercise(_ schedule:String)async throws {
        FileHandle.standardError.write(Data("OWNER_RETIREMENT_CHILD_STARTED \(schedule)\n".utf8))
        let finished=OwnerRetirementFlag(),failureFinished=OwnerRetirementFlag()
        DispatchQueue.global().asyncAfter(deadline:.now()+3){
            if !finished.finished{
                FileHandle.standardError.write(Data("OWNER_RETIREMENT_WATCHDOG \(schedule)\n".utf8));Darwin._exit(86)
            }
        }
        let box=ConversationOwnerBox(),id=UUID()
        let helper=HelperTransport(root:URL(fileURLWithPath:"/"),python:URL(fileURLWithPath:"/usr/bin/false"),mode:.noInference,onFrame:{_ in},onFailure:{})
        box.activateHelper(id)
        let capture:NativeSessionController?
        let owner:ConversationOwner
        let request:NativeUserQuestionRequest
        if schedule=="replacement" {
            let authority=SessionPresentationAuthority()
            // The original and replacement deliberately share the exact capture
            // controller/authority, as actual capture restarts do.
            let source=NativeSessionController(authority:authority,onEvent:{_ in});capture=source
            owner=ConversationOwner(helper:helper,helperIdentity:id,authority:authority,source:source)
            XCTAssertTrue(box.install(owner))
            try source.start(selectedBundleID:nil,microphoneEnabled:true,components:[1:SourceComponents(vad:LockQuietVAD(),recognizer:LockQuietASR())])
            request=try source.issueUserQuestion(expectedLease:try XCTUnwrap(authority.snapshot()),intent:.ask,question:"Explain queues.",baseRequestID:nil,enqueue:{_ in})
        }else{
            capture=nil;owner=ConversationOwner(helper:helper,helperIdentity:id,preparationIntent:UUID())
            XCTAssertTrue(box.install(owner));let native=try XCTUnwrap(owner.assistantController)
            let opening=try native.begin(enqueue:{owner.record($0.lease)});try native.completeOpen(opening)
            request=try native.issueUserQuestion(expectedLease:opening.lease,intent:.ask,question:"Explain queues.",baseRequestID:nil,enqueue:{_ in})
        }
        let trigger=DispatchSemaphore(value:0),started=DispatchSemaphore(value:0),replacementID=UUID()
        DispatchQueue.global().async{
            trigger.wait();started.signal();_=box.failHelper(schedule=="stale" ? UUID():id);failureFinished.finish()
        }
        owner.presentation.panel.onChange={
            trigger.signal();XCTAssertEqual(started.wait(timeout:.now()+1),.success)
            if schedule=="stale"{
                while !failureFinished.finished{Thread.sleep(forTimeInterval:0.001)}
            }else{
                // The original implementation holds the owner lock while
                // waiting for this actual panel authority lock. The child
                // watchdog makes that regression bounded instead of hanging CI.
                while !owner.isRetired{Thread.sleep(forTimeInterval:0.001)}
            }
            XCTAssertTrue(box.current === owner)
            if let capture{
                XCTAssertFalse(box.failHelper(id),"Duplicate current failure must not start a second retirement")
                box.activateHelper(replacementID);box.remove(owner)
                let next=ConversationOwner(helper:helper,helperIdentity:replacementID,authority:owner.authority,source:capture)
                XCTAssertFalse(box.install(next),"New helper generation cannot release original capture retirement")
            }
        }
        owner.presentation.panel.bind(PanelRequestBinding(lease:request.lease,requestID:request.requestID,eventSequence:request.anchorEventSequence))
        owner.presentation.panel.onChange=nil
        for _ in 0..<1000{if failureFinished.finished{break};try await Task.sleep(for:.milliseconds(1))}
        XCTAssertTrue(failureFinished.finished)
        if schedule=="stale"{XCTAssertEqual(owner.authority.snapshot(),request.lease);XCTAssertFalse(owner.isRetired)}
        else{XCTAssertNil(owner.authority.snapshot());XCTAssertTrue(owner.isRetired)}
        if let capture{
            await capture.waitForQuiescence();capture.finishStop(quiesced:true)
            let next=ConversationOwner(helper:helper,helperIdentity:replacementID,authority:owner.authority,source:capture)
            XCTAssertTrue(box.install(next))
            try capture.start(selectedBundleID:nil,microphoneEnabled:true,components:[1:SourceComponents(vad:LockQuietVAD(),recognizer:LockQuietASR())])
            let fresh=try XCTUnwrap(next.authority.snapshot())
            XCTAssertFalse(box.failHelper(id));XCTAssertEqual(next.authority.snapshot(),fresh)
            XCTAssertTrue(capture.isSourceActive(.microphone))
            capture.beginStop();await capture.waitForQuiescence();capture.finishStop(quiesced:true)
        }
        await helper.shutdownAndWait();finished.finish()
    }
}
