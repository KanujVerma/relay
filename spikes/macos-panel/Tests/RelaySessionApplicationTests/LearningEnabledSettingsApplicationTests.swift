import AppKit
import CoreFoundation
import Foundation
import SwiftUI
import XCTest
import RelaySessionPanel
@testable import RelayPanelSession

/// Test-only local view traversal. No AXUIElement, event synthesis, Cua or
/// cross-application contents are used. Presses invoke the rendered control.
@MainActor private enum OwnedLearningSettingsControls {
    static func value(_ object:NSObject,_ key:String)->Any?{
        object.responds(to:NSSelectorFromString(key)) ? object.value(forKey:key):nil
    }
    static func elements(_ root:NSObject)->[NSObject]{
        var queue=[root],seen=Set<ObjectIdentifier>(),result:[NSObject]=[]
        while !queue.isEmpty,seen.count<512{
            let object=queue.removeFirst()
            guard seen.insert(ObjectIdentifier(object)).inserted else{continue}
            result.append(object)
            if let children=value(object,"accessibilityChildren") as? [Any]{
                queue.append(contentsOf:children.compactMap{$0 as? NSObject})
            }
        }
        return result
    }
    static func text(_ root:NSObject)->String{
        elements(root).flatMap{object in
            ["accessibilityLabel","accessibilityValue","accessibilityTitle"].compactMap{value(object,$0) as? String}
        }.joined(separator:"\n")
    }
    static func press(_ label:String,in root:NSObject)throws{
        let matches=elements(root).filter{object in
            (value(object,"accessibilityRole") as? String)=="AXButton"
                && ["accessibilityLabel","accessibilityTitle"].contains{(value(object,$0) as? String)==label}
        }
        guard matches.count==1 else{
            XCTFail("Expected exactly one rendered owned button: "+label);throw HistoryError.invalid
        }
        let object=try XCTUnwrap(matches.first)
        if let button=object as? NSButton{
            XCTAssertTrue(button.isEnabled);button.performClick(nil)
        }else{
            // Public AppKit NSAccessibilityProtocol, operating on this local
            // object only. A missing/unsupported action fails the test.
            let button=try XCTUnwrap(object as? NSAccessibilityProtocol)
            XCTAssertTrue(button.accessibilityPerformPress(),"Owned button rejected Press: "+label)
        }
    }
}

