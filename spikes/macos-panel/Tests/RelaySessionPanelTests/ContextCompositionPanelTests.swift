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

extension SessionPanelTests {
    func test_image_use_requires_strict_optional_canonical_digest_on_OCR_only() throws {
        let authority=SessionPresentationAuthority();try authority.start();let e=try event(authority)
        var value=try JSONSerialization.jsonObject(with:result(e)) as! [String:Any]
        var provenance=value["provenance"] as! [String:Any]
        let base:[String:Any] = ["provenance":"local_ocr","source":"Synthetic diagram","capturedUptimeNanoseconds":123]
        var context=base;context["imageDigest"]=String(repeating:"a",count:64)
        provenance["taskContext"]=context;value["provenance"]=provenance
        XCTAssertEqual(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value)).taskContext?.imageDigest,String(repeating:"a",count:64))
        for malformed:Any in [String(repeating:"A",count:64),String(repeating:"a",count:63),NSNull(),true,42] {
            context=base;context["imageDigest"]=malformed
            provenance["taskContext"]=context;value["provenance"]=provenance
            XCTAssertThrowsError(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value)))
        }
        context=base;context["provenance"]="selected_accessibility_text";context["imageDigest"]=String(repeating:"a",count:64)
        provenance["taskContext"]=context;value["provenance"]=provenance
        XCTAssertThrowsError(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value)))
        provenance["taskContext"]=base;value["provenance"]=provenance
        XCTAssertNil(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value)).taskContext?.imageDigest)
    }
}
