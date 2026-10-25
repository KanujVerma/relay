import XCTest
import RelayNativeSession
import RelaySessionPanel
import RelayContextComposition
import RelayProfile
@testable import RelayPanelSession

@MainActor private final class LiveMessagePreferences:SessionContextUsePreferences {var useInSessions=false}

@MainActor final class LiveEmptyAnswerPresentationTests:XCTestCase {
    private func message(_ snapshot:SessionPanelSnapshot,running:Bool=false)->RelayEmptyAnswerPresentation {
        RelayEmptyAnswerPresentation(state:RelaySessionPresentation(running:running,assistantActive:!running),
            status:snapshot.status,hasQuestion:snapshot.question != nil)
    }
    private func decision(_ binding:PanelRequestBinding,disposition:String,reason:String)->Data {
        try! JSONSerialization.data(withJSONObject:[
            "schemaVersion":1,"captureSessionID":binding.lease.captureSessionID.uuidString,
            "sessionEpoch":binding.lease.sessionEpoch,"presentationGeneration":binding.lease.presentationGeneration,
            "requestID":binding.requestID.uuidString,"eventSequence":binding.eventSequence,
            "resultRevision":disposition == "pending" ? 1:2,"disposition":disposition,"reasonCode":reason,
            "pythonToken":["turnID":"assistant:1","version":1,"generation":1],
            "displayID":"current-question","question":"Explain inner and left joins.",
            "answerID":NSNull(),"answerKind":NSNull(),"card":NSNull(),"provenance":NSNull()
        ] as [String:Any])
    }
    func testRealTerminalDecisionsReplaceThinkingWhileKeepingTheQuestion()async throws {
        for running in [false,true] {
            for (disposition,reason,title) in [
                ("error","inference_disabled","Answer unavailable"),
                ("abstain","inference_disabled","AI requests are off"),
                ("abstain","no_reference_match","No reliable answer available"),
                ("clarify","task_context_unresolved","Clarify the updated task constraint"),
                ("clarify","task_context_overflow","Summarize the current problem and requirements"),
                ("clarify","personal_context_missing","Add confirmed background to answer this question")
            ] {
                let authority=SessionPresentationAuthority(),lease=try authority.start()
                let panel=SessionPanelController(authority:authority)
                let binding=PanelRequestBinding(lease:lease,requestID:UUID(),eventSequence:1)
                panel.bind(binding)
                XCTAssertTrue(try panel.accept(decision(binding,disposition:"pending",reason:"generation_started")))
                XCTAssertEqual(message(panel.snapshot,running:running).title,"Thinking it through…")
                XCTAssertTrue(try panel.accept(decision(binding,disposition:disposition,reason:reason)))
                XCTAssertNotNil(panel.snapshot.question);XCTAssertNil(panel.snapshot.card)
                XCTAssertEqual(message(panel.snapshot,running:running).title,title)
                XCTAssertFalse(try panel.accept(decision(binding,disposition:"pending",reason:"generation_started")))
                XCTAssertEqual(message(panel.snapshot,running:running).title,title)
            }
        }
    }
    func testRealTimeoutAndClearedStopOrWithheldStatusesNeverShowThinking()async throws {
        let authority=SessionPresentationAuthority(),lease=try authority.start()
        let panel=SessionPanelController(authority:authority)
        let binding=PanelRequestBinding(lease:lease,requestID:UUID(),eventSequence:1)
        panel.bind(binding)
        XCTAssertEqual(message(panel.snapshot).title,"Thinking it through…")
        XCTAssertTrue(try panel.accept(decision(binding,disposition:"pending",reason:"generation_started")))
        panel.expire(requestID:binding.requestID)
        XCTAssertEqual(message(panel.snapshot).title,"Answer timed out")
        for status in ["Response stopped","Answer withheld because context changed"] {
            panel.clear(status:status)
            XCTAssertNil(panel.snapshot.question)
            XCTAssertEqual(message(panel.snapshot).title,status)
        }
    }
    func testIdleListeningPauseAndClosingMessagesKeepTheirOwnPriority()async {
        func make(_ state:RelaySessionPresentation,_ status:String="Listening",_ question:Bool=false)->RelayEmptyAnswerPresentation {
            RelayEmptyAnswerPresentation(state:state,status:status,hasQuestion:question)
        }
        XCTAssertEqual(make(.init()).title,"Ask Relay a question.")
        XCTAssertEqual(make(.init(assistantActive:true),"Ready · not listening").title,"Ask Relay a question.")
        XCTAssertEqual(make(.init(running:true)).title,"Listening for the next question.")
        XCTAssertEqual(make(.init(paused:true),"Answer unavailable",true).title,"Take your time.")
        XCTAssertEqual(make(.init(stopping:true),"Answer unavailable",true).title,"Finishing the session…")
        XCTAssertEqual(make(.init(assistantClosing:true),"Answer unavailable",true).title,"Finishing the session…")
        XCTAssertEqual(make(.init(running:true)).detail,"Talking points appear automatically as the conversation develops.")
        XCTAssertEqual(make(.init(assistantActive:true)).detail,"Audio recording is off. Type a question or follow-up above.")
    }
    func testActualIdleNoInferenceTerminalUsesTheSameLargeMessageAsThePanel()async throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let python=try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])
        var audioEvents=0
        let model=SessionApplicationModel(arguments:["Relay","--repository",root.path,"--python",python,"--role","developer"],
            ingressEnqueued:{_ in audioEvents+=1},contextPreferences:LiveMessagePreferences())
        model.assistant.draft="Explain the JavaScript event loop and its microtask queue."
        model.assistant.submitDraft()
        do {
            for _ in 0..<2500 {
                if model.assistantActive && !model.assistant.snapshot.isPreparing && model.snapshot.question != nil && model.snapshot.status != "Thinking" {break}
                try await Task.sleep(for:.milliseconds(2))
            }
            XCTAssertTrue(model.assistantActive);XCTAssertFalse(model.running)
            XCTAssertFalse(model.authorizedConversation);XCTAssertEqual(audioEvents,0)
            XCTAssertNil(model.error);XCTAssertNil(model.snapshot.card)
            XCTAssertEqual(model.snapshot.status,"AI requests are off")
            XCTAssertEqual(message(model.snapshot).title,"AI requests are off")
            await model.stop()
        }catch{await model.stop();throw error}
    }
}
