import CoreGraphics
import Foundation
import XCTest
import RelayContextComposition
import RelayScreenContext
import RelaySessionPanel
import RelayProfile
@testable import RelayPanelSession

@MainActor private final class IdleVisualPreferences:SessionContextUsePreferences {var useInSessions=false}

@MainActor private final class IdlePixels:ScreenFrameProvider {
    func capture(source:ScreenSource)async throws->ScreenFrame {
        let context=CGContext(data:nil,width:2,height:2,bitsPerComponent:8,bytesPerRow:8,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ScreenFrame(image:context.makeImage()!,capturedUptimeNanoseconds:DispatchTime.now().uptimeNanoseconds)
    }
}
private actor IdleOCR:ScreenTextRecognizer {
    func recognize(_ image:CGImage)async throws->[OCRLine]{[OCRLine(text:"Synthetic task: group completed records",bounds:CGRect(x:0,y:0,width:1,height:1),confidence:1)]}
}
@MainActor private final class IdleImageAcknowledgment {
    var held:CheckedContinuation<Void,Never>?
    var original:PanelRequestBinding?
    func wrote(_ data:Data,_ binding:PanelRequestBinding)async {
        guard original==nil,let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any],value["kind"] as? String=="screen_image_end" else{return}
        original=binding;await withCheckedContinuation{held=$0}
    }
    func release(){let pending=held;held=nil;pending?.resume()}
}
@MainActor final class IdleVisualApplicationTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func waitUntil(_ predicate:()->Bool)async throws {
        for _ in 0..<2000{if predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NSError(domain:"Idle image boundary not reached",code:1)
    }
    private func questions(_ log:URL)->[String]{
        ((try? String(contentsOf:log,encoding:.utf8)) ?? "").split(separator:"\n").compactMap{
            guard let kind=(try? JSONSerialization.jsonObject(with:Data($0.utf8)) as? [String:Any])?["kind"] as? String,kind.hasSuffix("_question") else{return nil};return kind
        }
    }
    private func rig(ack:IdleImageAcknowledgment?=nil)throws->(SessionApplicationModel,URL) {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-idle-image-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let log=directory.appendingPathComponent("events.jsonl"),launcher=directory.appendingPathComponent("helper")
        func quote(_ value:String)->String{"'"+value.replacingOccurrences(of:"'",with:"'\\''")+"'"}
        let python=try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])
        let script="#!/bin/sh\nexec \(quote(python)) \(quote(root.appendingPathComponent("tests/support/visual_backend_helper.py").path)) --synthetic-visual-test --log \(quote(log.path)) \"$@\"\n"
        try Data(script.utf8).write(to:launcher);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:launcher.path)
        let screen=ScreenContextCoordinator(provider:IdlePixels(),recognizer:IdleOCR())
        screen.enable();screen.select(ScreenSource(windowID:1,bundleID:"com.example.synthetic",processID:42,label:"Synthetic task"))
        let hook:(@MainActor (Data,PanelRequestBinding)async->Void)?
        if let ack{hook={data,binding in await ack.wrote(data,binding)}}else{hook=nil}
        let model=SessionApplicationModel(arguments:["Relay","--repository",root.path,"--python",launcher.path,"--role","analytics"],contextCoordinator:screen,
            contextWriteAcknowledged:hook,contextPreferences:IdleVisualPreferences())
        addTeardownBlock{await ack?.release();await model.stop();try? FileManager.default.removeItem(at:directory)}
        return(model,log)
    }
    func testFreshIdleImageUsesOriginalTypedObservationWithNoAudio()async throws {
        let (model,log)=try rig()
        let helper=try model.ensureHelper()
        model.visual.beginVerification(using:{action,update in try await helper.requestVisualInput(action,onUpdate:update)})
        await model.visual.waitForQuiescence();XCTAssertTrue(model.visual.mayOfferImages)
        model.assistant.draft="Explain event loops.";model.assistant.submitDraft()
        try await waitUntil{model.snapshot.card != nil}
        XCTAssertEqual(questions(log),["image_question"])
        XCTAssertTrue(model.contextStatus.contains("image and local OCR"))
        XCTAssertFalse(model.running);XCTAssertTrue(model.assistantActive)
        XCTAssertTrue(model.assistant.transcript.snapshot.rows.isEmpty);XCTAssertFalse(model.authorizedConversation)
        XCTAssertEqual(model.speechSetup.snapshot.stage,.notPrepared)
    }
    func testEndDeniesHeldIdleImageAndLateOriginalCallbackCannotClearReplacement()async throws {
        let acknowledgment=IdleImageAcknowledgment(),(model,log)=try rig(ack:acknowledgment)
        let helper=try model.ensureHelper()
        model.visual.beginVerification(using:{action,update in try await helper.requestVisualInput(action,onUpdate:update)})
        await model.visual.waitForQuiescence()
        model.assistant.draft="Explain event loops.";model.assistant.submitDraft()
        try await waitUntil{acknowledgment.held != nil}
        let original=try XCTUnwrap(acknowledgment.original)
        await model.stop()
        XCTAssertTrue(questions(log).isEmpty);XCTAssertNil(model.snapshot.card)
        XCTAssertFalse(model.visual.mayOfferImages);XCTAssertFalse(model.running)
        try FileManager.default.removeItem(at:log)
        model.assistant.draft="What is the difference between WHERE and HAVING?";model.assistant.submitDraft()
        try await waitUntil{model.snapshot.card != nil}
        XCTAssertNotEqual(model.currentSessionID,original.lease.captureSessionID)
        let replacement=model.snapshot.replacement,question=model.snapshot.question
        acknowledgment.release()
        for _ in 0..<20{await Task.yield()}
        XCTAssertTrue(model.assistantActive);XCTAssertEqual(model.snapshot.question,question)
        XCTAssertEqual(model.snapshot.replacement,replacement);XCTAssertNotNil(model.snapshot.card)
        XCTAssertFalse(questions(log).contains("image_question"));XCTAssertNil(model.error)
    }
}
