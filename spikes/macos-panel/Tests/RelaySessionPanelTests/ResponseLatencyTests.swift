import XCTest
import Foundation
import RelayNativeSession
import RelayContextComposition
@testable import RelaySessionPanel

final class ResponseLatencyTests:XCTestCase {
    func timing(_ received:UInt64=4_100_000_000)->[String:Any]{[
        "schemaVersion":1,"helperReceivedUptimeNanoseconds":received,
        "generationStartedUptimeNanoseconds":4_200_000_000,
        "transportStartedUptimeNanoseconds":4_300_000_000,
        "firstTextUptimeNanoseconds":5_000_000_000,
        "responseCompletedUptimeNanoseconds":6_000_000_000,
        "validationFinishedUptimeNanoseconds":6_100_000_000,
        "helperEmittedUptimeNanoseconds":6_200_000_000,"transportOutcome":"completed"]}
    func withTiming(_ data:Data,_ value:Any)throws->Data{
        var o=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        o["timing"]=value;return try JSONSerialization.data(withJSONObject:o)
    }
    func eou(_ base:NativeSessionEvent)->NativeSessionEvent{
        NativeSessionEvent(captureSessionID:base.captureSessionID,sessionEpoch:base.sessionEpoch,
            eventSequence:base.eventSequence,presentationGeneration:base.presentationGeneration,kind:.eou,
            sourceCode:2,streamGeneration:1,emittedUptimeNanoseconds:4_000_000_000,payload:[
                "activityID":.uint(1),"event":.object([
                    "endHostTime":.uint(300),"finalizedUptimeNanoseconds":.uint(3_900_000_000),
                    "receivedUptimeNanoseconds":.uint(3_950_000_000),"timebase":.object([
                        "hostTicksAtAnchor":.uint(100),"uptimeNsAtAnchor":.uint(1_000_000_000),
                        "nsNumer":.uint(10_000_000),"nsDenom":.uint(1)])])],requestID:base.requestID)
    }
    @MainActor func test_actual_reducer_accepts_optional_timings_and_post_drain_observation_is_separate()throws{
        let fixture=SessionPanelTests(),authority=SessionPresentationAuthority();try authority.start()
        let event=eou(try fixture.event(authority)),panel=SessionPanelController(authority:authority)
        panel.observe(NativeSessionEvent(captureSessionID:event.captureSessionID,sessionEpoch:event.sessionEpoch,
            eventSequence:3,presentationGeneration:event.presentationGeneration,kind:.speechEnded,
            sourceCode:2,streamGeneration:1,emittedUptimeNanoseconds:3_800_000_000,
            payload:["activityID":.uint(1)]))
        panel.observe(event)
        let binding=try XCTUnwrap(PanelRequestBinding(event))
        panel.latency.recordForwarded(binding:binding,at:4_050_000_000)
        XCTAssertTrue(try panel.accept(withTiming(fixture.result(event),timing())))
        var row=try XCTUnwrap(panel.latency.samples.last)
        XCTAssertEqual(row.speechEndedAt,3_000_000_000)
        XCTAssertEqual(row.endpointEmittedAt,3_800_000_000)
        XCTAssertEqual(row.asrFinalizedAt,3_900_000_000)
        XCTAssertEqual(row.nativeEOUEmittedAt,4_000_000_000)
        XCTAssertEqual(row.helperForwardedAt,4_050_000_000)
        XCTAssertEqual(row.helper?.firstTextAt,5_000_000_000)
        XCTAssertNil(row.modelAvailableAt);XCTAssertNil(row.windowVisibleAt)
        let available=DispatchTime.now().uptimeNanoseconds
        panel.latency.recordAvailable(binding:binding,replacement:panel.snapshot.replacement,availableAt:available,visible:false)
        row=try XCTUnwrap(panel.latency.samples.last)
        XCTAssertEqual(row.modelAvailableAt,available);XCTAssertNil(row.windowVisibleAt)
        panel.latency.recordAvailable(binding:binding,replacement:panel.snapshot.replacement,availableAt:available+1,visible:true)
        row=try XCTUnwrap(panel.latency.samples.last)
        XCTAssertEqual(row.modelAvailableAt,available);XCTAssertEqual(row.windowVisibleAt,available+1)
    }
    @MainActor func test_invalid_optional_timing_cannot_reject_or_authorize_an_answer()throws{
        let fixture=SessionPanelTests(),authority=SessionPresentationAuthority();try authority.start()
        let event=try fixture.event(authority),panel=SessionPanelController(authority:authority)
        var bad=timing();bad["helperReceivedUptimeNanoseconds"]=UInt64.max
        let data=try withTiming(fixture.result(event),bad)
        XCTAssertNil(try SessionAnswerDecision(data:data).timing)
        panel.observe(event);XCTAssertTrue(try panel.accept(data));XCTAssertNotNil(panel.snapshot.card)
        authority.invalidate()
        let stale=SessionPanelController(authority:authority)
        XCTAssertFalse(try stale.accept(withTiming(fixture.result(event),timing())))
        XCTAssertTrue(stale.latency.samples.isEmpty)
    }
    @MainActor func test_reentrant_withholding_never_acquires_availability_from_earlier_commit()throws{
        let fixture=SessionPanelTests(),authority=SessionPresentationAuthority();try authority.start()
        let event=try fixture.event(authority),panel=SessionPanelController(authority:authority)
        let binding=try XCTUnwrap(PanelRequestBinding(event));panel.observe(event)
        panel.onChange={if panel.snapshot.card != nil{panel.withholdGuideAnswer(for:binding,status:"Changed")}}
        XCTAssertTrue(try panel.accept(withTiming(fixture.result(event),timing())))
        XCTAssertNil(panel.snapshot.card)
        panel.latency.recordAvailable(binding:binding,replacement:panel.snapshot.replacement,
            availableAt:DispatchTime.now().uptimeNanoseconds,visible:true)
        let row=try XCTUnwrap(panel.latency.samples.last)
        XCTAssertEqual(row.outcome,"withheld");XCTAssertNil(row.modelAvailableAt);XCTAssertNil(row.windowVisibleAt)
    }
    @MainActor func test_new_binding_rejects_late_available_observation_and_ring_is_bounded()throws{
        let fixture=SessionPanelTests(),authority=SessionPresentationAuthority();try authority.start()
        let old=try fixture.event(authority),panel=SessionPanelController(authority:authority)
        panel.observe(old);XCTAssertTrue(try panel.accept(fixture.result(old)))
        let oldReplacement=panel.snapshot.replacement
        for seq in 1...40{
            authority.invalidate();panel.observe(try fixture.event(authority,sequence:UInt64(seq+4)))
        }
        panel.latency.recordAvailable(binding:try XCTUnwrap(PanelRequestBinding(old)),replacement:oldReplacement,
            availableAt:DispatchTime.now().uptimeNanoseconds,visible:true)
        XCTAssertEqual(panel.latency.samples.count,32)
        XCTAssertFalse(panel.latency.samples.contains{$0.modelAvailableAt != nil})
        XCTAssertFalse(panel.latency.samples.contains{$0.requestID==old.requestID})
    }
    @MainActor func test_failure_and_timeout_rows_remain_distinct_from_available_answers()throws{
        let fixture=SessionPanelTests(),authority=SessionPresentationAuthority();try authority.start()
        let event=try fixture.event(authority),panel=SessionPanelController(authority:authority)
        panel.observe(event);XCTAssertTrue(try panel.accept(fixture.result(event,disposition:"error")))
        XCTAssertEqual(panel.latency.samples.last?.outcome,"error")
        authority.invalidate();let fresh=try fixture.event(authority,sequence:8);panel.observe(fresh)
        panel.expire(requestID:fresh.requestID!)
        XCTAssertEqual(panel.latency.samples.last?.outcome,"timeout")
        XCTAssertFalse(panel.latency.samples.contains{$0.modelAvailableAt != nil})
    }
    @MainActor func test_pending_even_with_complete_transport_telemetry_never_counts_as_available()throws{
        let fixture=SessionPanelTests(),authority=SessionPresentationAuthority();try authority.start()
        let event=try fixture.event(authority),panel=SessionPanelController(authority:authority)
        let binding=try XCTUnwrap(PanelRequestBinding(event));panel.observe(event)
        XCTAssertTrue(try panel.accept(withTiming(fixture.result(event,disposition:"pending",revision:1),timing())))
        panel.latency.recordAvailable(binding:binding,replacement:panel.snapshot.replacement,
            availableAt:DispatchTime.now().uptimeNanoseconds,visible:true)
        XCTAssertNil(panel.snapshot.card)
        XCTAssertEqual(panel.latency.samples.last?.outcome,"pending")
        XCTAssertNil(panel.latency.samples.last?.modelAvailableAt)
    }
}
