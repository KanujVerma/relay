import CoreGraphics
import Foundation
import Testing
import RelayNativeSession
import RelayScreenContext
import RelayControls
@testable import RelayContextComposition

@MainActor private final class ImageSource:ScreenFrameProvider {
    var calls=0
    func capture(source:ScreenSource) async throws -> ScreenFrame {
        calls+=1
        let context=CGContext(data:nil,width:2,height:2,bitsPerComponent:8,bytesPerRow:8,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ScreenFrame(image:context.makeImage()!,capturedUptimeNanoseconds:DispatchTime.now().uptimeNanoseconds)
    }
}
private actor TextSource:ScreenTextRecognizer {
    var text="require capacity 3"
    func recognize(_ image:CGImage) async throws -> [OCRLine] { [OCRLine(text:text,bounds:CGRect(x:0,y:0,width:1,height:1),confidence:1)] }
    func change(){text="capacity is now 7"}
}
@MainActor private final class SelectionSource:SelectedTextProviding {
    let app:ApplicationIdentity;var text="selected requirement";var calls=0
    init(_ app:ApplicationIdentity){self.app=app}
    func isTrusted(prompt:Bool)->Bool {true}
    func selectedText(from application:ApplicationIdentity) async throws -> SelectedTextObservation {
        calls+=1;return SelectedTextObservation(application:app,role:"AXTextArea",subrole:nil,text:text)
    }
}
@MainActor private final class BindingBox {var binding:PanelRequestBinding?}

@Suite @MainActor struct QuestionContextComposerTests {
    @Test func selectedTextHasPriorityOnlyForExplicitHelpAndReobservesBeforePublication() async throws {
        let authority=SessionPresentationAuthority();let binding=PanelRequestBinding(lease:try authority.start(),requestID:UUID(),eventSequence:4)
        let box=BindingBox();box.binding=binding
        let app=ApplicationIdentity(bundleID:"com.example.editor",processID:42,launchDate:Date(timeIntervalSince1970:1234567))
        let selectionSource=SelectionSource(app)
        let selection=SelectedTextService(provider:selectionSource,frontmostApplication:{app},currentRequest:{box.binding.map{SelectionRequestIdentity(sessionID:$0.lease.captureSessionID,sessionEpoch:$0.lease.sessionEpoch,presentationGeneration:$0.lease.presentationGeneration,requestID:$0.requestID)}})
        try selection.enable(allowedBundleIDs:[app.bundleID],requestPermission:false)
        let image=ImageSource();let screen=ScreenContextCoordinator(provider:image,recognizer:TextSource())
        screen.enable();screen.select(ScreenSource(windowID:1,bundleID:app.bundleID,processID:42,label:"Synthetic editor"))
        let composer=QuestionContextComposer(authority:authority,screen:screen,selection:selection)
        let frames=await composer.capture(for:binding,readSelectedText:true)
        #expect(frames.count==1);#expect(selectionSource.calls==1);#expect(image.calls==0)
        #expect(composer.contextUse?.provenance=="selected_accessibility_text")
        #expect(await composer.validateForPublication(binding))
        #expect(selectionSource.calls==2);#expect(composer.ownsCurrent(binding))
        selection.invalidate()
        #expect(!(await composer.validateForPublication(binding)))
        #expect(selectionSource.calls==2)
        selectionSource.text="changed selection"
        #expect(!(await composer.validateForPublication(binding)))
    }
    @Test func automaticQuestionUsesOCRAndChangedCodeFailsActualReobservation() async throws {
        let authority=SessionPresentationAuthority();let binding=PanelRequestBinding(lease:try authority.start(),requestID:UUID(),eventSequence:4)
        let app=ApplicationIdentity(bundleID:"com.example.editor",processID:42,launchDate:Date())
        let selectionSource=SelectionSource(app)
        let selection=SelectedTextService(provider:selectionSource,frontmostApplication:{app},currentRequest:{nil})
        let recognizer=TextSource();let screen=ScreenContextCoordinator(provider:ImageSource(),recognizer:recognizer)
        screen.enable();screen.select(ScreenSource(windowID:1,bundleID:app.bundleID,processID:42,label:"Synthetic editor"))
        let composer=QuestionContextComposer(authority:authority,screen:screen,selection:selection)
        #expect(await composer.capture(for:binding,readSelectedText:false).count==1)
        #expect(selectionSource.calls==0);#expect(composer.contextUse?.provenance=="local_ocr")
        await recognizer.change()
        #expect(!(await composer.validateForPublication(binding)))
        #expect(!composer.ownsCurrent(binding))
    }
}
