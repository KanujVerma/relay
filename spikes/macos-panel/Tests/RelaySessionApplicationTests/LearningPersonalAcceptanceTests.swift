import Foundation
import Combine
import XCTest
import RelayAudioBuffer
import RelayProfile
import RelaySessionPanel
@testable import RelayPanelSession

extension LearningApplicationTests {
    private func emittedPersonal(_ model:SessionApplicationModel,_ directory:URL)throws->[String:Any]{
        let request=try XCTUnwrap(model.responseLatencySamples.last?.requestID).uuidString.lowercased()
        let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.hasPrefix("calls") && $0.pathExtension=="jsonl"}
        for file in files{
            for line in try String(contentsOf:file,encoding:.utf8).split(separator:"\n"){
                let row=try JSONSerialization.jsonObject(with:Data(line.utf8)) as? [String:Any]
                if row?["kind"] as? String=="synthetic_personal_emitted",row?["requestID"] as? String==request{return row!}
            }
        }
        throw HistoryError.missing
    }
    private func personalFacts(_ row:[String:Any])throws->Data{
        try JSONSerialization.data(withJSONObject:XCTUnwrap(row["facts"]),options:[.sortedKeys])
    }
    func testActualConfirmedPersonalLearningPreservesFactUnitsAndProvenanceWithoutModelCalls()async throws{
        let method="testActualConfirmedPersonalLearningPreservesFactUnitsAndProvenanceWithoutModelCalls"
        if try await LearningGUIWitness.run(caseClass:Self.self,method:method){return}
        let question="Describe your Fictional Northstar project."
        let(model,conversation,directory,_)=try rig(question:"How should a recruiter introduction be structured?",
            profileReceipt:AppLearningProfileReceipt(hold:false),
            microphoneReply:"Explain opening structure clearly. I earned a certificate.",
            remoteContinuation:"How should a recruiter transition be organized?",
            responsePreferencesStorage:ApplicationPreferenceStorage(),responsePreferencesReceipts:ApplicationPreferenceReceipts(),tracePersonal:true)
        model.openMyContext();await model.contextUse.waitForQuiescence();XCTAssertTrue(model.profile.opened)
        for (text,actor,key) in [
            ("I implemented validation tests for Fictional Northstar as a prototype.","self","fictional.northstar.self"),
            ("Our team built deployment checks for Fictional Northstar during a mock exercise.","team","fictional.northstar.team")]{
            await model.profile.stageEnteredText(text,purpose:"project",label:"Fictional project",role:model.role,project:"Fictional Northstar")
            let card=try XCTUnwrap(model.profile.card);XCTAssertEqual(card.snippet,text)
            await model.profile.review(card,actor:actor,claimKey:key,replaces:nil)
            XCTAssertNil(model.profile.errorStatus)
        }
        XCTAssertEqual(model.profile.memoryCount,2)
        let approved=Set(model.profile.memories.map(\.factID));_ = window(model)
        try await model.history.enableSaving()
        var edits=0
        let draftProbe=model.assistant.$draft.dropFirst().sink{value in
            edits+=1
            print("PERSONAL_DRAFT event=\(edits) matchesExpected=\(value==question) empty=\(value.isEmpty) preparing=\(model.assistant.snapshot.isPreparing)")
        }
        defer{draftProbe.cancel()}
        model.assistant.draft=question
        print("PERSONAL_PREP canSend=\(model.assistant.snapshot.canSendAsNew) profileOpened=\(model.profile.opened) profileBusy=\(model.profile.busy) contextBusy=\(model.contextUse.isBusy)")
        XCTAssertTrue(model.assistant.snapshot.canSendAsNew)
        model.assistant.sendDraftAsNewQuestion()
        do{try await until{model.snapshot.card != nil}}
        catch{
            let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.hasPrefix("calls") && $0.pathExtension=="jsonl"}
            for file in files{print("PERSONAL_PROTOCOL "+(try String(contentsOf:file,encoding:.utf8)))}
            throw error
        }
        let baseline=try XCTUnwrap(model.snapshot.card),originalProof=try emittedPersonal(model,directory)
        XCTAssertEqual(baseline.points.count,2);XCTAssertNil(model.snapshot.learningMemoryRevision)
        XCTAssertTrue(baseline.points.contains{$0.hasPrefix("Your contribution:") && $0.contains("as a prototype")})
        XCTAssertTrue(baseline.points.contains{$0.hasPrefix("Team contribution:") && $0.contains("during a mock exercise")})
        XCTAssertEqual(originalProof["modelRequests"] as? Int,0)
        let originalFacts=try personalFacts(originalProof)
        let ids=(originalProof["facts"] as? [[String:Any]])?.compactMap{$0["factID"] as? String} ?? []
        XCTAssertEqual(Set(ids),approved)
        await model.stop();try await model.learning.enable()
        for _ in 0..<4{
            await model.start();try await conversation.speak(.remoteAudio,through:model)
            try await until{model.snapshot.card != nil && model.responseLatencySamples.last?.windowVisibleAt != nil}
            try await conversation.speak(.microphone,through:model)
            try await until{model.assistant.transcript.snapshot.rows.contains{$0.source == .microphone}}
            try await conversation.speak(.remoteAudio,through:model);try await until{!model.learning.session.episodes.isEmpty}
            XCTAssertTrue(model.learning.session.episodes.first?.signal.eligibleForStyle==true)
            await model.stop()
        }
        XCTAssertEqual(model.learning.retainedEpisodes.count,4)
        XCTAssertTrue(model.learning.snapshot.rules.contains{$0.id=="recruiter:concise_lead" && !$0.suppressed})
        await model.start();model.assistant.draft=question;model.assistant.sendDraftAsNewQuestion()
        try await until{model.snapshot.card != nil && model.snapshot.learningMemoryRevision != nil}
        func assertApprovedUnits(_ adapted:Bool) throws{
            let card=try XCTUnwrap(model.snapshot.card),proof=try emittedPersonal(model,directory)
            if adapted{XCTAssertEqual(card.lead,baseline.points[0]);XCTAssertEqual(card.points,Array(baseline.points.dropFirst()))}
            else{XCTAssertEqual(card,baseline)}
            XCTAssertEqual(try personalFacts(proof),originalFacts);XCTAssertEqual(proof["modelRequests"] as? Int,0)
            XCTAssertEqual(Set(model.profile.memories.map(\.factID)),approved);XCTAssertEqual(model.profile.memoryCount,2)
            XCTAssertFalse(([card.lead]+card.points).joined(separator:" ").contains("certificate"),"Unconfirmed microphone wording never becomes personal evidence")
            if let revision=model.snapshot.learningMemoryRevision{XCTAssertEqual(proof["learningRevision"] as? String,revision.uuidString.lowercased())}
            else{XCTAssertTrue(proof["learningRevision"] is NSNull)}
        }
        try assertApprovedUnits(true)
        var before=model.snapshot.replacement
        model.assistant.draft=question+" In detail.";model.assistant.sendDraftAsNewQuestion()
        try await until{model.snapshot.replacement>before && model.snapshot.card != nil && model.snapshot.learningMemoryRevision==nil};try assertApprovedUnits(false)
        try await model.responsePreferences.useBuiltin(.coding)
        before=model.snapshot.replacement
        model.assistant.draft=question;model.assistant.sendDraftAsNewQuestion()
        try await until{model.snapshot.replacement>before && model.snapshot.card != nil && model.snapshot.learningMemoryRevision==nil};try assertApprovedUnits(false)
        before=model.snapshot.replacement
        model.responsePreferences.useGeneral();model.assistant.draft=question;model.assistant.sendDraftAsNewQuestion()
        try await until{model.snapshot.replacement>before && model.snapshot.card != nil && model.snapshot.learningMemoryRevision != nil};try assertApprovedUnits(true)
        let projection=try XCTUnwrap(model.learning.capture(question:question)),used=try XCTUnwrap(projection.payload.sourceRecordIDs.first)
        await model.history.waitForQuiescence();let record=try XCTUnwrap(model.history.snapshot.records.first{$0.id==used})
        let deletion=model.history.delete(record.id,expectedRevision:record.revision)
        XCTAssertNil(model.snapshot.card);XCTAssertTrue(model.running)
        try await deletion.value;try await model.learning.restore()
        XCTAssertEqual(model.learning.retainedEpisodes.count,3)
        model.assistant.requestCurrentQuestionHelp();try await until{model.snapshot.card != nil && model.snapshot.learningMemoryRevision != nil}
        try assertApprovedUnits(true)
        let undo=model.learning.undo("recruiter:concise_lead");XCTAssertNil(model.snapshot.card);XCTAssertTrue(model.running);try await undo.value
        model.assistant.requestCurrentQuestionHelp();try await until{model.snapshot.card != nil && model.snapshot.learningMemoryRevision==nil}
        try assertApprovedUnits(false)
    }
}
