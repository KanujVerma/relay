import Foundation
import XCTest
@testable import RelaySessionPanel

private final class VisualReplyProbe:@unchecked Sendable {
    private let lock=NSLock();private var values:[VisualInputResponse]=[];private var failed=false
    func append(_ reply:VisualInputResponse){lock.withLock{values.append(reply)}}
    func fail(){lock.withLock{failed=true}}
    var replies:[VisualInputResponse]{lock.withLock{values}}
    var didFail:Bool{lock.withLock{failed}}
}
@MainActor final class VisualInputTransportTests:XCTestCase {
    private var root:URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private func helper(_ mode:String,probe:VisualReplyProbe)->HelperTransport {
        let script="""
        import json,struct,sys,uuid
        def read():
            header=sys.stdin.buffer.read(4)
            return None if not header else json.loads(sys.stdin.buffer.read(struct.unpack('>I',header)[0]))
        def emit(request,revision,status,reason,action=None):
            reply={'schemaVersion':1,'kind':'visual_input_response','requestID':request['requestID'],'action':action or request['action'],'resultRevision':revision,'status':status,'reasonCode':reason,'model':'gpt-fixture'}
            if sys.argv[1]=='wrong_uuid':reply['requestID']=str(uuid.uuid4())
            body=json.dumps(reply,separators=(',',':')).encode()
            sys.stdout.buffer.write(struct.pack('>I',len(body))+body);sys.stdout.buffer.flush()
        request=read();mode=sys.argv[1]
        if mode=='closed':raise SystemExit(0)
        if mode=='wrong_action':emit(request,2,'verified','current_status','status')
        else:
            emit(request,1,'checking','checking')
            if mode=='cancel':
                disabled=read();emit(disabled,2,'disabled','user_disabled');emit(request,2,'cancelled','probe_cancelled')
            elif mode=='progress_eof':raise SystemExit(0)
            else:
                emit(request,1,'checking','checking')
                emit(request,2,'verified','probe_verified')
                emit(request,2,'verified','probe_verified')
        sys.stdin.buffer.read()
        """
        return HelperTransport(root:root,python:URL(fileURLWithPath:"/usr/bin/env"),pythonArguments:["python3","-u","-c",script,mode],mode:.fixture,onFrame:{_ in XCTFail("visual reply escaped answer route")},onFailure:{probe.fail()})
    }
    func testCheckingAndTerminalReplayAreDeliveredOnlyOnce()async throws {
        let probe=VisualReplyProbe();let helper=helper("valid",probe:probe);try helper.start()
        let result=try await helper.requestVisualInput(.verify,onUpdate:probe.append)
        XCTAssertEqual(result.status,.verified);XCTAssertEqual(probe.replies.count,1)
        XCTAssertEqual(probe.replies.first?.status,.checking)
        try await Task.sleep(for:.milliseconds(20));XCTAssertFalse(probe.didFail)
        await helper.shutdownAndWait()
    }
    func testMismatchedOwnedActionUUIDAndEOFRejectTheirWaiter()async throws {
        for mode in ["wrong_action","wrong_uuid","closed","progress_eof"] {
            let probe=VisualReplyProbe();let helper=helper(mode,probe:probe);try helper.start()
            let finished=expectation(description:"visual request rejects \(mode)")
            var rejected=false
            Task{@MainActor in
                defer{finished.fulfill()}
                do{_=try await helper.requestVisualInput(.verify,onUpdate:probe.append);XCTFail("invalid reply succeeded")}
                catch{rejected=true}
            }
            await fulfillment(of:[finished],timeout:2)
            helper.stop();await helper.shutdownAndWait()
            XCTAssertTrue(rejected);XCTAssertTrue(probe.didFail)
        }
    }
    func testDisableRemainsResponsiveWhileVerifyWaitsForItsOwnTerminal()async throws {
        let probe=VisualReplyProbe();let helper=helper("cancel",probe:probe);try helper.start()
        let verifying=Task{try await helper.requestVisualInput(.verify,onUpdate:probe.append)}
        for _ in 0..<100 where probe.replies.isEmpty{try await Task.sleep(for:.milliseconds(2))}
        XCTAssertEqual(probe.replies.first?.status,.checking)
        let disabled=try await helper.requestVisualInput(.disable,onUpdate:probe.append)
        XCTAssertEqual(disabled.status,.disabled)
        let cancelled=try await verifying.value;XCTAssertEqual(cancelled.status,.cancelled)
        XCTAssertNotEqual(cancelled.requestID,disabled.requestID)
        await helper.shutdownAndWait()
    }
}

extension VisualInputTransportTests {
    @MainActor func testSynchronousControlOwnsReplyBeforeTheCallerStartsWaiting()async throws {
        for mode in ["valid","wrong_action","closed"] {
            let script="""
            import json,struct,sys
            size=struct.unpack('>I',sys.stdin.buffer.read(4))[0]
            req=json.loads(sys.stdin.buffer.read(size))
            if sys.argv[1]=='closed':sys.exit(0)
            action='status' if sys.argv[1]=='wrong_action' else req['action']
            reason='current_status' if action=='status' else 'user_disabled'
            data=json.dumps(dict(schemaVersion=1,kind='visual_input_response',requestID=req['requestID'],action=action,resultRevision=2,status='disabled',reasonCode=reason,model=None)).encode()
            sys.stdout.buffer.write(struct.pack('>I',len(data))+data);sys.stdout.buffer.flush()
            sys.stdin.buffer.read()
            """
            let helper=HelperTransport(root:root,python:URL(fileURLWithPath:"/usr/bin/env"),pythonArguments:["python3","-u","-c",script,mode],mode:.fixture,onFrame:{_ in},onFailure:{})
            try helper.start()
            let response=try helper.issueVisualInput(.disable,onUpdate:{_ in})
            try await Task.sleep(for:.milliseconds(30))
            do {
                let reply=try await response.value()
                XCTAssertEqual(mode,"valid");XCTAssertEqual(reply.action,.disable);XCTAssertEqual(reply.status,.disabled)
            }catch{XCTAssertNotEqual(mode,"valid")}
            await helper.shutdownAndWait()
        }
    }
}
