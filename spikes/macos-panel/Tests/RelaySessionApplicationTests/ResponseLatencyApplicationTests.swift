import Combine
import Foundation
import XCTest
import RelayProfile
import RelaySessionPanel
import RelayNativeSession
import RelayContextComposition
@testable import RelayPanelSession

@MainActor private final class LatencyContextPreferences:SessionContextUsePreferences{var useInSessions=false}

/// Actual Model, native fixture, source helper and reducer. No account, model
/// download, hardware capture or displayed window. Fixtures prove timestamp
/// joins and negative controls, never production inference speed or paint.
@MainActor final class ResponseLatencyApplicationTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func model(ingress:(@MainActor (SessionIngress)->Void)?=nil)throws->SessionApplicationModel{
        let value=SessionApplicationModel(arguments:["Relay","--fixture-suite","coding","--repository",root.path,
            "--python",try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"]),"--role","analytics"],
            ingressEnqueued:ingress,contextPreferences:LatencyContextPreferences(),
            responsePreferencesStorage:ApplicationPreferenceStorage(),responsePreferencesReceipts:ApplicationPreferenceReceipts())
        addTeardownBlock{await value.shutdown()};return value
    }
    private func until(_ predicate:()->Bool)async throws{
        for _ in 0..<2500{if predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NSError(domain:"actual response timing boundary not reached",code:1)
    }
    func testIdleReviewedResponseHasActualHelperAndPostDrainModelTimesWithoutFakeAudioOrProviderMarks()async throws{
        var audio=0;let model=try model(ingress:{if case .audio=$0{audio+=1}})
        model.assistant.draft="What is the difference between WHERE and HAVING?";model.assistant.submitDraft()
        try await until{model.responseLatencySamples.last?.modelAvailableAt != nil}
        let row=try XCTUnwrap(model.responseLatencySamples.last),helper=try XCTUnwrap(row.helper)
        XCTAssertEqual(row.outcome,"answer");XCTAssertEqual(row.answerKind,"reviewed_reference")
        XCTAssertNotNil(model.snapshot.card);XCTAssertFalse(model.running);XCTAssertTrue(model.assistantActive)
        XCTAssertEqual(audio,0);XCTAssertTrue(model.assistant.transcript.snapshot.rows.isEmpty)
        XCTAssertNil(row.speechEndedAt);XCTAssertNil(row.nativeEOUEmittedAt)
        XCTAssertNil(helper.transportStartedAt);XCTAssertNil(helper.firstTextAt);XCTAssertNil(helper.responseCompletedAt)
        XCTAssertNotNil(row.helperForwardedAt);XCTAssertNotNil(row.helperFrameReceivedAt)
        XCTAssertLessThanOrEqual(helper.helperReceivedAt,helper.helperEmittedAt)
        XCTAssertLessThanOrEqual(try XCTUnwrap(row.panelCommittedAt),try XCTUnwrap(row.modelAvailableAt))
        XCTAssertNil(row.windowVisibleAt,"No attached visible window can count as readable presentation")
    }
    func testNativeFixtureJoinsOriginalSpeechEndpointASRAndHelperStagesBeforeModelAvailability()async throws{
        let model=try model();await model.start()
        try await until{model.responseLatencySamples.last?.modelAvailableAt != nil}
        let row=try XCTUnwrap(model.responseLatencySamples.last),helper=try XCTUnwrap(row.helper)
        let speech=try XCTUnwrap(row.speechEndedAt),endpoint=try XCTUnwrap(row.endpointEmittedAt)
        let asr=try XCTUnwrap(row.asrFinalizedAt),eou=try XCTUnwrap(row.nativeEOUEmittedAt)
        XCTAssertLessThanOrEqual(speech,endpoint);XCTAssertLessThanOrEqual(endpoint,asr)
        XCTAssertLessThanOrEqual(asr,try XCTUnwrap(row.nativeASRReceivedAt))
        XCTAssertLessThanOrEqual(try XCTUnwrap(row.nativeASRReceivedAt),eou)
        XCTAssertLessThanOrEqual(eou,helper.helperReceivedAt)
        XCTAssertLessThanOrEqual(helper.helperReceivedAt,try XCTUnwrap(helper.generationStartedAt))
        XCTAssertLessThanOrEqual(try XCTUnwrap(helper.generationStartedAt),try XCTUnwrap(helper.validationFinishedAt))
        XCTAssertLessThanOrEqual(helper.helperEmittedAt,try XCTUnwrap(row.helperFrameReceivedAt))
        XCTAssertLessThanOrEqual(try XCTUnwrap(row.panelCommittedAt),try XCTUnwrap(row.modelAvailableAt))
        XCTAssertNil(helper.firstTextAt);XCTAssertNil(helper.responseCompletedAt,"Injected fixture is not an OAuth model stream")
        XCTAssertTrue(model.running);XCTAssertEqual(model.assistant.transcript.snapshot.rows.count,1)
        XCTAssertNil(row.windowVisibleAt)
    }
    func testMissingPersonalContextRecordsWithholdWithoutProviderOrAvailableAnswer()async throws{
        let model=try model()
        model.assistant.draft="Tell me about yourself and the project you led.";model.assistant.submitDraft()
        try await until{model.responseLatencySamples.last?.outcome=="clarify"}
        let row=try XCTUnwrap(model.responseLatencySamples.last),helper=try XCTUnwrap(row.helper)
        XCTAssertNil(model.snapshot.card)
        XCTAssertNil(helper.generationStartedAt);XCTAssertNil(helper.firstTextAt);XCTAssertNil(helper.responseCompletedAt)
        XCTAssertNil(row.modelAvailableAt);XCTAssertNil(row.windowVisibleAt)
        XCTAssertFalse(model.running);XCTAssertTrue(model.assistant.transcript.snapshot.rows.isEmpty)
    }
    func testReentrantActualModelGuideWithholdingCannotCountOuterCardAsAvailable()async throws{
        let model=try model();try await model.responsePreferences.useBuiltin(.coding)
        let revision=try XCTUnwrap(model.responsePreferences.capture()).revision
        var retired=false
        let subscription=model.$snapshot.dropFirst().sink{incoming in
            guard !retired,incoming.card != nil,incoming.responsePreferencesRevision==revision else{return}
            retired=true;model.responsePreferences.useGeneral()
        }
        defer{subscription.cancel()}
        await model.start();try await until{retired};await Task.yield()
        XCTAssertNil(model.snapshot.card);XCTAssertNil(model.snapshot.responsePreferencesRevision)
        XCTAssertEqual(model.snapshot.status,"Response guide changed. Ask again.")
        XCTAssertTrue(model.responseLatencySamples.contains{$0.outcome=="withheld"})
        XCTAssertFalse(model.responseLatencySamples.contains{$0.modelAvailableAt != nil})
        XCTAssertFalse(model.responseLatencySamples.contains{$0.windowVisibleAt != nil})
    }
}
