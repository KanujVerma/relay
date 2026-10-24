import Foundation
import XCTest
import RelayNativeSession
@testable import RelaySessionPanel

@MainActor final class LearningWireTests:XCTestCase {
    private func frame()throws->[String:Any]{
        let fixture=SessionPanelTests(),authority=SessionPresentationAuthority();try authority.start()
        let event=try fixture.event(authority)
        return try XCTUnwrap(JSONSerialization.jsonObject(with:fixture.result(event)) as? [String:Any])
    }
    func testActualGeneralAndConfirmedPersonalFramesAcceptOneSeparateLearningRevision()async throws{
        let revision=UUID().uuidString.lowercased();var general=try frame()
        var provenance=try XCTUnwrap(general["provenance"] as? [String:Any]);provenance["learningMemoryRevision"]=revision;general["provenance"]=provenance
        XCTAssertNoThrow(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:general)))
        general["provenance"]=["personal":true,"contextRevision":"synthetic-approved-revision","facts":[["factID":"f","sourceID":"s","actor":"self","revision":1]],"checks":["host_exact_approved_facts"],"learningMemoryRevision":revision] as [String:Any]
        XCTAssertNoThrow(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:general)))
    }
    func testMalformedLearningUseAndLocalReferenceClaimsRemainRejected()async throws{
        for invalid in [NSNull(),true,1,"bad"] as [Any]{
            var value=try frame(),provenance=try XCTUnwrap(value["provenance"] as? [String:Any])
            provenance["learningMemoryRevision"]=invalid;value["provenance"]=provenance
            XCTAssertThrowsError(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:value)))
        }
        var reference=try frame();reference["answerKind"]="reviewed_reference"
        reference["provenance"]=["referenceID":"synthetic-reference","sourceRef":"public-fixture","learningMemoryRevision":UUID().uuidString.lowercased()]
        XCTAssertThrowsError(try SessionAnswerDecision(data:JSONSerialization.data(withJSONObject:reference)))
    }
}
