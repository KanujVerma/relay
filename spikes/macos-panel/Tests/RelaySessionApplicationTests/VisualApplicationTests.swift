import Foundation
import XCTest
import RelaySessionPanel
@testable import RelayPanelSession

@MainActor final class VisualApplicationTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func waitUntil(_ predicate:()->Bool)async throws {
        for _ in 0..<1000{if predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        XCTFail("synthetic visual app did not finish")
    }
    func testDisabledAIAndFixtureDoNotStartVisualControlWork()async {
        for args in [["relay"],["relay","--fixture-suite","coding"]] {
            let model=SessionApplicationModel(arguments:args+["--repository",root.path])
            model.beginVisualVerification()
            XCTAssertFalse(model.visual.isBusy);XCTAssertFalse(model.visual.mayOfferImages)
            XCTAssertFalse(model.canTestVisualInput)
            await model.stop()
        }
    }
    func testPauseRetiresTheLocalVisualReflectionToMatchHelperStopSemantics()async throws {
        let model=SessionApplicationModel(arguments:["relay","--repository",root.path])
        // Inject only the control response, with no helper/account/capture IO.
        model.visual.beginVerification(using:{_,_ in
            try VisualInputResponse(data:JSONSerialization.data(withJSONObject:["schemaVersion":1,"kind":"visual_input_response","requestID":UUID().uuidString.lowercased(),"action":"verify","resultRevision":2,"status":"verified","reasonCode":"probe_verified","model":"synthetic-model"]))
        })
        await model.visual.waitForQuiescence();XCTAssertTrue(model.visual.mayOfferImages)
        model.beginRetirement(end:false)
        XCTAssertFalse(model.visual.mayOfferImages)
        try await waitUntil{!model.stopping}
        XCTAssertTrue(model.paused);XCTAssertTrue(model.canResume)
        await model.stop()
    }
    func testActualAppProbeBlocksStartAndModeChangesUntilEndJoinsOriginalTerminal()async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-visual-app-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:directory)}
        let gate=directory.appendingPathComponent("complete"),seen=directory.appendingPathComponent("seen")
        let launcher=directory.appendingPathComponent("helper")
        let script="""
        #!/usr/bin/env python3
        import json,os,struct,sys,threading,time
        lock=threading.Lock()
        def send(req,status,reason,revision=2):
            reply=dict(schemaVersion=1,kind='visual_input_response',requestID=req['requestID'],action=req['action'],resultRevision=revision,status=status,reasonCode=reason,model='synthetic-model')
            data=json.dumps(reply).encode()
            with lock:sys.stdout.buffer.write(struct.pack('>I',len(data))+data);sys.stdout.buffer.flush()
        def finish(req):
            while not os.path.exists('\(gate.path)'):time.sleep(.002)
            send(req,'cancelled','probe_cancelled')
        while True:
            header=sys.stdin.buffer.read(4)
            if not header:break
            req=json.loads(sys.stdin.buffer.read(struct.unpack('>I',header)[0]))
            if req.get('kind')!='visual_input_request':continue
            with open('\(seen.path)','a') as log:log.write(req['action']+'\\n')
            if req['action']=='verify':
                send(req,'checking','checking',1)
                threading.Thread(target=finish,args=(req,),daemon=True).start()
            elif req['action']=='disable':send(req,'disabled','user_disabled')
        """
        try Data(script.utf8).write(to:launcher);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:launcher.path)
        let model=SessionApplicationModel(arguments:["relay","--oauth","--repository",root.path,"--python",launcher.path])
        XCTAssertTrue(model.canTestVisualInput)
        model.beginVisualVerification()
        XCTAssertTrue(model.visual.isBusy);XCTAssertFalse(model.canStartSession);XCTAssertFalse(model.canChangeAIMode)
        try await waitUntil{FileManager.default.fileExists(atPath:seen.path)}
        await model.start();XCTAssertFalse(model.running);XCTAssertFalse(model.starting)
        await model.setAIEnabled(false);XCTAssertTrue(model.oauth)
        model.beginRetirement(end:true)
        XCTAssertTrue(model.stopping);XCTAssertFalse(model.visual.mayOfferImages)
        try await waitUntil{(try? String(contentsOf:seen,encoding:.utf8).contains("disable"))==true}
        for _ in 0..<5{await Task.yield()}
        XCTAssertTrue(model.visual.isBusy);XCTAssertTrue(model.stopping)
        try Data().write(to:gate)
        await model.stop()
        XCTAssertFalse(model.visual.isBusy);XCTAssertFalse(model.visual.mayOfferImages)
        XCTAssertFalse(model.stopping);XCTAssertTrue(model.canStartSession)
    }
}
