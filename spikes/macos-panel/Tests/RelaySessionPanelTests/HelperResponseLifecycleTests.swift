import Foundation
import XCTest
@testable import RelaySessionPanel

@MainActor final class HelperResponseLifecycleTests:XCTestCase {
    private var root:URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    /// Real child, real owned pipes and production frame dispatch. No source,
    /// model, profile storage, credentials or external service is involved.
    private func helper(_ mode:String)->HelperTransport {
        let script="""
        import json,struct,sys,uuid
        size=struct.unpack('>I',sys.stdin.buffer.read(4))[0]
        request=json.loads(sys.stdin.buffer.read(size))
        mode=sys.argv[1]
        if mode=='closed':
            raise SystemExit(0)
        if request['kind']=='profile_request':
            payload={'ok':True}
            if mode=='profile_null':payload=None
            elif mode=='profile_scalar':payload='synthetic'
            elif mode=='profile_array':payload=['synthetic']
            reply={'schemaVersion':1,'kind':'profile_response','requestID':request['requestID'],'payload':payload}
        else:
            reply={**request,'kind':'session_quiescence_response','quiesced':True}
            if mode=='wrong_session':reply['captureSessionID']=str(uuid.uuid4())
            elif mode=='wrong_epoch':reply['sessionEpoch']+=1
        body=json.dumps(reply,separators=(',',':')).encode()
        sys.stdout.buffer.write(struct.pack('>I',len(body))+body)
        sys.stdout.buffer.flush()
        sys.stdin.buffer.read()
        """
        return HelperTransport(root:root,python:URL(fileURLWithPath:"/usr/bin/env"),pythonArguments:["python3","-u","-c",script,mode],mode:.fixture,onFrame:{_ in},onFailure:{})
    }
    private func assertQuiescenceFailsPromptly(_ mode:String) async throws {
        let helper=helper(mode);try helper.start()
        let finished=expectation(description:"quiescence waiter resolves on \(mode)")
        var rejected=false
        Task { @MainActor in
            defer { finished.fulfill() }
            do { try await helper.requestSessionQuiescence(sessionID:UUID(),epoch:1);XCTFail("invalid response succeeded") }
            catch { rejected=true }
        }
        await fulfillment(of:[finished],timeout:2)
        helper.stop();await helper.shutdownAndWait()
        XCTAssertTrue(rejected)
        XCTAssertThrowsError(try helper.sendJSON(Data("{}".utf8)))
    }
    func testMatchingQuiescenceResponseResolvesTheActualWaiter() async throws {
        let helper=helper("valid");try helper.start()
        try await helper.requestSessionQuiescence(sessionID:UUID(),epoch:1)
        await helper.shutdownAndWait()
    }
    func testWrongSessionQuiescenceResponseResolvesErrorInsteadOfLosingWaiter() async throws { try await assertQuiescenceFailsPromptly("wrong_session") }
    func testWrongEpochQuiescenceResponseResolvesErrorInsteadOfLosingWaiter() async throws { try await assertQuiescenceFailsPromptly("wrong_epoch") }
    func testClosedTransportResolvesQuiescenceWaiter() async throws { try await assertQuiescenceFailsPromptly("closed") }
    func testNonobjectProfilePayloadsResolveErrorWithoutOrphanOrCrash() async throws {
        for mode in ["profile_null","profile_scalar","profile_array"] {
            let helper=helper(mode);try helper.start()
            let finished=expectation(description:"profile waiter resolves on \(mode)")
            var rejected=false
            Task { @MainActor in
                defer { finished.fulfill() }
                do { _=try await helper.requestProfile(Data("{\"command\":\"state\"}".utf8));XCTFail("nonobject profile response succeeded") }
                catch { rejected=true }
            }
            await fulfillment(of:[finished],timeout:2)
            helper.stop();await helper.shutdownAndWait()
            XCTAssertTrue(rejected)
        }
    }
}
