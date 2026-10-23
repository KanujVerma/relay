import Foundation
import XCTest
import Darwin
@testable import RelaySessionPanel

@MainActor final class ImageWriteBackpressureTests:XCTestCase {
    private var root:URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private func makeBlockedHelper(_ gate:URL,record:URL?=nil)->HelperTransport {
        let script="""
        import json,os,struct,sys,time
        while not os.path.exists(sys.argv[1]):time.sleep(.001)
        while True:
            header=sys.stdin.buffer.read(4)
            if not header:break
            size=struct.unpack('>I',header)[0]
            data=sys.stdin.buffer.read(size)
            if len(data)!=size:break
            value=json.loads(data)
            if sys.argv[2]:
                with open(sys.argv[2],'a') as log:log.write(json.dumps(list(value))+'\\n')
        """
        return HelperTransport(root:root,python:URL(fileURLWithPath:"/usr/bin/env"),pythonArguments:["python3","-u","-c",script,gate.path,record?.path ?? ""],mode:.fixture,onFrame:{_ in},onFailure:{})
    }
    @discardableResult private func fillQueue(_ helper:HelperTransport)throws ->Int {
        // Fill the frame limit before the byte limit, so even a small next
        // frame has to wait rather than fitting the residual byte capacity.
        let data=try JSONSerialization.data(withJSONObject:["synthetic_padding":String(repeating:"x",count:7000)])
        var admitted=0
        for _ in 0..<64 {
            do{try helper.sendJSON(data);admitted+=1}
            catch PanelBridgeError.overflow{break}
        }
        XCTAssertLessThan(admitted,64);return admitted
    }
    func testImageFrameWaitsForBoundedQueueAndActualFullWrite()async throws {
        let gate=FileManager.default.temporaryDirectory.appendingPathComponent("relay-writer-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:gate)}
        let helper=makeBlockedHelper(gate);try helper.start();XCTAssertGreaterThan(try fillQueue(helper),0)
        try await Task.sleep(for:.milliseconds(20));try fillQueue(helper)
        var completed=false
        let writing=Task{@MainActor in
            try await helper.sendJSONAwaitingWrite(Data("{\"synthetic_image_chunk\":1}".utf8),deadline:DispatchTime.now().uptimeNanoseconds+1_000_000_000,isCurrent:{true})
            completed=true
        }
        try await Task.sleep(for:.milliseconds(30));XCTAssertFalse(completed)
        try Data().write(to:gate)
        try await writing.value;XCTAssertTrue(completed)
        await helper.shutdownAndWait()
    }
    func testSourceRetirementWhileWaitingForCapacityDoesNotEnqueueAnImage()async throws {
        let gate=FileManager.default.temporaryDirectory.appendingPathComponent("relay-writer-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:gate)}
        let helper=makeBlockedHelper(gate);try helper.start();XCTAssertGreaterThan(try fillQueue(helper),0)
        try await Task.sleep(for:.milliseconds(20));try fillQueue(helper)
        var current=true
        let writing=Task{@MainActor in
            try await helper.sendJSONAwaitingWrite(Data("{\"synthetic_image_chunk\":1}".utf8),deadline:DispatchTime.now().uptimeNanoseconds+1_000_000_000,isCurrent:{current})
        }
        try await Task.sleep(for:.milliseconds(20));current=false
        do{try await writing.value;XCTFail("retired image was admitted")}catch{}
        try Data().write(to:gate)
        // The channel remains framed and usable; retirement did not truncate
        // an existing frame or close unrelated native control admission.
        try await helper.sendJSONAwaitingWrite(Data("{\"synthetic_control\":1}".utf8),deadline:DispatchTime.now().uptimeNanoseconds+1_000_000_000,isCurrent:{true})
        await helper.shutdownAndWait()
    }
    func testAdmittedImageRetiresBeforeItsFirstByteOnCancellationOrSourceChange()async throws {
        for mode in ["cancel","source"]{try await checkAdmittedRetirement(mode)}
    }
    func testAdmittedImageDeadlineRetiresBeforeItsFirstByte()async throws {
        try await checkAdmittedRetirement("deadline")
    }
    func testFirstBytePipeFailureRetiresAndReapsTheSharedChild()async throws {
        let script="""
        import json,os,struct,sys,time
        size=struct.unpack('>I',sys.stdin.buffer.read(4))[0]
        req=json.loads(sys.stdin.buffer.read(size))
        os.close(0)
        reply=dict(schemaVersion=1,kind='profile_response',requestID=req['requestID'],payload=dict(pid=os.getpid()))
        data=json.dumps(reply).encode()
        sys.stdout.buffer.write(struct.pack('>I',len(data))+data);sys.stdout.buffer.flush()
        while True:time.sleep(.01)
        """
        let failure=expectation(description:"first-byte EPIPE fails shared transport")
        let helper=HelperTransport(root:root,python:URL(fileURLWithPath:"/usr/bin/env"),pythonArguments:["python3","-u","-c",script],mode:.fixture,onFrame:{_ in},onFailure:{failure.fulfill()})
        try helper.start()
        let response=try await helper.requestProfile(Data("{\"command\":\"state\"}".utf8))
        let payload=try JSONSerialization.jsonObject(with:response) as! [String:Any]
        let pid=(payload["pid"] as! NSNumber).int32Value
        do{try await helper.sendJSONAwaitingWrite(Data("{\"synthetic_image_chunk\":1}".utf8),deadline:DispatchTime.now().uptimeNanoseconds+1_000_000_000,isCurrent:{true});XCTFail("closed input accepted an image")}catch{}
        await fulfillment(of:[failure],timeout:0.5)
        for _ in 0..<300{if kill(pid,0)<0,errno==ESRCH{break};try await Task.sleep(for:.milliseconds(10))}
        XCTAssertLessThan(kill(pid,0),0,"I/O failure must stop its retained child without another shutdown call")
        XCTAssertEqual(errno,ESRCH)
        await helper.shutdownAndWait()
    }
    private func checkAdmittedRetirement(_ mode:String)async throws {
        let gate=FileManager.default.temporaryDirectory.appendingPathComponent("relay-queued-"+UUID().uuidString)
        let record=gate.appendingPathExtension("observed")
        defer{try? FileManager.default.removeItem(at:gate);try? FileManager.default.removeItem(at:record)}
        let helper=makeBlockedHelper(gate,record:record);try helper.start()
        let padding=try JSONSerialization.data(withJSONObject:["padding":String(repeating:"x",count:14000)])
        // The image fits both admission bounds, but ten preceding frames are
        // blocked on the unopened reader, so none of its bytes can have begun.
        for _ in 0..<10{try helper.sendJSON(padding)}
        var current=true,finished=false
        let writing=Task{@MainActor in
            defer{finished=true}
            do {
                try await helper.sendJSONAwaitingWrite(Data("{\"synthetic_image_chunk\":1}".utf8),deadline:DispatchTime.now().uptimeNanoseconds+(mode=="deadline" ? 100_000_000:1_000_000_000),isCurrent:{current})
                XCTFail("retired queued image completed")
            }catch{}
        }
        try await Task.sleep(for:.milliseconds(50))
        if mode=="cancel"{writing.cancel()}else if mode=="source"{current=false}
        try await Task.sleep(for:.milliseconds(150))
        XCTAssertTrue(finished,"queued retirement must resolve before reader opens")
        try Data().write(to:gate)
        await writing.value
        try await helper.sendJSONAwaitingWrite(Data("{\"synthetic_control\":1}".utf8),deadline:DispatchTime.now().uptimeNanoseconds+1_000_000_000,isCurrent:{true})
        for _ in 0..<100 {
            if (try? String(contentsOf:record,encoding:.utf8).contains("synthetic_control"))==true{break}
            try await Task.sleep(for:.milliseconds(2))
        }
        let observed=try String(contentsOf:record,encoding:.utf8)
        XCTAssertTrue(observed.contains("synthetic_control"));XCTAssertFalse(observed.contains("synthetic_image_chunk"))
        await helper.shutdownAndWait()
    }
}
