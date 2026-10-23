import CoreGraphics
import Foundation
import Testing
import RelayNativeSession
import RelayScreenContext
import RelayControls
@testable import RelayContextComposition

private actor VisualOCR:ScreenTextRecognizer {
    func recognize(_ image:CGImage) async throws ->[OCRLine]{[OCRLine(text:"Find the highlighted path",bounds:CGRect(x:0,y:0,width:1,height:1),confidence:1)]}
}
@MainActor private final class VisualPixels:ScreenFrameProvider {
    var seed:UInt64=17
    func capture(source:ScreenSource)async throws ->ScreenFrame {
        var value=seed
        var bytes=[UInt8](repeating:0,count:256*256*4)
        for index in bytes.indices {
            value ^= value<<13;value ^= value>>7;value ^= value<<17
            bytes[index]=index%4==3 ? 255:UInt8(truncatingIfNeeded:value)
        }
        let provider=CGDataProvider(data:Data(bytes) as CFData)!
        let image=CGImage(width:256,height:256,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:1024,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        return ScreenFrame(image:image,capturedUptimeNanoseconds:DispatchTime.now().uptimeNanoseconds)
    }
}
@MainActor private final class UnusedSelection:SelectedTextProviding {
    func isTrusted(prompt:Bool)->Bool{false}
    func selectedText(from application:ApplicationIdentity)async throws ->SelectedTextObservation{throw SelectionError.stale}
}
@MainActor private final class ImageWriteHold {
    var held:CheckedContinuation<Void,Never>?
    var kinds:[String]=[]
    let heldKind:String
    private var heldOnce=false
    init(_ heldKind:String){self.heldKind=heldKind}
    func write(_ data:Data)async throws {
        let object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        let kind=object["kind"] as! String;kinds.append(kind)
        if kind==heldKind,!heldOnce{heldOnce=true;await withCheckedContinuation{held=$0}}
    }
    func release(){held?.resume();held=nil}
}
@Suite @MainActor struct VisualContextComposerTests {
    private func waitForHold(_ hold:ImageWriteHold)async throws {
        for _ in 0..<100 where hold.held==nil{try await Task.sleep(for:.milliseconds(2))}
        try #require(hold.held != nil)
    }
    private func prepared()async throws ->(QuestionContextComposer,PanelRequestBinding,VisualPixels,String,ScreenContextCoordinator) {
        let authority=SessionPresentationAuthority();let binding=PanelRequestBinding(lease:try authority.start(),requestID:UUID(),eventSequence:8)
        let pixels=VisualPixels();let screen=ScreenContextCoordinator(provider:pixels,recognizer:VisualOCR())
        screen.enable();screen.select(ScreenSource(windowID:1,bundleID:"com.example.synthetic",processID:42,label:"Synthetic diagram"))
        let selection=SelectedTextService(provider:UnusedSelection(),frontmostApplication:{nil},currentRequest:{nil})
        let composer=QuestionContextComposer(authority:authority,screen:screen,selection:selection)
        let frames=await composer.capture(for:binding,readSelectedText:false)
        #expect(frames.count==1)
        let frame=try JSONSerialization.jsonObject(with:frames[0]) as! [String:Any]
        return(composer,binding,pixels,frame["imageDigest"] as! String,screen)
    }
    @Test func realPNGIsPulledOneFrameAtATimeBeyondSenderQueueLimit()async throws {
        let (composer,binding,_,digest,_)=try await prepared()
        var outstanding=0,maximum=0,frames=0
        let offered=await composer.offerImage(for:binding){_ in
            outstanding+=1;maximum=max(maximum,outstanding);frames+=1
            await Task.yield();outstanding-=1
        }
        #expect(offered);#expect(frames>32);#expect(maximum==1)
        let use=composer.contextUse!
        #expect(composer.ownsContext(TaskContextUse(provenance:use.provenance,source:use.source,capturedUptimeNanoseconds:use.capturedUptimeNanoseconds,imageDigest:digest),for:binding))
    }
    @Test func completeOfferRequiresActualEndWriteAndRetirementPreservesOCRFallback()async throws {
        let (composer,binding,_,digest,_)=try await prepared();let hold=ImageWriteHold("screen_image_end")
        let use=composer.contextUse!
        let imageUse=TaskContextUse(provenance:use.provenance,source:use.source,capturedUptimeNanoseconds:use.capturedUptimeNanoseconds,imageDigest:digest)
        let offering=Task{@MainActor in await composer.offerImage(for:binding,write:hold.write)}
        try await waitForHold(hold)
        #expect(!composer.ownsContext(imageUse,for:binding))
        hold.release();#expect(await offering.value)
        #expect(composer.ownsContext(imageUse,for:binding))
        composer.retireImageOffer()
        #expect(!composer.ownsContext(imageUse,for:binding));#expect(composer.ownsContext(use,for:binding))
    }
    @Test func cancelledChunkNeverCompletesOfferOrSendsLaterChunks()async throws {
        let (composer,binding,_,_,_)=try await prepared();let hold=ImageWriteHold("screen_image_chunk")
        let offering=Task{@MainActor in await composer.offerImage(for:binding,write:hold.write)}
        try await waitForHold(hold)
        composer.retireImageOffer();hold.release()
        #expect(!(await offering.value));#expect(hold.kinds==["screen_image_begin","screen_image_chunk"])
        #expect(composer.ownsContext(composer.contextUse!,for:binding))
    }
    @Test func pickerSourceChangeRetiresTheOriginalImageBeforeLaterChunks()async throws {
        let (composer,binding,_,_,screen)=try await prepared();let hold=ImageWriteHold("screen_image_chunk")
        let offering=Task{@MainActor in await composer.offerImage(for:binding,write:hold.write)}
        try await waitForHold(hold)
        screen.select(ScreenSource(windowID:2,bundleID:"com.example.synthetic",processID:42,label:"Replacement source"))
        hold.release()
        #expect(!(await offering.value));#expect(hold.kinds==["screen_image_begin","screen_image_chunk"])
        #expect(!composer.ownsCurrent(binding))
    }
    @Test func unchangedOCRCannotProveUnchangedImagePixels()async throws {
        let (composer,binding,pixels,_,_)=try await prepared()
        #expect(await composer.offerImage(for:binding){_ in})
        pixels.seed=91
        #expect(await composer.validateForPublication(binding))
        #expect(!(await composer.validateForPublication(binding,requiringImageIdentity:true)))
        #expect(!composer.ownsCurrent(binding))
    }
}
