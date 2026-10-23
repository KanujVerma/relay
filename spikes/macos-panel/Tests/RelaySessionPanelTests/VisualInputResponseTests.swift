import Foundation
import XCTest
@testable import RelaySessionPanel

final class VisualInputResponseTests:XCTestCase {
    private let id=UUID()
    private func frame(_ changes:[String:Any]=[:])throws->Data {
        var value:[String:Any] = ["schemaVersion":1,"kind":"visual_input_response","requestID":id.uuidString.lowercased(),"action":"verify","resultRevision":2,"status":"verified","reasonCode":"probe_verified","model":"gpt-fixture"]
        value.merge(changes){_,new in new};return try JSONSerialization.data(withJSONObject:value)
    }
    func testStrictVisualResponsesPreserveIdentityActionAndActualModel()throws {
        let reply=try VisualInputResponse(data:frame())
        XCTAssertEqual(reply.requestID,id);XCTAssertEqual(reply.action,.verify)
        XCTAssertEqual(reply.status,.verified);XCTAssertEqual(reply.model,"gpt-fixture")
        XCTAssertTrue(reply.isTerminal)
        let progress=try VisualInputResponse(data:frame(["resultRevision":1,"status":"checking","reasonCode":"checking"]))
        XCTAssertFalse(progress.isTerminal)
        let disabled=try VisualInputResponse(data:frame(["action":"disable","status":"disabled","reasonCode":"user_disabled","model":NSNull()]))
        XCTAssertNil(disabled.model)
    }
    func testUnknownFieldsTypesAndContradictoryRevisionsCannotGrantVisualUse()throws {
        for changes:[String:Any] in [["extra":true],["schemaVersion":true],["resultRevision":true],["resultRevision":3],
            ["status":"checking"],["action":"status","resultRevision":1,"status":"checking","reasonCode":"checking"],
            ["status":"verified","model":NSNull()],["reasonCode":"raw_provider_error"],["model":"token\nsecret"],
            ["action":"disable","status":"verified","reasonCode":"probe_verified"],["imageEnabled":true]] {
            XCTAssertThrowsError(try VisualInputResponse(data:frame(changes)))
        }
        let duplicate=String(data:try frame(),encoding:.utf8)!.replacingOccurrences(of:"\"schemaVersion\":1",with:"\"schemaVersion\":1,\"schemaVersion\":1")
        XCTAssertThrowsError(try VisualInputResponse(data:Data(duplicate.utf8)))
    }
}
