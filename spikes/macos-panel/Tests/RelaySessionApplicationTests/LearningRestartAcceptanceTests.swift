import AppKit
import CoreFoundation
import Foundation
import XCTest
import RelayAudioBuffer
import RelaySessionPanel
@testable import RelayPanelSession

/// Four separately launched actual app instances share only an explicitly
/// fictional encrypted History directory and a unique content-free CF domain.
/// The helper completion stays synthetic; all source/ownership/control IO is real.
extension LearningApplicationTests {
    private var restartMethod:String{"testFreshProcessesRestoreAndReversiblyApplyProtectedLearning"}
    private var restartPhaseKey:String{"RELAY_LEARNING_ACCEPTANCE_PHASE"}
    private var restartDomainKey:String{"RELAY_LEARNING_ACCEPTANCE_DOMAIN"}
    private var restartDirectoryKey:String{"RELAY_LEARNING_ACCEPTANCE_DIRECTORY"}
    private var baselineLearningLead:String{"Check the input contract, then explain the empty-list case before returning the first item."}
    private var expectedLearningCode:String{"def first_or_none(items):\n    return items[0] if items else None\n"}
    private func phaseProof(_ directory:URL,_ phase:String,_ values:[String:Any])throws{
        var value=values;value["phase"]=phase;value["pid"]=ProcessInfo.processInfo.processIdentifier
        try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]).write(to:directory.appendingPathComponent("acceptance-"+phase+".json"),options:.withoutOverwriting)
    }
    private func proof(_ directory:URL,_ phase:String)throws->[String:Any]{
        try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("acceptance-"+phase+".json"))) as? [String:Any])
    }
    private func nextPhase(_ phase:String,directory:URL,domain:String)async throws{
        _=try await LearningGUIWitness.run(caseClass:Self.self,method:restartMethod,
            environmentOverrides:[restartPhaseKey:phase,restartDirectoryKey:directory.path,restartDomainKey:domain],
            forceChild:true,pump:Self.pumpCocoaEvents)
    }
    private func finishAcceptanceModel(_ model:SessionApplicationModel)async throws{
        let original=try model.ensureHelper()
        await model.stop();await model.shutdown()
        XCTAssertTrue(original.hasExited,"The actual helper's exit receipt must complete independently of the GUI host group")
    }
    func testFreshProcessesRestoreAndReversiblyApplyProtectedLearning()async throws{
        if try await LearningGUIWitness.run(caseClass:Self.self,method:restartMethod){return}
        let environment=ProcessInfo.processInfo.environment,phase=environment[restartPhaseKey] ?? "train"
        if phase=="train"{
            let domain="com.relay.fixture.learning.restart."+UUID().uuidString.lowercased()
            let defaults=try XCTUnwrap(UserDefaults(suiteName:domain)),controls=CFPreferencesLearningControls(domain:domain)
            defer{
                for key in ["relay.learning.control-receipt.v1","relay.history.saving-enabled.v1"]{CFPreferencesSetAppValue(key as CFString,nil,domain as CFString)}
                _=CFPreferencesAppSynchronize(domain as CFString)
            }
            let(model,conversation,directory,_)=try rig(controlPreferences:controls,historyPreferences:UserDefaultsHistoryPreferences(defaults:defaults))
            try JSONSerialization.data(withJSONObject:["domain":domain]).write(to:directory.appendingPathComponent("acceptance-owner.json"),options:.withoutOverwriting)
            _=window(model)
            try await model.history.enableSaving();try await model.learning.enable()
            for _ in 0..<4{
                await model.start();try await conversation.speak(.remoteAudio,through:model)
                try await until{model.snapshot.card != nil && model.responseLatencySamples.last?.windowVisibleAt != nil}
                try await conversation.speak(.microphone,through:model)
                try await until{model.assistant.transcript.snapshot.rows.contains{$0.source == .microphone}}
                try await conversation.speak(.remoteAudio,through:model);try await until{!model.learning.session.episodes.isEmpty}
                let episode=try XCTUnwrap(model.learning.session.episodes.first)
                XCTAssertTrue(episode.signal.eligibleForStyle)
                XCTAssertGreaterThanOrEqual(episode.reply.startUptimeNanoseconds.value,episode.suggestion.availableAt.value)
                let original=try model.ensureHelper();await model.stop();XCTAssertTrue(original.hasExited)
            }
            XCTAssertEqual(model.learning.retainedEpisodes.count,4)
            let committed=try await controls.read();XCTAssertTrue(committed.enabled);XCTAssertNil(committed.pending)
            XCTAssertTrue(CFPreferencesAppSynchronize(domain as CFString))
            XCTAssertEqual(CFPreferencesCopyAppValue("relay.history.saving-enabled.v1" as CFString,domain as CFString) as? Bool,true)
            try phaseProof(directory,"train",["retained":4])
            await model.shutdown()
            try await nextPhase("apply",directory:directory,domain:domain)
            let proofs=try ["train","apply","undone","off"].map{try proof(directory,$0)}
            let pids=proofs.compactMap{$0["pid"] as? Int}
            XCTAssertEqual(pids.count,4);XCTAssertEqual(Set(pids).count,4,"Every restore/control phase must be a different actual process")
            XCTAssertEqual(proofs[1]["retained"] as? Int,3);XCTAssertEqual(proofs[2]["retained"] as? Int,0)
            XCTAssertEqual(proofs[3]["enabled"] as? Bool,false)
            return
        }
        guard ["apply","undone","off"].contains(phase),let domain=environment[restartDomainKey],
              domain.hasPrefix("com.relay.fixture.learning.restart."),UUID(uuidString:String(domain.dropFirst("com.relay.fixture.learning.restart.".count))) != nil,
              let path=environment[restartDirectoryKey] else{throw HistoryError.invalid}
        let directory=URL(fileURLWithPath:path).standardizedFileURL
        guard directory.deletingLastPathComponent().resolvingSymlinksInPath()==FileManager.default.temporaryDirectory.resolvingSymlinksInPath(),
              directory.lastPathComponent.hasPrefix("relay-learning-application-"),
              let owner=try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("acceptance-owner.json"))) as? [String:String],owner==["domain":domain] else{throw HistoryError.invalid}
        let defaults=try XCTUnwrap(UserDefaults(suiteName:domain)),history=UserDefaultsHistoryPreferences(defaults:defaults),controls=CFPreferencesLearningControls(domain:domain)
        XCTAssertTrue(history.savingEnabled,"The fresh process must read the actual persisted History opt-in")
        let(model,conversation,_,_)=try rig(controlPreferences:controls,directory:directory,historyPreferences:history)
        _=window(model);await model.start();try await conversation.speak(.remoteAudio,through:model)
        try await until{model.snapshot.card != nil && model.responseLatencySamples.last?.windowVisibleAt != nil}
        XCTAssertEqual(model.snapshot.card?.detail?.text,expectedLearningCode)
        let boot=try await controls.read();XCTAssertNil(boot.pending)
        if phase=="apply"{
            XCTAssertTrue(boot.enabled);XCTAssertEqual(model.learning.retainedEpisodes.count,4)
            XCTAssertNotEqual(model.snapshot.card?.lead,baselineLearningLead);XCTAssertNotNil(model.snapshot.learningMemoryRevision)
            let projection=try XCTUnwrap(model.learning.capture(question:LearningAppConversation.question))
            let used=try XCTUnwrap(projection.payload.sourceRecordIDs.sorted{$0.uuidString<$1.uuidString}.first)
            await model.history.waitForQuiescence()
            let record=try XCTUnwrap(model.history.snapshot.records.first{$0.id==used})
            let deletion=model.history.delete(record.id,expectedRevision:record.revision)
            XCTAssertNil(model.snapshot.card);XCTAssertTrue(model.running)
            try await deletion.value;try await model.learning.restore()
            XCTAssertEqual(model.learning.retainedEpisodes.count,3);XCTAssertFalse(model.learning.retainedEpisodes.contains{$0.recordID==used})
            let afterDelete=try await controls.read();XCTAssertEqual(afterDelete,boot,"Source/data deletion must not silently revise consent")
            try model.perform(.requestHelp);try await until{model.snapshot.card != nil}
            XCTAssertNotEqual(model.snapshot.card?.lead,baselineLearningLead,"Three remaining genuine source examples still support the tentative rule")
            let undo=model.learning.undo("technical:concise_lead")
            XCTAssertNil(model.snapshot.card);XCTAssertTrue(model.running);try await undo.value
            try model.perform(.requestHelp);try await until{model.snapshot.card != nil}
            XCTAssertEqual(model.snapshot.card?.lead,baselineLearningLead)
            XCTAssertTrue(model.learning.snapshot.rules.contains{$0.id=="technical:concise_lead" && $0.suppressed})
            try phaseProof(directory,"apply",["retained":3,"deletedRecord":used.uuidString.lowercased()])
            try await finishAcceptanceModel(model)
            try await nextPhase("undone",directory:directory,domain:domain)
        }else if phase=="undone"{
            XCTAssertTrue(boot.enabled);XCTAssertEqual(model.learning.retainedEpisodes.count,3)
            XCTAssertEqual(model.snapshot.card?.lead,baselineLearningLead)
            XCTAssertTrue(model.learning.snapshot.rules.contains{$0.id=="technical:concise_lead" && $0.suppressed})
            let deleted=try XCTUnwrap(try proof(directory,"apply")["deletedRecord"] as? String)
            XCTAssertFalse(model.history.snapshot.records.contains{$0.id.uuidString.lowercased()==deleted})
            await model.history.waitForQuiescence();let records=Set(model.history.snapshot.records.map(\.id))
            let reset=model.learning.reset();XCTAssertNil(model.snapshot.card);XCTAssertTrue(model.running);try await reset.value
            XCTAssertTrue(model.learning.retainedEpisodes.isEmpty);XCTAssertTrue(model.learning.snapshot.rules.isEmpty)
            XCTAssertEqual(Set(model.history.snapshot.records.map(\.id)),records)
            let resetReceipt=try await controls.read();XCTAssertTrue(resetReceipt.enabled);XCTAssertNotEqual(resetReceipt.revision,boot.revision)
            try model.perform(.requestHelp);try await until{model.snapshot.card != nil}
            XCTAssertEqual(model.snapshot.card?.lead,baselineLearningLead);XCTAssertNotNil(model.snapshot.learningMemoryRevision)
            let disabled=model.learning.disable();XCTAssertNil(model.snapshot.card);XCTAssertTrue(model.running);try await disabled.value
            let off=try await controls.read();XCTAssertFalse(off.enabled);XCTAssertNil(off.pending)
            try phaseProof(directory,"undone",["retained":0])
            try await finishAcceptanceModel(model)
            try await nextPhase("off",directory:directory,domain:domain)
        }else{
            XCTAssertFalse(boot.enabled);XCTAssertEqual(model.learning.snapshot.phase,.off)
            XCTAssertTrue(model.learning.retainedEpisodes.isEmpty);XCTAssertTrue(model.learning.snapshot.rules.isEmpty)
            XCTAssertEqual(model.snapshot.card?.lead,baselineLearningLead);XCTAssertNil(model.snapshot.learningMemoryRevision)
            XCTAssertGreaterThanOrEqual(model.history.snapshot.records.count,6,"Reset/disable must preserve the original saved meetings")
            try phaseProof(directory,"off",["enabled":false])
            try await finishAcceptanceModel(model)
        }
    }
}
