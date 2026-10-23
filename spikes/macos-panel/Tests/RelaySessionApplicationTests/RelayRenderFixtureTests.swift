import AppKit
import SwiftUI
import XCTest
@testable import RelayPanelSession

@MainActor final class RelayRenderFixtureTests:XCTestCase {
    func testRenderInertSyntheticSurfacesForReview()throws {
        guard let path=ProcessInfo.processInfo.environment["RELAY_RENDER_DIRECTORY"] else{throw XCTSkip("Optional inert offscreen render artifacts; set RELAY_RENDER_DIRECTORY.")}
        let directory=URL(fileURLWithPath:path,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let ready=RelaySessionPresentation(hasSelectedSource:true,hasRemoteSource:true,authorizedConversation:true,ownerCanStart:true)
        try render(home(ready,nil,nil),name:"home",size:CGSize(width:920,height:670),directory:directory)
        var microphoneOnly=ready;microphoneOnly.hasRemoteSource=false
        try render(home(microphoneOnly,nil,nil,microphoneOnly:true),name:"microphone-only",size:CGSize(width:920,height:670),directory:directory)
        var preparing=ready;preparing.preparing=true;preparing.starting=true
        try render(home(preparing,RelayPreparationPresentation(title:"Preparing local speech…",detail:"First setup · 225 MB total",fraction:0.45,busy:true),nil),name:"preparing",size:CGSize(width:920,height:670),directory:directory)
        try render(home(ready,RelayPreparationPresentation(title:"Speech setup needs attention",detail:"Connect once to prepare speech files. Your existing files are kept.",recovery:.retry),nil),name:"error",size:CGSize(width:920,height:670),directory:directory)
        let live=RelaySessionPresentation(running:true,hasQuestion:true,hasAnswer:true)
        let answer=RelayAnswerPresentation(lead:"Use a single pass and return early when the sequence is empty.",points:["Check the empty case before accessing an index.","Keep the input unchanged."],detail:"def first_or_none(items):\n    if not items:\n        return None\n    return items[0]",language:"python",isCode:true)
        try render(LiveSessionView(state:live,question:"How would you return the first item, or None for an empty list?",answer:answer,status:"Talking points",contextLabel:"Viewed screen text",contextDetail:"Synthetic editor · local OCR",elapsed:"02:41",fixture:true,expanded:.constant(true),detailExpanded:.constant(true),onAction:{_ in}),name:"live",size:CGSize(width:706,height:576),directory:directory)
        let paused=RelaySessionPresentation(paused:true,hasSelectedSource:true,authorizedConversation:true,ownerCanResume:true)
        try render(LiveSessionView(state:paused,status:"Paused",fixture:true,expanded:.constant(true),detailExpanded:.constant(false),onAction:{_ in}),name:"paused",size:CGSize(width:706,height:576),directory:directory)
        try render(LiveSessionView(state:live,status:"Talking points",elapsed:"02:41",fixture:true,expanded:.constant(false),detailExpanded:.constant(false),onAction:{_ in}),name:"pill",size:CGSize(width:706,height:66),directory:directory)
    }
    private func home(_ state:RelaySessionPresentation,_ preparation:RelayPreparationPresentation?,_ error:String?,microphoneOnly:Bool=false)->some View {
        RelayHomeView(state:state,preparation:preparation,aiEnabled:true,error:error,fixture:true,onAction:{_ in}){
            VStack(alignment:.leading,spacing:14){HStack{Label(microphoneOnly ? "Microphone only":"Synthetic conversation app",systemImage:microphoneOnly ? "mic":"app");Spacer();Image(systemName:"chevron.up.chevron.down")}.font(.system(size:13));Label("Microphone replies included",systemImage:"checkmark.square.fill").font(.system(size:12));Label("Recording and assistance permitted",systemImage:"checkmark.square.fill").font(.system(size:12)).foregroundStyle(RelayTheme.secondary)}
        }
    }
    private func render<V:View>(_ view:V,name:String,size:CGSize,directory:URL)throws {
        // ImageRenderer omits AppKit-backed ScrollView descendants on this
        // host. Render the same pure view in an unordered offscreen window.
        let hosting=NSHostingView(rootView:view.frame(width:size.width,height:size.height).background(RelayTheme.base))
        let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        window.contentView=hosting;hosting.frame=NSRect(origin:.zero,size:size)
        window.layoutIfNeeded();hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until:Date().addingTimeInterval(0.1))
        hosting.layoutSubtreeIfNeeded()
        let bitmap=try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds))
        hosting.cacheDisplay(in:hosting.bounds,to:bitmap)
        let data=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
        try data.write(to:directory.appendingPathComponent(name+".png"))
        window.contentView=nil;window.close()
    }
}
