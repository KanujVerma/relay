import Foundation
import XCTest
import RelayNativeSession
import RelaySessionPanel
@testable import RelayPanelSession

private actor OwnerQuietVAD:SpeechActivityDetector {
    nonisolated let chunkSamples=512
    func accept(_ samples:[Float])async throws->[SpeechBoundary]{[]}
}
private actor OwnerQuietASR:ActivityRecognizer {
    func recognize(_ samples:[Float])async throws->String{""}
}

@MainActor final class ConversationOwnerTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    func testActualReusedChildEOFRetiresCurrentOwnerAndOldChildFailureCannotRetireReplacement()async throws {
        let box=ConversationOwnerBox(),firstID=UUID()
        box.activateHelper(firstID)
        let script="""
        import json,struct,sys
        while True:
            header=sys.stdin.buffer.read(4)
            if not header:break
            n=json.loads(sys.stdin.buffer.read(struct.unpack('>I',header)[0]))
            if n.get('kind')!='assistant_scope_request':break
            r={k:n[k] for k in ('schemaVersion','action','requestID','assistantSessionID','sessionEpoch','presentationGeneration','controlSequence')}
            r.update(kind='assistant_scope_response',status='ready' if n['action']=='open' else 'closed')
            if n['action']=='close':r['quiesced']=True
            data=json.dumps(r).encode();sys.stdout.buffer.write(struct.pack('>I',len(data))+data);sys.stdout.buffer.flush()
        """
        let python=URL(fileURLWithPath:try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"]))
        let helper=HelperTransport(root:root,python:python,pythonArguments:["-u","-c",script],mode:.noInference,onFrame:{_ in},onFailure:{_=box.failHelper(firstID)})
        try helper.start();addTeardownBlock{await helper.shutdownAndWait()}
        func open(_ owner:ConversationOwner)async throws{
            XCTAssertTrue(box.install(owner))
            let native=try XCTUnwrap(owner.assistantController)
            let request=try native.begin(enqueue:{request in owner.record(request.lease);_=try helper.registerAssistantScope(request)})
            try helper.sendJSON(request.encodedJSON());_=try await helper.registerAssistantScope(request).value();try native.completeOpen(request)
        }
        let first=ConversationOwner(helper:helper,helperIdentity:firstID,preparationIntent:UUID())
        try await open(first)
        let close=try XCTUnwrap(first.assistantController?.beginClose(enqueue:{request in _=try helper.registerAssistantScope(request)}))
        try helper.sendJSON(close.encodedJSON());_=try await helper.registerAssistantScope(close).value()
        try first.assistantController?.completeClose(close);box.remove(first)
        let current=ConversationOwner(helper:helper,helperIdentity:firstID,preparationIntent:UUID())
        try await open(current);XCTAssertNotNil(current.authority.snapshot())
        // EOF comes from the same child after it was genuinely reused. The IO
        // callback must retire current, rather than the owner present at launch.
        do{_=try await helper.requestVisualInput(.status,onUpdate:{_ in});XCTFail("Expected child EOF")}catch{}
        XCTAssertTrue(current.isRetired);XCTAssertNil(current.authority.snapshot())
        await helper.shutdownAndWait();box.remove(current)
        let replacementID=UUID();box.activateHelper(replacementID)
        let replacement=ConversationOwner(helper:helper,helperIdentity:replacementID,preparationIntent:UUID())
        XCTAssertTrue(box.install(replacement))
        let native=try XCTUnwrap(replacement.assistantController)
        let request=try native.begin(enqueue:{_ in});try native.completeOpen(request)
        XCTAssertFalse(box.failHelper(firstID));box.remove(first);box.remove(current)
        XCTAssertTrue(box.current === replacement);XCTAssertFalse(replacement.isRetired)
        XCTAssertEqual(replacement.authority.snapshot(),request.lease)
    }
    func testSameHelperFailureRetiresActualCaptureSourceWithoutAnAudioInference()async throws {
        let box=ConversationOwnerBox(),id=UUID(),authority=SessionPresentationAuthority()
        let native=NativeSessionController(authority:authority,onEvent:{_ in})
        let helper=HelperTransport(root:root,python:URL(fileURLWithPath:"/usr/bin/false"),mode:.noInference,onFrame:{_ in},onFailure:{})
        box.activateHelper(id)
        let owner=ConversationOwner(helper:helper,helperIdentity:id,authority:authority,source:native)
        XCTAssertTrue(box.install(owner))
        try native.start(selectedBundleID:nil,microphoneEnabled:true,
            components:[1:SourceComponents(vad:OwnerQuietVAD(),recognizer:OwnerQuietASR())])
        XCTAssertTrue(native.isSourceActive(.microphone));XCTAssertNotNil(authority.snapshot())
        XCTAssertTrue(box.failHelper(id))
        XCTAssertNil(authority.snapshot());XCTAssertFalse(native.isSourceActive(.microphone))
        await native.waitForQuiescence()
    }
}