extension LearningApplicationTests {
    /// Source-only acceptance candidate from cd5233be3a99e9fbbf90b3fde27103e86191bb07.
    /// Reuses the existing fictional audio/completion/key ports and actual
    /// History/CF receipts. No real account or provider call is permitted.
    func testEnabledLearningSettingsBoundExamplesReviewAndUndoPreserveOriginalHistory()async throws{
        let domain="com.relay.fixture.learning.settings."+UUID().uuidString.lowercased()
        let defaults=try XCTUnwrap(UserDefaults(suiteName:domain))
        let controls=CFPreferencesLearningControls(domain:domain)
        // Register before rig teardown: actual model/helper shutdown must join
        // before removing this one uniquely owned fictional preference domain.
        addTeardownBlock{
            for key in ["relay.learning.control-receipt.v1","relay.history.saving-enabled.v1"]{
                CFPreferencesSetAppValue(key as CFString,nil,domain as CFString)
            }
            XCTAssertTrue(CFPreferencesAppSynchronize(domain as CFString))
        }
        let(model,conversation,_,_)=try rig(controlPreferences:controls,
            historyPreferences:UserDefaultsHistoryPreferences(defaults:defaults))
        _=window(model)
        try await model.history.enableSaving();try await model.learning.enable()
        var baseline:String?
        for _ in 0..<3{
            await model.start();try await conversation.speak(.remoteAudio,through:model)
            try await until{model.snapshot.card != nil && model.responseLatencySamples.last?.windowVisibleAt != nil}
            if baseline==nil{baseline=model.snapshot.card?.lead}
            try await conversation.speak(.microphone,through:model)
            try await until{model.assistant.transcript.snapshot.rows.contains{$0.source == .microphone}}
            try await conversation.speak(.remoteAudio,through:model)
            try await until{model.learning.session.episodes.first?.signal.eligibleForStyle==true}
            let original=try XCTUnwrap(model.learning.session.episodes.first)
            XCTAssertGreaterThanOrEqual(original.reply.startUptimeNanoseconds.value,original.suggestion.availableAt.value)
            await model.stop();await model.learning.waitForQuiescence()
        }
        let episodes=model.learning.retainedEpisodes
        XCTAssertEqual(episodes.count,3);XCTAssertGreaterThanOrEqual(Set(episodes.compactMap(\.recordID)).count,2)
        XCTAssertTrue(episodes.allSatisfy{$0.scope == .technical && $0.signal.eligibleForStyle})
        XCTAssertTrue(model.learning.snapshot.rules.contains{$0.id=="technical:concise_lead" && !$0.suppressed})
        let original=try XCTUnwrap(episodes.first),receipt=try await controls.read()
        XCTAssertTrue(receipt.enabled);XCTAssertNil(receipt.pending)
        await model.start();try await conversation.speak(.remoteAudio,through:model)
        try await until{model.snapshot.card != nil && model.snapshot.learningMemoryRevision != nil}
        XCTAssertNotEqual(model.snapshot.card?.lead,try XCTUnwrap(baseline))
        let capture=try XCTUnwrap(model.currentSessionID)
        let records=Set(model.history.snapshot.records.map(\.id))
        var navigations=0
        let settings=NSWindow(contentRect:NSRect(x:90,y:90,width:720,height:640),
            styleMask:[.titled,.closable],backing:.buffered,defer:false)
        settings.isReleasedWhenClosed=false
        settings.contentView=NSHostingView(rootView:LearningMemorySettingsSection(memory:model.learning,openHistory:{navigations+=1})
            .padding(24).frame(width:720,height:640).background(Color.black).foregroundStyle(.white).preferredColorScheme(.dark))
        settings.contentView?.layoutSubtreeIfNeeded();settings.makeKeyAndOrderFront(nil)
        addTeardownBlock{await MainActor.run{settings.orderOut(nil);settings.contentView=nil;settings.close()}}
        let root=try XCTUnwrap(settings.contentView)
        try await until{settings.isVisible && OwnedLearningSettingsControls.text(root).contains("See examples")}
        try OwnedLearningSettingsControls.press("See examples",in:root)
        try await until{settings.attachedSheet?.contentView.map{OwnedLearningSettingsControls.text($0).contains("Why this preference?")}==true}
        let why=try XCTUnwrap(settings.attachedSheet?.contentView)
        let whyText=OwnedLearningSettingsControls.text(why)
        for label in ["Question · selected app audio","Suggestion available","Reply · microphone","What followed · selected app audio"]{
            XCTAssertTrue(whyText.contains(label),"Missing original-source inspector label: "+label)
        }
        for text in [original.question.text,try XCTUnwrap(baseline),original.reply.text,original.continuation.text]{XCTAssertTrue(whyText.contains(text))}
        XCTAssertEqual(Set(model.learning.retainedEpisodes.map(\.id)),Set(episodes.map(\.id)))
        try OwnedLearningSettingsControls.press("Close",in:why)
        try await until{settings.attachedSheet==nil}
        try OwnedLearningSettingsControls.press("Review saved examples",in:root)
        try await until{settings.attachedSheet?.contentView.map{OwnedLearningSettingsControls.text($0).contains("Saved learning examples")}==true}
        let review=try XCTUnwrap(settings.attachedSheet?.contentView)
        XCTAssertTrue(OwnedLearningSettingsControls.text(review).contains(original.reply.text))
        try OwnedLearningSettingsControls.press("Close",in:review)
        try await until{settings.attachedSheet==nil}
        try OwnedLearningSettingsControls.press("Undo",in:root)
        XCTAssertNil(model.snapshot.card,"The bound Undo action must retire the used card synchronously")
        XCTAssertTrue(model.running);XCTAssertEqual(model.currentSessionID,capture)
        await model.learning.waitForQuiescence()
        try await until{OwnedLearningSettingsControls.text(root).contains("Undone")}
        XCTAssertTrue(model.learning.snapshot.rules.contains{$0.id=="technical:concise_lead" && $0.suppressed})
        let after=try await controls.read()
        XCTAssertTrue(after.enabled);XCTAssertNil(after.pending);XCTAssertNotEqual(after.revision,receipt.revision)
        XCTAssertEqual(Set(model.learning.retainedEpisodes.map(\.id)),Set(episodes.map(\.id)))
        XCTAssertEqual(Set(model.history.snapshot.records.map(\.id)),records);XCTAssertEqual(navigations,0)
        try model.perform(.requestHelp);try await until{model.snapshot.card != nil}
        XCTAssertEqual(model.snapshot.card?.lead,baseline);XCTAssertTrue(model.running)
        await model.stop();await model.learning.waitForQuiescence()
    }
}
