import Foundation
import XCTest
@testable import RelaySessionPanel

@MainActor final class ImageWriteBackpressureTests:XCTestCase {
    private var root:URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private func makeBlockedHelper(_ gate:URL)->HelperTransport {
        let script="""
        import json,os,struct,sys,time
        while not os.path.exists(sys.argv[1]):time.sleep(.001)
        while True:
            header=sys.stdin.buffer.read(4)
            if not header:break
            size=struct.unpack('>I',header)[0]
            data=sys.stdin.buffer.read(size)
            if len(data)!=size:break
            json.loads(data)
        """
        return HelperTransport(root:root,python:URL(fileURLWithPath:"/usr/bin/env"),pythonArguments:["python3","-u","-c",script,gate.path],mode:.fixture,onFrame:{_ in},onFailure:{})
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
}
