import AppKit
import Combine
import Darwin
import Foundation
import SwiftUI
import XCTest
import RelayAudioBuffer
import RelayNativeSession
import RelayProfile
import RelaySessionPanel
@testable import RelayPanelSession

@MainActor private final class AppLearningHistoryPreferences:HistorySavingPreferences{var savingEnabled=false}
@MainActor private final class AppLearningPreferences:LearningControlPreferences {
    var receipt=LearningControlReceipt(revision:nil,enabled:false,pending:nil)
    func read()->LearningControlReceipt{receipt}
    func deny(_ pending:LearningPendingControl)->LearningControlReceipt{receipt=LearningControlReceipt(revision:pending.revision,enabled:false,pending:pending);return receipt}
    func commit(_ control:LearningControlRecord)->LearningControlReceipt{receipt=LearningControlReceipt(revision:control.revision,enabled:control.enabled,pending:nil);return receipt}
}
@MainActor private final class AppLearningContextPreferences:SessionContextUsePreferences{var useInSessions=false}
@MainActor final class AppLearningProfileReceipt {
    var entered=false;private var held:CheckedContinuation<Void,Never>?
    func observe(_ data:Data)async{
        guard let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any],value["command"] as? String=="select_begin" else{return}
        entered=true;await withCheckedContinuation{held=$0}
    }
    func release(){held?.resume();held=nil}
}
final class AppLearningKey:ProfileKeyProvider,@unchecked Sendable {
    private let lock=NSLock();private var count=0
    var calls:Int{lock.withLock{count}}
    func key(createIfMissing:Bool)throws->Data{lock.withLock{count+=1};return Data(repeating:131,count:32)}
}
private actor LearningAppVAD:SpeechActivityDetector {
    nonisolated let chunkSamples=512
    private var count=0
    func accept(_ samples:[Float])async throws->[SpeechBoundary]{count+=1;return[SpeechBoundary(kind:count%2==1 ? .start:.end,sampleIndex:UInt64(count%2==1 ? (count-1)*512:count*512))]}
}
private actor LearningAppRecognizer:ActivityRecognizer {
    private var values:[String]
    init(_ values:[String]){self.values=values}
    func recognize(_ samples:[Float])async throws->String{
        // Synthetic ASR waits past the actual paced sample end. This delay is
        // not a speech-model latency measurement or an invented speech clock.
        try await Task.sleep(for:.milliseconds(80));return values.isEmpty ? "":values.removeFirst()
    }
}
private final class LearningPaintFinished:@unchecked Sendable {
    private let lock=NSLock();private var value=false
    var finished:Bool{lock.withLock{value}}
    func finish(){lock.withLock{value=true}}
}
@MainActor final class LearningAppConversation {
    static let question="Write a Python function that returns the first item or None for an empty list."
    // This fixture isolates concise wording. Stepwise wording has independent
    // derivation coverage; mixing both would make a one-rule Undo ambiguous.
    static let reply="Check empty lists and return an item when present."
    private let remoteQuestion:String
    init(remoteQuestion:String=LearningAppConversation.question){self.remoteQuestion=remoteQuestion}
    private var sequences:[UInt32:UInt64]=[:]
    func start(_ controller:NativeSessionController)throws{
        sequences=[:]
        try controller.start(selectedBundleID:"com.example.learning-fixture",microphoneEnabled:true,components:[
            1:SourceComponents(vad:LearningAppVAD(),recognizer:LearningAppRecognizer([Self.reply,Self.reply])),
            2:SourceComponents(vad:LearningAppVAD(),recognizer:LearningAppRecognizer([remoteQuestion,"What about empty input?"]))])
    }
    func speak(_ source:PCMSource,through model:SessionApplicationModel)async throws{
        for _ in 0..<2{
            let sequence=(sequences[source.rawValue] ?? 0)+1;sequences[source.rawValue]=sequence
            model.ingestFixturePacket(SessionAudioPacket(source:source,streamGeneration:1,sequence:sequence,hostTime:mach_absolute_time(),samples:Array(repeating:0.2,count:512)))
            try await Task.sleep(for:.milliseconds(33))
        }
    }
}
@MainActor private struct LearningVisibleFixtureView:View {
    @ObservedObject var model:SessionApplicationModel
    @State private var expanded=true
    var body:some View{
        LiveSessionView(state:model.relayPresentation,question:model.snapshot.question,answer:model.relayAnswer,status:model.snapshot.status,
            fixture:true,assistant:model.assistant,answerSurfaceIdentity:model.answerSurfaceIdentity,attachAnswerSurface:{[weak model] view in model?.attachAnswerSurface(view)},
            attachScroll:{window,scroll in model.attachWindow(window,scrollView:scroll)},
            expanded:$expanded,detailExpanded:$model.expanded,onAction:{_ in})
    }
}

