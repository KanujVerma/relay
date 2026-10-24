import CoreGraphics
import Foundation
import XCTest
import RelayNativeSession
import RelayScreenContext
import RelayControls
import RelayContextComposition
@testable import RelaySessionPanel

private actor ForwardingOCR:ScreenTextRecognizer {
    func recognize(_ image:CGImage)async throws->[OCRLine]{[OCRLine(text:"Synthetic diagram task",bounds:CGRect(x:0,y:0,width:1,height:1),confidence:1)]}
}
@MainActor private final class ForwardingPixels:ScreenFrameProvider {
    func capture(source:ScreenSource)async throws->ScreenFrame {
        var value:UInt64=17,bytes=[UInt8](repeating:0,count:256*256*4)
        for index in bytes.indices{value ^= value<<13;value ^= value>>7;value ^= value<<17;bytes[index]=index%4==3 ? 255:UInt8(truncatingIfNeeded:value)}
        let provider=CGDataProvider(data:Data(bytes) as CFData)!
        let image=CGImage(width:256,height:256,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:1024,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        return ScreenFrame(image:image,capturedUptimeNanoseconds:DispatchTime.now().uptimeNanoseconds)
    }
}
@MainActor private final class ForwardingSelection:SelectedTextProviding {
    func isTrusted(prompt:Bool)->Bool{false}
    func selectedText(from application:ApplicationIdentity)async throws->SelectedTextObservation{throw SelectionError.stale}
}
@MainActor final class VisualForwardingIntegrationTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    func testCancelledRealPNGTransferKeepsOriginalEOUBeforeNextOnsetAndWholeFrames()async throws {
        try await checkTransfer(cancel:true)
    }
    func testCompleteRealPNGTransferOffersImageOnlyAfterWholeEndBeforeOriginalEOU()async throws {
        try await checkTransfer(cancel:false)
    }
    private func checkTransfer(cancel:Bool)async throws {
        let gate=FileManager.default.temporaryDirectory.appendingPathComponent("relay-image-order-"+UUID().uuidString),record=FileManager.default.temporaryDirectory.appendingPathComponent("relay-image-seen-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:gate);try? FileManager.default.removeItem(at:record)}
        let script="""
        import json,os,struct,sys,time
        while not os.path.exists(sys.argv[1]):time.sleep(.001)
        while True:
            header=sys.stdin.buffer.read(4)
            if not header:break
            size=struct.unpack('>I',header)[0]
            body=sys.stdin.buffer.read(size)
            if len(body)!=size:raise RuntimeError('truncated synthetic frame')
            value=json.loads(body)
            with open(sys.argv[2],'a') as log:log.write(json.dumps(dict(kind=value['kind'],requestID=value.get('requestID'),eventSequence=value.get('eventSequence')))+'\\n')
        """
        let helper=HelperTransport(root:root,python:URL(fileURLWithPath:"/usr/bin/env"),pythonArguments:["python3","-u","-c",script,gate.path,record.path],mode:.fixture,onFrame:{_ in},onFailure:{})
        try helper.start()
        let authority=SessionPresentationAuthority(),lease=try authority.start(),requestID=UUID()
        let eou=NativeSessionEvent(captureSessionID:lease.captureSessionID,sessionEpoch:lease.sessionEpoch,eventSequence:4,presentationGeneration:lease.presentationGeneration,kind:.eou,sourceCode:2,streamGeneration:1,emittedUptimeNanoseconds:4,payload:[:],requestID:requestID)
        let binding=PanelRequestBinding(eou)!
        let screen=ScreenContextCoordinator(provider:ForwardingPixels(),recognizer:ForwardingOCR())
        screen.enable();screen.select(ScreenSource(windowID:1,bundleID:"com.example.synthetic",processID:42,label:"Synthetic image"))
        let selection=SelectedTextService(provider:ForwardingSelection(),frontmostApplication:{nil},currentRequest:{nil})
        let composer=QuestionContextComposer(authority:authority,screen:screen,selection:selection)
        var completedWrites=0,enteredWrites=0,failed=false
        let deadline=DispatchTime.now().uptimeNanoseconds+1_500_000_000
        let forwarder=OrderedContextForwarder(shouldCapture:{$0.binding != nil},capture:{ingress in
            await composer.captureForForwarding(for:ingress.binding!,readSelectedText:false,imageWriter:{data in
                enteredWrites+=1
                try await helper.sendJSONAwaitingWrite(data,deadline:deadline,isCurrent:{composer.ownsCurrent(binding)})
                completedWrites+=1
            })
        },send:{ingress,frames in
            for frame in frames{try helper.sendJSON(frame)}
            if case .audio(let event)=ingress{try helper.send(event)}
        },onFailure:{failed=true})
        if !cancel{try Data().write(to:gate)}
        try forwarder.enqueue(eou)
        if cancel {
            for _ in 0..<200{if enteredWrites>completedWrites,completedWrites>=2{break};try await Task.sleep(for:.milliseconds(1))}
            XCTAssertGreaterThanOrEqual(completedWrites,2)
            // Cancellation either skips a not-yet-started chunk or finishes
            // its already-started frame before the queued original EOU.
            let next=try XCTUnwrap(authority.invalidate())
            let onset=NativeSessionEvent(captureSessionID:next.captureSessionID,sessionEpoch:next.sessionEpoch,eventSequence:5,presentationGeneration:next.presentationGeneration,kind:.speechStarted,sourceCode:2,streamGeneration:1,emittedUptimeNanoseconds:5,payload:[:])
            try forwarder.enqueue(onset);try Data().write(to:gate)
        }
        let last=cancel ? "speech_started":"eou"
        for _ in 0..<500{if (try? String(contentsOf:record,encoding:.utf8).contains("\"kind\": \""+last+"\""))==true{break};try await Task.sleep(for:.milliseconds(2))}
        let lines=try String(contentsOf:record,encoding:.utf8).split(separator:"\n")
        let values=try lines.map{try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
        let kinds=values.map{$0["kind"] as! String}
        XCTAssertFalse(failed);XCTAssertEqual(kinds.first,"screen_context")
        XCTAssertEqual(kinds.filter{$0=="screen_context"}.count,1)
        XCTAssertTrue(kinds.contains("screen_image_begin"))
        if cancel {
            XCTAssertFalse(kinds.contains("screen_image_end"));XCTAssertEqual(Array(kinds.suffix(2)),["eou","speech_started"])
        }else{
            XCTAssertGreaterThan(kinds.count,32);XCTAssertEqual(Array(kinds.suffix(2)),["screen_image_end","eou"])
            let use=try XCTUnwrap(composer.contextUse),digest=try XCTUnwrap(screen.snapshot?.imageDigest)
            XCTAssertTrue(composer.ownsContext(TaskContextUse(provenance:use.provenance,source:use.source,capturedUptimeNanoseconds:use.capturedUptimeNanoseconds,imageDigest:digest),for:binding))
            let valid=await composer.validateForPublication(binding,requiringImageIdentity:true);XCTAssertTrue(valid)
        }
        let original=try XCTUnwrap(values.first{$0["kind"] as? String=="eou"})
        XCTAssertEqual(original["requestID"] as? String,requestID.uuidString.lowercased())
        XCTAssertEqual(original["eventSequence"] as? Int,4)
        await helper.shutdownAndWait()
    }
}
