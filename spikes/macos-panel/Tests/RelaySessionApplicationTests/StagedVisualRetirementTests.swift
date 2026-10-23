import CoreGraphics
import Darwin
import Foundation
import XCTest
import RelayAudioBuffer
import RelayContextComposition
import RelayNativeSession
import RelayScreenContext
import RelaySessionPanel
@testable import RelayPanelSession

@MainActor private final class RetirementPixels:ScreenFrameProvider {
    func capture(source:ScreenSource)async throws->ScreenFrame {
        let context=CGContext(data:nil,width:2,height:2,bitsPerComponent:8,bytesPerRow:8,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ScreenFrame(image:context.makeImage()!,capturedUptimeNanoseconds:DispatchTime.now().uptimeNanoseconds)
    }
}
private actor RetirementOCR:ScreenTextRecognizer {
    func recognize(_ image:CGImage)async throws->[OCRLine]{[OCRLine(text:"Synthetic task: group completed records",bounds:CGRect(x:0,y:0,width:1,height:1),confidence:1)]}
}
@MainActor private final class EndAcknowledgment {
    var held:CheckedContinuation<Void,Never>?
    var binding:PanelRequestBinding?
    func wrote(_ data:Data,_ binding:PanelRequestBinding)async {
        guard let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any],value["kind"] as? String=="screen_image_end" else{return}
        self.binding=binding
        await withCheckedContinuation{held=$0}
    }
    func release(){let old=held;held=nil;old?.resume()}
}
@MainActor final class StagedVisualRetirementTests:XCTestCase {
    private enum Action:CaseIterable{case complete,onset,source,pause,end,disableThenOnset,closedTransport}
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func waitUntil(_ predicate:()->Bool)async throws {
        for _ in 0..<2000{if predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NSError(domain:"Synthetic visual callback timed out",code:1)
    }
    private func questionKinds(_ log:URL)->[String] {
        guard let contents=try? String(contentsOf:log,encoding:.utf8) else{return []}
        return contents.split(separator:"\n").compactMap{line in
            guard let value=try? JSONSerialization.jsonObject(with:Data(line.utf8)) as? [String:Any],let kind=value["kind"] as? String,kind.hasSuffix("_question") else{return nil};return kind
        }
    }
    func testCompleteOriginalImageIsActuallyUsedByTheInjectedBackend()async throws{try await exercise(.complete)}
    func testActualRemoteOnsetRetiresCompleteStagedImageBeforeOldEOU()async throws{try await exercise(.onset)}
    func testActualSourceCallbackRetiresCompleteStagedImageBeforeOldEOU()async throws{try await exercise(.source)}
    func testActualPauseRetiresCompleteStagedImageBeforeOldEOU()async throws{try await exercise(.pause)}
    func testActualEndRetiresCompleteStagedImageBeforeOldEOU()async throws{try await exercise(.end)}
    func testImageDisableFlushesOCRFallbackBeforeLaterActualOnset()async throws{try await exercise(.disableThenOnset)}
    func testFailedRetirementChannelNeverReleasesItsHeldEOU()async throws{try await exercise(.closedTransport)}
    private func exercise(_ action:Action)async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-staged-retirement-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:directory)}
        let log=directory.appendingPathComponent("post-types.jsonl"),launcher=directory.appendingPathComponent("synthetic-helper")
        let fixture=root.appendingPathComponent("tests/support/visual_backend_helper.py")
        let localInterpreter="/private/tmp/relay-answers-venv/bin/python"
        let interpreter=FileManager.default.isExecutableFile(atPath:localInterpreter) ? localInterpreter:"/usr/bin/env python3"
        let script="""
        #!\(interpreter)
        import runpy,sys
        sys.argv=['\(fixture.path)','--synthetic-visual-test','--log','\(log.path)']+sys.argv[1:]
        runpy.run_path('\(fixture.path)',run_name='__main__')
        """
        try Data(script.utf8).write(to:launcher);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:launcher.path)
        let screen=ScreenContextCoordinator(provider:RetirementPixels(),recognizer:RetirementOCR())
        screen.enable();screen.select(ScreenSource(windowID:1,bundleID:"com.example.synthetic",processID:42,label:"Synthetic task"))
        let acknowledgment=EndAcknowledgment();var nativeEvents:[NativeSessionEvent]=[]
        let model=SessionApplicationModel(arguments:["relay","--fixture-suite","reviewed","--repository",root.path,"--python",launcher.path],contextCoordinator:screen,contextWriteAcknowledged:acknowledgment.wrote,ingressEnqueued:{[self] ingress in
            guard case .audio(let event)=ingress else{return}
            nativeEvents.append(event)
            if event.kind == .eou {
                // A valid pipe schedule lets EOU complete before a later onset
                // becomes readable. This actor is held only after image-end's
                // actual write, so no MainActor first-byte admission is needed.
                let deadline=DispatchTime.now().uptimeNanoseconds+300_000_000
                while questionKinds(log).isEmpty,DispatchTime.now().uptimeNanoseconds<deadline{Thread.sleep(forTimeInterval:0.001)}
            }
        })
        do {
            let helper=try model.ensureHelper()
            model.visual.beginVerification(using:{action,update in try await helper.requestVisualInput(action,onUpdate:update)})
            await model.visual.waitForQuiescence();XCTAssertTrue(model.visual.mayOfferImages)
            await model.start();try await waitUntil{acknowledgment.held != nil}
            let original=try XCTUnwrap(acknowledgment.binding)
            func onset(){model.ingestFixturePacket(SessionAudioPacket(source:.remoteAudio,streamGeneration:1,sequence:3,hostTime:mach_absolute_time(),samples:Array(repeating:0.2,count:512)))}
            switch action {
            case .complete:acknowledgment.release()
            case .onset:onset()
            case .source:screen.select(ScreenSource(windowID:2,bundleID:"com.example.synthetic",processID:42,label:"Replacement task"));acknowledgment.release()
            case .pause:model.beginRetirement(end:false)
            case .end:model.beginRetirement(end:true)
            case .closedTransport:helper.stop();onset()
            case .disableThenOnset:
                model.disableVisualInput()
                let released=nativeEvents.contains{$0.kind == .eou}
                XCTAssertTrue(released,"Disable must enqueue its control and release the original EOU synchronously")
                if released {
                    try await waitUntil{model.snapshot.card != nil}
                    XCTAssertTrue(model.contextStatus.contains("Used Synthetic task · local OCR"))
                    XCTAssertFalse(model.contextStatus.contains("image and"))
                }
                onset()
            }
            if action == .closedTransport {
                try await waitUntil{model.stopping}
                XCTAssertFalse(nativeEvents.contains{$0.kind == .eou})
                XCTAssertTrue(questionKinds(log).isEmpty)
                acknowledgment.release();await model.stop();return
            }
            try await waitUntil{nativeEvents.contains{$0.kind == .eou}}
            acknowledgment.release()
            if [.onset,.disableThenOnset].contains(action){try await waitUntil{nativeEvents.filter{$0.kind == .speechStarted}.count==2}}
            if action == .complete{try await waitUntil{model.snapshot.card != nil}}
            if action == .disableThenOnset{try await waitUntil{questionKinds(log).contains("text_question")}}
            let posts=questionKinds(log)
            if action == .complete{XCTAssertEqual(posts,["image_question"]);XCTAssertTrue(model.contextStatus.contains("image and local OCR"))}
            else{XCTAssertFalse(posts.contains("image_question"),"locally retired image must not reach the model: \(action)")}
            if action == .disableThenOnset{XCTAssertEqual(posts,["text_question"])}
            let eou=try XCTUnwrap(nativeEvents.first{$0.kind == .eou})
            XCTAssertEqual(PanelRequestBinding(eou),original)
            XCTAssertEqual(nativeEvents.map(\.eventSequence),Array(1...UInt64(nativeEvents.count)))
            await model.stop()
        }catch{acknowledgment.release();await model.stop();throw error}
    }
}
