import CoreGraphics
import Darwin
import Foundation
import XCTest
import RelayAudioBuffer
import RelayContextComposition
import RelayNativeSession
import RelayScreenContext
import RelaySessionPanel
import RelayProfile
@testable import RelayPanelSession

@MainActor private final class PreferencePixels:ScreenFrameProvider {
    var holdNext=false,held:CheckedContinuation<Void,Never>?
    func release(){holdNext=false;let original=held;held=nil;original?.resume()}
    func capture(source:ScreenSource)async throws->ScreenFrame {
        if holdNext{await withCheckedContinuation{held=$0}}
        let context=CGContext(data:nil,width:2,height:2,bitsPerComponent:8,bytesPerRow:8,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ScreenFrame(image:context.makeImage()!,capturedUptimeNanoseconds:DispatchTime.now().uptimeNanoseconds)
    }
}
private actor PreferenceOCR:ScreenTextRecognizer {
    func recognize(_ image:CGImage)async throws->[OCRLine]{[OCRLine(text:"Synthetic task: group completed records",bounds:CGRect(x:0,y:0,width:1,height:1),confidence:1)]}
}
@MainActor private final class PreferenceEndAcknowledgment {
    var held:CheckedContinuation<Void,Never>?
    var binding:PanelRequestBinding?
    func wrote(_ data:Data,_ binding:PanelRequestBinding)async {
        guard let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any],value["kind"] as? String=="screen_image_end" else{return}
        guard self.binding==nil else{return}
        self.binding=binding
        await withCheckedContinuation{held=$0}
    }
    func release(){let old=held;held=nil;old?.resume()}
}
@MainActor final class ResponsePreferencesVisualTests:XCTestCase {
    private enum Action:CaseIterable{case complete,general,feature,delete,publicationChange,onset,source,pause,end,disable,closedChannel}
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func python()throws->String {
        let environment=ProcessInfo.processInfo.environment
        let paths:[String]
        if let explicit=environment["RELAY_TEST_PYTHON"],!explicit.isEmpty{paths=[explicit]}
        else{paths=(environment["PATH"] ?? "").split(separator:":").map{URL(fileURLWithPath:String($0)).appendingPathComponent("python3").path}}
        guard let selected=paths.first(where:{$0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath:$0)})
        else{throw NSError(domain:"RelayVisualTestEnvironment",code:1,userInfo:[NSLocalizedDescriptionKey:"Set RELAY_TEST_PYTHON or put Python 3 on PATH."])}
        return selected
    }
    private func shellQuote(_ value:String)->String{"'"+value.replacingOccurrences(of:"'",with:"'\\''")+"'"}
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
    func testOriginalGuideAndCanonicalImageAreActuallyUsed()async throws{try await exercise(.complete)}
    func testGeneralDuringHeldImageEndRetiresGuideBeforeOriginalEOU()async throws{try await exercise(.general)}
    func testReplacementGuideCannotAttachToHeldOriginalButFreshHelpCanUseIt()async throws{try await exercise(.feature)}
    func testDeleteOriginalGuideDuringHeldImageEndRetiresBeforeEOU()async throws{try await exercise(.delete)}
    func testFailedGuideRetirementChannelNeverReleasesHeldEOU()async throws{try await exercise(.closedChannel)}
    func testGuideChangeDuringActualFinalPixelReobservationCannotPublishAndPreservesFreshHelp()async throws{try await exercise(.publicationChange)}
    func testOnsetRetiresHeldGuideAndImageBeforeOriginalEOU()async throws{try await exercise(.onset)}
    func testSourceChangeRetiresHeldGuideAndImageBeforeOriginalEOU()async throws{try await exercise(.source)}
    func testPauseJoinsOriginalGuideAndImageWithoutPOST()async throws{try await exercise(.pause)}
    func testEndJoinsOriginalGuideAndImageWithoutPOST()async throws{try await exercise(.end)}
    func testImageDisablePreservesOriginalGuideForGenuineOCRFallback()async throws{try await exercise(.disable)}
    private func exercise(_ action:Action)async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-staged-retirement-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:directory)}
        let trace=directory.appendingPathComponent("trace.jsonl"),log=directory.appendingPathComponent("post-types.jsonl"),launcher=directory.appendingPathComponent("synthetic-helper")
        let fixture=root.appendingPathComponent("tests/support/response_preferences_visual_helper.py")
        let interpreter=try python()
        let script="""
        #!/bin/sh
        exec \(shellQuote(interpreter)) \(shellQuote(fixture.path)) --synthetic-preferences-test --trace \(shellQuote(trace.path)) --log \(shellQuote(log.path)) "$@"
        """
        try Data(script.utf8).write(to:launcher);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:launcher.path)
        let pixels=PreferencePixels(),screen=ScreenContextCoordinator(provider:pixels,recognizer:PreferenceOCR())
        screen.enable();screen.select(ScreenSource(windowID:1,bundleID:"com.example.synthetic",processID:42,label:"Synthetic task"))
        let acknowledgment=PreferenceEndAcknowledgment();var nativeEvents:[NativeSessionEvent]=[]
        let store=ApplicationPreferenceStorage(),receipts=ApplicationPreferenceReceipts()
        let model=SessionApplicationModel(arguments:["relay","--fixture-suite","reviewed","--repository",root.path,"--python",launcher.path],contextCoordinator:screen,contextWriteAcknowledged:acknowledgment.wrote,ingressEnqueued:{ ingress in
            guard case .audio(let event)=ingress else{return}
            nativeEvents.append(event)

        },responsePreferencesStorage:store,responsePreferencesReceipts:receipts)
        do {
            if action == .delete{try await model.responsePreferences.saveAndUse(ResponseGuide(name:"Synthetic guide",focus:.coding,guidance:"Prefer concise invariants."),expectedCatalogRevision:nil)}
            else{try await model.responsePreferences.useBuiltin(.coding)}
            let guide=try XCTUnwrap(model.responsePreferences.capture())
            let helper=try model.ensureHelper()
            model.visual.beginVerification(using:{action,update in try await helper.requestVisualInput(action,onUpdate:update)})
            await model.visual.waitForQuiescence();XCTAssertTrue(model.visual.mayOfferImages)
            await model.start();try await waitUntil{acknowledgment.held != nil}
            let original=try XCTUnwrap(acknowledgment.binding)
            func onset(){model.ingestFixturePacket(SessionAudioPacket(source:.remoteAudio,streamGeneration:1,sequence:3,hostTime:mach_absolute_time(),samples:Array(repeating:0.2,count:512)))}
            switch action {
            case .complete:acknowledgment.release()
            case .publicationChange:pixels.holdNext=true;acknowledgment.release()
            case .general:model.responsePreferences.useGeneral();acknowledgment.release()
            case .feature:try await model.responsePreferences.useBuiltin(.feature);acknowledgment.release()
            case .delete:
                let catalog=try XCTUnwrap(model.responsePreferences.catalog)
                try await model.responsePreferences.delete(id:try XCTUnwrap(catalog.guides.first).id,expectedCatalogRevision:catalog.revision);acknowledgment.release()
            case .closedChannel:helper.stop();model.responsePreferences.useGeneral()
            case .onset:onset()
            case .source:screen.select(ScreenSource(windowID:2,bundleID:"com.example.synthetic",processID:42,label:"Replacement task"));acknowledgment.release()
            case .pause:model.beginRetirement(end:false)
            case .end:model.beginRetirement(end:true)
            case .disable:model.disableVisualInput()
            }
            if action == .publicationChange{
                try await waitUntil{pixels.held != nil}
                XCTAssertEqual(questionKinds(log),["image_question"]);XCTAssertNil(model.snapshot.card)
                try await model.responsePreferences.useBuiltin(.feature)
                pixels.release()
                try await waitUntil{model.snapshot.status=="Response guide changed. Ask again."}
                XCTAssertNil(model.snapshot.card);XCTAssertNil(model.snapshot.responsePreferencesRevision)
                XCTAssertTrue(model.assistant.snapshot.canHelpCurrent)
                try model.perform(.requestHelp)
                try await waitUntil{model.snapshot.card != nil}
                XCTAssertEqual(model.snapshot.responsePreferencesRevision,model.responsePreferences.capture()?.revision)
                XCTAssertNotEqual(model.snapshot.responsePreferencesRevision,guide.revision)
                XCTAssertEqual(questionKinds(log),["image_question","image_question"])
                await model.stop();return
            }
            if action == .closedChannel{
                try await waitUntil{model.stopping}
                XCTAssertFalse(nativeEvents.contains{$0.kind == .eou});XCTAssertTrue(questionKinds(log).isEmpty)
                acknowledgment.release();await model.stop();XCTAssertTrue(helper.hasExited);return
            }
            try await waitUntil{nativeEvents.contains{$0.kind == .eou}}
            acknowledgment.release()
            if [.complete,.general,.feature,.delete,.disable].contains(action){try await waitUntil{model.snapshot.card != nil}}
            if [.pause,.end].contains(action){try await waitUntil{!model.stopping}}
            if action == .onset{try await waitUntil{nativeEvents.filter{$0.kind == .speechStarted}.count==2}}
            let posts=questionKinds(log)
            if [.complete,.general,.feature,.delete].contains(action){XCTAssertEqual(posts,["image_question"]);XCTAssertTrue(model.contextStatus.contains("image and local OCR"))}
            else if action == .disable{XCTAssertEqual(posts,["text_question"]);XCTAssertTrue(model.contextStatus.contains("local OCR"));XCTAssertFalse(model.contextStatus.contains("image and"))}
            else{XCTAssertTrue(posts.isEmpty)}
            if [.complete,.disable].contains(action){XCTAssertEqual(model.snapshot.responsePreferencesRevision,guide.revision)}
            else{XCTAssertNil(model.snapshot.responsePreferencesRevision)}
            if [.general,.feature,.delete].contains(action){
                let rows=try String(contentsOf:trace,encoding:.utf8).split(separator:"\n").map{try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
                let retired=try XCTUnwrap(rows.firstIndex{ $0["kind"] as? String == "response_preferences_retired" })
                let eou=try XCTUnwrap(rows.firstIndex{ $0["kind"] as? String == "eou" })
                XCTAssertLessThan(retired,eou);XCTAssertEqual(rows[retired]["preferencesRevision"] as? String,guide.revision.uuidString.lowercased())
                XCTAssertFalse(rows.contains{ $0["kind"] as? String == "response_preferences" },"The held original cannot acquire its replacement guide")
            }
            if action == .feature{
                try model.perform(.requestHelp);try await waitUntil{model.snapshot.responsePreferencesRevision==model.responsePreferences.capture()?.revision}
                XCTAssertNotEqual(model.snapshot.responsePreferencesRevision,guide.revision)
            }
            let eou=try XCTUnwrap(nativeEvents.first{$0.kind == .eou})
            XCTAssertEqual(PanelRequestBinding(eou),original)
            XCTAssertEqual(nativeEvents.map(\.eventSequence),Array(1...UInt64(nativeEvents.count)))
            await model.stop()
        }catch{pixels.release();acknowledgment.release();await model.stop();throw error}
    }
}