@MainActor final class LearningApplicationTests:XCTestCase {
    private static var finishedCocoaLaunch=false
    private weak var diagnosticModel:SessionApplicationModel?
    private weak var diagnosticSurface:NSWindow?
    static func pumpCocoaEvents(){
        guard let application=NSApp else{return}
        for _ in 0..<32{guard let event=application.nextEvent(matching:.any,until:Date(),inMode:.default,dequeue:true) else{break};application.sendEvent(event)}
        application.updateWindows()
    }
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func quote(_ text:String)->String{"'"+text.replacingOccurrences(of:"'",with:"'\\''")+"'"}
    func rig(learning:Bool=true,question:String=LearningAppConversation.question,controlPreferences:(any LearningControlPreferences)?=nil,profileReceipt:AppLearningProfileReceipt?=nil,directory existingDirectory:URL?=nil,historyPreferences:(any HistorySavingPreferences)?=nil)throws->(SessionApplicationModel,LearningAppConversation,URL,AppLearningKey){
        let directory=existingDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("relay-learning-application-"+UUID().uuidString)
        if existingDirectory==nil{try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])}
        let python=ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"] ?? "/usr/bin/python3"
        let launcher=directory.appendingPathComponent("synthetic-helper"),helper=root.appendingPathComponent("tests/support/learning_memory_helper.py"),log=directory.appendingPathComponent("calls.jsonl")
        let command="exec \(quote(python)) \(quote(helper.path)) --synthetic-learning-test --log "
        // End really terminates the child. Preserve the first exclusive log
        // and give each later child a new owned file instead of reusing it.
        let script="#!/bin/sh\nif [ -e \(quote(log.path)) ]; then\n\(command)\(quote(directory.appendingPathComponent("calls-").path))$$.jsonl \"$@\"\nfi\n\(command)\(quote(log.path)) \"$@\"\n"
        try Data(script.utf8).write(to:launcher)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:launcher.path)
        let key=AppLearningKey(),history=historyPreferences ?? AppLearningHistoryPreferences(),controls=controlPreferences ?? AppLearningPreferences(),conversation=LearningAppConversation(remoteQuestion:question)
        let storage=HistoryVaultStorage(directory:directory.appendingPathComponent("Relay/History"),keys:key)
        let profileFactory:(@Sendable ()->ProfileVault)?
        let observer:(@MainActor (Data)async->Void)?
        let context:(any SessionContextUsePreferences)?
        if let profileReceipt{
            profileFactory={ProfileVault(directory:directory.appendingPathComponent("Profile"),keys:key)}
            observer={data in await profileReceipt.observe(data)}
            context=AppLearningContextPreferences()
        }else{profileFactory=nil;observer=nil;context=nil}
        let model=SessionApplicationModel(arguments:["relay","--fixture-suite","coding","--role","developer","--repository",root.path,"--python",launcher.path],
            contextPreferences:context,profileVaultFactory:profileFactory,profileResponseObserved:observer,
            historyPreferences:history,historyStorageFactory:{storage},learningPreferences:learning ? controls:nil,fixtureSessionStart:conversation.start)
        diagnosticModel=model
        addTeardownBlock{await model.shutdown();if existingDirectory==nil{try? FileManager.default.removeItem(at:directory)}}
        return(model,conversation,directory,key)
    }
    func until(file:StaticString=#filePath,line:UInt=#line,_ condition:()->Bool)async throws{
        let deadline=ContinuousClock.now+Duration.seconds(8)
        while true{
            if diagnosticSurface != nil{
                // XCTest's Foundation loop does not dispatch AppKit events.
                // Serve the real owned app queue; never invent occlusion state.
                Self.pumpCocoaEvents()
            }
            if condition(){return}
            guard ContinuousClock.now<deadline else{
                let model=diagnosticModel,surface=diagnosticSurface,sample=model?.responseLatencySamples.last
                let state="line=\(line) running=\(model?.running==true) card=\(model?.snapshot.card != nil) modelAvailable=\(sample?.modelAvailableAt != nil) windowVisible=\(sample?.windowVisibleAt != nil) surfaceVisible=\(surface?.isVisible==true) occlusion=\(surface?.occlusionState.contains(.visible)==true) appActive=\(NSApp.isActive) appRunning=\(NSApp.isRunning) key=\(surface != nil && NSApp.keyWindow === surface) rows=\(model?.assistant.transcript.snapshot.rows.count ?? -1) episodes=\(model?.learning.session.episodes.count ?? -1) retained=\(model?.learning.retainedEpisodes.count ?? -1)"
                XCTFail(state,file:file,line:line);throw HistoryError.unavailable
            }
            try await Task.sleep(for:.milliseconds(3))
        }
    }
    func window(_ model:SessionApplicationModel,show:Bool=true)->NSWindow{
        let application=NSApplication.shared,originalPolicy=application.activationPolicy(),frontmost=NSWorkspace.shared.frontmostApplication
        _=application.setActivationPolicy(.regular)
        if !Self.finishedCocoaLaunch{application.finishLaunching();Self.finishedCocoaLaunch=true}
        let window=NSWindow(contentRect:NSRect(x:80,y:80,width:706,height:600),styleMask:[.titled,.fullSizeContentView],backing:.buffered,defer:false)
        RelayWindowShell().attachLive(window)
        window.isReleasedWhenClosed=false;window.contentView=NSHostingView(rootView:LearningVisibleFixtureView(model:model))
        diagnosticSurface=window
        window.contentView?.layoutSubtreeIfNeeded();model.attachWindow(window,scrollView:nil)
        // Exercise the production own-window action, including app activation
        // and key-window presentation. A background XCTest window is occluded.
        if show{model.performWindowAction(.showPanel)}
        addTeardownBlock{
            await MainActor.run{window.orderOut(nil);window.close();_=application.setActivationPolicy(originalPolicy);if let frontmost,!frontmost.isTerminated{_=frontmost.activate(options:[])}}
            // Settle the real close/deactivation/foreground notifications before
            // another XCTest window requests activation in this same process.
            for _ in 0..<50{await MainActor.run{Self.pumpCocoaEvents()};try? await Task.sleep(for:.milliseconds(8))}
            await MainActor.run{
                XCTAssertEqual(application.activationPolicy(),originalPolicy)
                if let frontmost,!frontmost.isTerminated{XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier,frontmost.processIdentifier)}
            }
        }
        return window
    }
    /// Read only this owned view's accessibility geometry. No external AX API,
    /// screen capture or copied visibility receipt is involved.
    private func textFrames(in root:NSObject,wanted:Set<String>)->[String:NSRect]{
        var queue=[root],seen:Set<ObjectIdentifier>=[],result:[String:NSRect]=[:]
        while !queue.isEmpty,seen.count<512{
            let object=queue.removeFirst();guard seen.insert(ObjectIdentifier(object)).inserted else{continue}
            func value(_ key:String)->Any?{object.responds(to:NSSelectorFromString(key)) ? object.value(forKey:key):nil}
            let words=[value("accessibilityValue"),value("accessibilityLabel")].compactMap{$0 as? String}
            if let text=words.first(where:wanted.contains),let frame=value("accessibilityFrame") as? NSValue,frame.rectValue.width>0,frame.rectValue.height>0{result[text]=frame.rectValue}
            if let children=value("accessibilityChildren") as? [Any]{queue.append(contentsOf:children.compactMap{$0 as? NSObject})}
        }
        return result
    }
    func testDefaultFixtureCannotEnableLearningOrReachProductionControlAndHistoryStorage()async throws{
        let python=ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"] ?? "/usr/bin/python3"
        let model=SessionApplicationModel(arguments:["relay","--fixture-suite","coding","--repository",root.path,"--python",python])
        XCTAssertFalse(model.canEnableLearning)
        do{try await model.learning.enable();XCTFail("Default fixture must remain unavailable")}catch{}
        XCTAssertTrue(model.learning.retainedEpisodes.isEmpty);await model.shutdown()
        let(injected,_,_,key)=try rig(learning:false)
        XCTAssertFalse(injected.canEnableLearning);XCTAssertEqual(key.calls,0)
        do{try await injected.learning.enable();XCTFail("History-only synthetic injection does not authorize production CF")}catch{}
        XCTAssertEqual(key.calls,0)
    }
    func testActualVisibleSuggestionOriginalMicContinuationEndAndLaterSessionChangeWithNoExtraCalls()async throws{
        if try await LearningGUIWitness.run(caseClass:Self.self,method:"testActualVisibleSuggestionOriginalMicContinuationEndAndLaterSessionChangeWithNoExtraCalls"){return}
        let(model,conversation,directory,_)=try rig();let surface=window(model);surface.orderFront(nil)
        try await model.history.enableSaving();try await model.learning.enable()
        var baseline:String?
        for _ in 0..<3{
            await model.start();try await conversation.speak(.remoteAudio,through:model)
            try await until{model.snapshot.card != nil && model.responseLatencySamples.last?.windowVisibleAt != nil}
            if baseline==nil{baseline=model.snapshot.card?.lead}
            try await conversation.speak(.microphone,through:model)
            try await until{model.assistant.transcript.snapshot.rows.contains{$0.source == .microphone}}
            try await conversation.speak(.remoteAudio,through:model)
            try await until{!model.learning.session.episodes.isEmpty}
            let episode=try XCTUnwrap(model.learning.session.episodes.first)
            XCTAssertGreaterThanOrEqual(episode.reply.startUptimeNanoseconds.value,episode.suggestion.availableAt.value)
            XCTAssertEqual(episode.reply.source,.microphone);XCTAssertEqual(episode.continuation.source,.selectedAppAudio)
            await model.stop();await model.learning.waitForQuiescence()
        }
        XCTAssertEqual(model.learning.retainedEpisodes.count,3)
        await model.start();try await conversation.speak(.remoteAudio,through:model)
        try await until{model.snapshot.card != nil && model.snapshot.learningMemoryRevision != nil}
        XCTAssertNotEqual(model.snapshot.card?.lead,baseline)
        XCTAssertEqual(model.snapshot.card?.detail?.text,"def first_or_none(items):\n    return items[0] if items else None\n")
        for _ in 0..<12{
            let before=model.snapshot.replacement;try model.perform(.requestHelp)
            try await until{model.snapshot.card != nil && model.snapshot.replacement>before}
            XCTAssertTrue(model.running);XCTAssertNotNil(model.snapshot.learningMemoryRevision)
        }
        let undo=model.learning.undo("technical:concise_lead")
        XCTAssertNil(model.snapshot.card);XCTAssertTrue(model.running);try await undo.value
        try model.perform(.requestHelp);try await until{model.snapshot.card != nil}
        XCTAssertEqual(model.snapshot.card?.lead,baseline)
        let entries=(try? String(contentsOf:directory.appendingPathComponent("calls.jsonl"),encoding:.utf8))?.split(separator:"\n") ?? []
        XCTAssertFalse(entries.isEmpty);XCTAssertTrue(entries.allSatisfy{!$0.contains("first item or None")})
    }
    func testHiddenCommitThenActualWindowExposureUsesLaterOriginalMicAndNoDuplicateAvailability()async throws{
        if try await LearningGUIWitness.run(caseClass:Self.self,method:"testHiddenCommitThenActualWindowExposureUsesLaterOriginalMicAndNoDuplicateAvailability"){return}
        let(model,conversation,_,_)=try rig();try await model.history.enableSaving();try await model.learning.enable()
        await model.start();try await conversation.speak(.remoteAudio,through:model)
        try await until{model.snapshot.card != nil && model.responseLatencySamples.last?.modelAvailableAt != nil}
        XCTAssertNil(model.responseLatencySamples.last?.windowVisibleAt)
        try await conversation.speak(.microphone,through:model);try await until{model.assistant.transcript.snapshot.rows.contains{$0.source == .microphone}}
        let before=try XCTUnwrap(model.assistant.transcript.snapshot.rows.first{$0.source == .microphone})
        let surface=window(model);surface.orderFront(nil)
        try await until{model.responseLatencySamples.last?.windowVisibleAt != nil}
        try await conversation.speak(.microphone,through:model)
        try await until{model.assistant.transcript.snapshot.rows.filter{$0.source == .microphone}.count==2}
        try await conversation.speak(.remoteAudio,through:model);try await until{!model.learning.session.episodes.isEmpty}
        let episode=try XCTUnwrap(model.learning.session.episodes.first)
        XCTAssertGreaterThan(episode.reply.startUptimeNanoseconds.value,before.endUptimeNanoseconds)
        XCTAssertGreaterThanOrEqual(episode.reply.startUptimeNanoseconds.value,episode.suggestion.availableAt.value)
        XCTAssertEqual(model.learning.session.episodes.count,1)
    }
    func testOffViewportLeadAndPointsCannotCreditEarlierMicBeforeActualScrollExposure()async throws{
        if try await LearningGUIWitness.run(caseClass:Self.self,method:"testOffViewportLeadAndPointsCannotCreditEarlierMicBeforeActualScrollExposure"){return}
        let question=String((LearningAppConversation.question+" "+String(repeating:"WWWWW ",count:80)).prefix(490))
        let(model,conversation,_,_)=try rig(question:question)
        try await model.history.enableSaving();try await model.learning.enable();await model.start()
        try await conversation.speak(.remoteAudio,through:model)
        try await until{model.snapshot.card != nil}
        model.expanded=true
        let surface=window(model,show:false)
        func scrolls(_ view:NSView)->[NSScrollView]{(view as? NSScrollView).map{[$0]} ?? view.subviews.flatMap{scrolls($0)}}
        surface.contentView?.layoutSubtreeIfNeeded()
        try await until{surface.contentView.map{scrolls($0).contains{($0.documentView?.bounds.height ?? 0)>$0.contentView.bounds.height+1}} ?? false}
        let scroll=try XCTUnwrap(scrolls(try XCTUnwrap(surface.contentView)).max{
            ($0.documentView?.bounds.height ?? 0)-$0.contentView.bounds.height < ($1.documentView?.bounds.height ?? 0)-$1.contentView.bounds.height
        })
        let document=try XCTUnwrap(scroll.documentView)
        let card=try XCTUnwrap(model.snapshot.card),wanted=Set([card.lead]+card.points)
        func frames()->[NSRect]{Array(textFrames(in:surface.contentView!,wanted:wanted).values)}
        func viewport()->NSRect{surface.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds,to:nil))}
        print("LEARNING_VIEWPORT_GEOMETRY documentHeight=\(document.bounds.height) clipHeight=\(scroll.contentView.bounds.height)")
        XCTAssertGreaterThan(document.bounds.height,scroll.contentView.bounds.height)
        scroll.contentView.scroll(to:.zero);scroll.reflectScrolledClipView(scroll.contentView)
        model.performWindowAction(.showPanel)
        try await until{surface.isVisible && surface.occlusionState.contains(.visible) && frames().count==wanted.count}
        XCTAssertFalse(frames().allSatisfy{viewport().contains($0)},"The real lead/points must be clipped before the earlier microphone source starts")
        try await conversation.speak(.microphone,through:model)
        try await until{model.assistant.transcript.snapshot.rows.filter{$0.source == .microphone}.count==1}
        let earlier=try XCTUnwrap(model.assistant.transcript.snapshot.rows.first{$0.source == .microphone})
        let spoken=frames().reduce(NSRect.null){$0.union($1)},local=document.convert(surface.convertFromScreen(spoken),from:nil)
        let y=min(max(0,local.midY-scroll.contentView.bounds.height/2),max(0,document.bounds.height-scroll.contentView.bounds.height))
        scroll.contentView.scroll(to:NSPoint(x:0,y:y))
        scroll.reflectScrolledClipView(scroll.contentView);surface.contentView?.layoutSubtreeIfNeeded()
        try await until{frames().count==wanted.count && frames().allSatisfy{viewport().contains($0)}}
        try await Task.sleep(for:.milliseconds(33))
        try await conversation.speak(.microphone,through:model)
        try await until{model.assistant.transcript.snapshot.rows.filter{$0.source == .microphone}.count==2}
        try await conversation.speak(.remoteAudio,through:model);try await until{!model.learning.session.episodes.isEmpty}
        let episode=try XCTUnwrap(model.learning.session.episodes.first)
        XCTAssertGreaterThan(episode.suggestion.availableAt.value,earlier.endUptimeNanoseconds)
        XCTAssertGreaterThanOrEqual(episode.reply.startUptimeNanoseconds.value,episode.suggestion.availableAt.value)
        XCTAssertTrue(episode.signal.eligibleForStyle,"Only the later original reply follows real lead/points exposure")
        XCTAssertEqual(model.learning.session.episodes.count,1)
    }
    func testOptionalLearningPreparationUsesReadyHistoryWithoutRetiringOriginalNotesSource()async throws{
        let(model,conversation,_,_)=try rig();try await model.history.enableSaving();try await model.learning.enable()
        await model.start();try await conversation.speak(.remoteAudio,through:model);try await until{model.snapshot.card != nil}
        await model.stop();let record=try XCTUnwrap(model.history.snapshot.records.first)
        try await model.history.openRecord(record.id)
        let detail=try XCTUnwrap(model.history.snapshot.selected);var retired=false
        let source=try await model.history.prepareNotesSource(recordID:record.id,expectedRevision:detail.record.revision,
            selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{_ in retired=true})
        XCTAssertTrue(model.history.ownsNotesSource(source));let workspace=model.history.snapshot.epoch
        model.assistant.draft="Explain bounded queues.";model.assistant.submitDraft()
        try await until{model.snapshot.card != nil && model.assistantActive}
        XCTAssertFalse(retired,"Optional Learning read must not reopen and retire an already ready original Notes source")
        XCTAssertTrue(model.history.ownsNotesSource(source));XCTAssertEqual(model.history.snapshot.epoch,workspace)
    }
    func testMismatchedLearningReceiptCannotReopenReadyHistoryOrRetireNotesSource()async throws{
        let controls=AppLearningPreferences(),(model,conversation,_,_)=try rig(controlPreferences:controls)
        try await model.history.enableSaving();try await model.learning.enable();await model.start()
        try await conversation.speak(.remoteAudio,through:model);try await until{model.snapshot.card != nil};await model.stop()
        let record=try XCTUnwrap(model.history.snapshot.records.first);try await model.history.openRecord(record.id)
        let detail=try XCTUnwrap(model.history.snapshot.selected);var retired=false
        let source=try await model.history.prepareNotesSource(recordID:record.id,expectedRevision:detail.record.revision,
            selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{_ in retired=true})
        let workspace=model.history.snapshot.epoch
        controls.receipt=LearningControlReceipt(revision:UUID(),enabled:true,pending:nil)
        model.assistant.draft="Explain bounded queues.";model.assistant.submitDraft();try await until{model.snapshot.card != nil && model.assistantActive}
        XCTAssertFalse(retired);XCTAssertTrue(model.history.ownsNotesSource(source));XCTAssertEqual(model.history.snapshot.epoch,workspace)
        XCTAssertNotEqual(model.learning.snapshot.phase,.ready);XCTAssertNil(model.snapshot.learningMemoryRevision)
    }
    func testActualProfileEmergencyEndRetiresLiveLearningBeforeHeldOriginalJoin()async throws{
        let receipt=AppLearningProfileReceipt(),(model,conversation,_,_)=try rig(profileReceipt:receipt)
        model.openMyContext();await model.contextUse.waitForQuiescence();XCTAssertTrue(model.profile.opened)
        try await model.history.enableSaving();try await model.learning.enable();await model.start()
        try await conversation.speak(.remoteAudio,through:model);try await until{model.snapshot.card != nil}
        let original=try XCTUnwrap(model.learning.capture(question:"empty list")),profile=model.profile
        XCTAssertTrue(original.payload.continuity.contains{$0.text.contains("empty list")})
        let edit=Task{await profile.stageEnteredText("Fictional pending source.",purpose:"project",label:"Synthetic held source",role:model.role,project:"Fictional project")}
        do{
            try await until{receipt.entered};model.lockMyContext()
            try await until{!model.running && profile.busy}
            XCTAssertNil(model.learning.capture(question:"empty list"),"An actual forced helper end must retire its live semantic context before joining a held old profile request")
            XCTAssertFalse(model.learning.owns(original));XCTAssertFalse(model.canStartSession)
            receipt.release();await edit.value;await model.contextUse.waitForQuiescence()
        }catch{receipt.release();await edit.value;throw error}
    }
    func testActualModelPublicationReentrantLearningDisableHasOwnedWatchdogAndNoAvailability()async throws{
        let key="RELAY_LEARNING_MODEL_PAINT_CHILD"
        if ProcessInfo.processInfo.environment[key]=="1"{
            let finished=LearningPaintFinished();FileHandle.standardError.write(Data("LEARNING_MODEL_PAINT_CHILD_STARTED\n".utf8))
            DispatchQueue.global().asyncAfter(deadline:.now()+8){if !finished.finished{Darwin._exit(86)}}
            let(model,conversation,_,_)=try rig();try await model.history.enableSaving();try await model.learning.enable()
            await model.start();try await conversation.speak(.remoteAudio,through:model);try await until{model.snapshot.card != nil}
            var fired=false
            let observation=model.$snapshot.sink{[weak model] incoming in
                guard let model,!fired,incoming.card != nil,incoming.learningMemoryRevision != nil else{return}
                fired=true;_=model.learning.disable()
            }
            try model.perform(.requestHelp);try await until{fired}
            XCTAssertNil(model.snapshot.card);XCTAssertTrue(model.running)
            XCTAssertNil(model.responseLatencySamples.last?.modelAvailableAt)
            observation.cancel();await model.learning.waitForQuiescence();await model.shutdown();finished.finish();return
        }
        let child=Process(),finished=LearningPaintFinished(),errors=Pipe()
        child.executableURL=URL(fileURLWithPath:"/usr/bin/xcrun")
        child.arguments=["xctest","-XCTest","RelaySessionApplicationTests.LearningApplicationTests/testActualModelPublicationReentrantLearningDisableHasOwnedWatchdogAndNoAvailability",Bundle(for:Self.self).bundleURL.path]
        var environment=ProcessInfo.processInfo.environment;environment[key]="1";child.environment=environment
        child.standardOutput=FileHandle.nullDevice;child.standardError=errors;child.terminationHandler={_ in finished.finish()}
        try child.run();try errors.fileHandleForWriting.close()
        for _ in 0..<5000{if finished.finished{break};try await Task.sleep(for:.milliseconds(2))}
        if !finished.finished{child.terminate()}
        for _ in 0..<500{if finished.finished{break};try await Task.sleep(for:.milliseconds(2))}
        guard finished.finished else{_=Darwin.kill(child.processIdentifier,SIGKILL);XCTFail("Owned Model publication child failed to exit");return}
        let log=String(data:errors.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8) ?? ""
        XCTAssertTrue(log.contains("LEARNING_MODEL_PAINT_CHILD_STARTED"));XCTAssertEqual(child.terminationStatus,0,log)
    }
}
