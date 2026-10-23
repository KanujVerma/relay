import Foundation
import XCTest
import RelayContextComposition
@testable import RelaySessionPanel
import RelayNativeSession

extension SessionPanelTests {
    @MainActor func test_manual_binding_uses_fresh_native_request_without_observing_fake_audio() throws {
        let authority=SessionPresentationAuthority();try authority.start()
        let panel=SessionPanelController(authority:authority);let original=try event(authority)
        panel.observe(original);XCTAssertTrue(try panel.accept(result(original)))
        let lease=try XCTUnwrap(authority.invalidate());let manual=PanelRequestBinding(lease:lease,requestID:UUID(),eventSequence:original.eventSequence)
        panel.bind(manual)
        var value=try JSONSerialization.jsonObject(with:result(original)) as! [String:Any]
        value["presentationGeneration"]=lease.presentationGeneration;value["requestID"]=manual.requestID.uuidString.lowercased()
        XCTAssertTrue(try panel.accept(JSONSerialization.data(withJSONObject:value)))
        XCTAssertFalse(try panel.accept(result(original)))
        XCTAssertEqual(panel.snapshot.card?.lead,"Use FIFO ordering.")
    }
    func test_context_use_is_strict_host_provenance_and_not_model_authority() throws {
        let authority=SessionPresentationAuthority();try authority.start();let e=try event(authority)
        var value=try JSONSerialization.jsonObject(with:result(e)) as! [String:Any]
        var provenance=value["provenance"] as! [String:Any]
        provenance["taskContext"]=["provenance":"selected_accessibility_text","source":"Selected text: com.example.editor","capturedUptimeNanoseconds":123]
        value["provenance"]=provenance
        let parsed=try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value))
        XCTAssertEqual(parsed.taskContext?.provenance,"selected_accessibility_text")
        provenance["taskContext"]=["provenance":"verified_resume","source":"invented","capturedUptimeNanoseconds":123]
        value["provenance"]=provenance
        XCTAssertThrowsError(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value)))
    }
}
