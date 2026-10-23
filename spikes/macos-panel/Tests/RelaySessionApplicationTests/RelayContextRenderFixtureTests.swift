import AppKit
import SwiftUI
import XCTest
import RelayProfile
@testable import RelayPanelSession

private struct FictionalRenderKey:ProfileKeyProvider {
    func key(createIfMissing:Bool)throws->Data{Data(repeating:73,count:32)}
}

/// Visual fixture responses only. This is not an importer/approval/backend test.
private actor FictionalRenderProfilePort:ProfilePort {
    let pendingReview:Bool
    init(pendingReview:Bool){self.pendingReview=pendingReview}
    func request(_ data:Data)async throws->Data {
        let input=try JSONSerialization.jsonObject(with:data) as? [String:Any]
        let result:[String:Any]
        switch input?["command"] as? String {
        case "load_begin","transfer_chunk":result=["ok":true]
        case "load_commit":
            let claim="I added input validation to the fictional Northstar reporting tool."
            let card:[String:Any]=["fact_id":"pending_render","source_id":"source_render","snippet":claim,"source_sha256":String(repeating:"a",count:64),"span_start":0,"span_end":claim.utf8.count,"review_revision":1,"actor_hint":"unknown","card_fingerprint":String(repeating:"b",count:64)]
            result=["ok":true,"ready":true,"pending_count":pendingReview ? 1:0,"card":pendingReview ? card:NSNull(),"job":NSNull()]
        case "sources":
            result=["ok":true,"sources":[["source_id":"source_render","label":"Fictional Northstar project notes","purpose":"project"]]]
        case "memories":
            result=["ok":true,"memories":[
                ["fact_id":"fact_a","claim_key":"fictional.northstar.validation","claim_text":"I wrote validation tests for the fictional Northstar reporting tool.","actor":"self","source_id":"source_render","source_label":"Fictional Northstar project notes"],
                ["fact_id":"fact_b","claim_key":"fictional.northstar.team","claim_text":"Our fictional Northstar team chose a shared metric glossary.","actor":"team","source_id":"source_render","source_label":"Fictional Northstar project notes"]
            ],"total_count":2,"next_after":NSNull()]
        case "lock":result=["ok":true,"locked":true,"ready":false]
        default:throw ProfileError.rejected
        }
        return try JSONSerialization.data(withJSONObject:result)
    }
    func close()async{}
    func emergencyShutdown()async{}
}

@MainActor final class RelayContextRenderFixtureTests:XCTestCase {
    func testRenderFictionalContextStatesWithFakeKeyAndCommandPort()async throws {
        guard let path=ProcessInfo.processInfo.environment["RELAY_RENDER_DIRECTORY"] else{throw XCTSkip("Optional fictional My Context exports; set RELAY_RENDER_DIRECTORY.")}
        let directory=URL(fileURLWithPath:path,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let vaultRoot=FileManager.default.temporaryDirectory.appendingPathComponent("relay-fictional-context-render-"+UUID().uuidString,isDirectory:true)
        defer{try? FileManager.default.removeItem(at:vaultRoot)}
        for (name,opened,pending) in [("context-locked",false,false),("context-memory",true,false),("context-review",true,true)] {
            let vault=ProfileVault(directory:vaultRoot.appendingPathComponent(name,isDirectory:true),keys:FictionalRenderKey())
            let controller=ProfileController(client:ProfileClient(port:FictionalRenderProfilePort(pendingReview:pending)),vault:vault)
            if opened {
                // A fictional encrypted payload under the test's temp root.
                // The fake port supplies state; no production profile is read.
                try vault.save(Data("fictional-render-payload-only".utf8),createKey:true)
                await controller.openProfile()
                XCTAssertTrue(controller.opened);XCTAssertNil(controller.errorStatus)
                XCTAssertEqual(controller.memoryCount,2);XCTAssertEqual(controller.pendingCount,pending ? 1:0)
            }
            let view=VStack(spacing:0){
                Text("SYNTHETIC MY CONTEXT · fictional facts · fake key and command port").font(.system(size:10,weight:.medium)).foregroundStyle(RelayTheme.muted).frame(maxWidth:.infinity).padding(12)
                ProfilePreparationView(controller:controller,role:"developer")
            }.frame(width:920,height:720).background(RelayTheme.base).preferredColorScheme(.dark)
            try render(view,name:name,directory:directory)
            if opened{await controller.close()}
        }
    }
    private func render<V:View>(_ view:V,name:String,directory:URL)throws {
        let size=CGSize(width:920,height:720),hosting=NSHostingView(rootView:view)
        let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=hosting;hosting.frame=NSRect(origin:.zero,size:size)
        window.layoutIfNeeded();hosting.layoutSubtreeIfNeeded();RunLoop.current.run(until:Date().addingTimeInterval(0.1));hosting.layoutSubtreeIfNeeded()
        let bitmap=try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds))
        hosting.cacheDisplay(in:hosting.bounds,to:bitmap)
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:directory.appendingPathComponent(name+".png"))
        window.contentView=nil;window.close()
    }
}
