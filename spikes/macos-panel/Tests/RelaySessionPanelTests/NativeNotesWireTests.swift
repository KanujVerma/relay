import Foundation
import XCTest
@testable import RelaySessionPanel

final class NativeNotesWireTests:XCTestCase{
    private typealias F=HistoryNotesFixtures
    private func scope(_ action:String="open",status:String="ready",quiesced:Any=NSNull(),reason:String="ok")->[String:Any]{
        ["schemaVersion":1,"kind":"notes_scope_response","scopeID":F.capture,"scopeEpoch":1,"operationID":F.note,"action":action,"status":status,"quiesced":quiesced,"reasonCode":reason]
    }
    private func result(_ status:String="pending",notes:Any=NSNull(),reason:String="generating")->[String:Any]{
        ["schemaVersion":1,"kind":"notes_result","scopeID":F.capture,"scopeEpoch":1,"requestID":F.note,"requestSequence":1,"transferID":F.capture,
         "recordID":F.record,"recordRevision":"7","sourceDigest":"","resultRevision":status=="pending" ? 1:2,"status":status,"reasonCode":reason,"notes":notes]
    }
    func testScopeResponseHasExactStatusNullAndIdentityDomains()throws{
        let good=scope();let response=try NativeNotesWire.scopeResponse(F.encode(good))
        XCTAssertEqual(response.scopeID,UUID(uuidString:F.capture));XCTAssertEqual(response.scopeEpoch,1);XCTAssertEqual(response.status,"ready")
        for key in good.keys{var bad=good;bad.removeValue(forKey:key);XCTAssertThrowsError(try NativeNotesWire.scopeResponse(F.encode(bad)))}
        for bad in [scope(quiesced:true),scope(reason:"busy"),scope("close",status:"closed",quiesced:1),scope(status:"unavailable",quiesced:false,reason:"private diagnostic")]{
            XCTAssertThrowsError(try NativeNotesWire.scopeResponse(F.encode(bad)))
        }
        XCTAssertNoThrow(try NativeNotesWire.scopeResponse(F.encode(scope("close",status:"closed",quiesced:true))))
        XCTAssertNoThrow(try NativeNotesWire.scopeResponse(F.encode(scope(status:"unavailable",quiesced:false,reason:"busy"))))
    }
    func testScopeRejectsCallerAuthorityUnknownFieldsUppercaseAndBoolCounters()throws{
        for value in [true,"1",0] as [Any] {var bad=scope();bad["scopeEpoch"]=value;XCTAssertThrowsError(try NativeNotesWire.scopeResponse(F.encode(bad)))}
        var bad=scope();bad["scopeID"]=F.capture.uppercased();XCTAssertThrowsError(try NativeNotesWire.scopeResponse(F.encode(bad)))
        bad=scope();bad["authorized"]=true;XCTAssertThrowsError(try NativeNotesWire.scopeResponse(F.encode(bad)))
    }
    func testCompletedResultValidatesLiteralCitationsAgainstOriginalData()throws{
        let source=try HistoryNotesData.source(F.encode(F.source()));var good=result("completed",notes:F.output(),reason:"ok");good["sourceDigest"]=source.sourceDigest
        let parsed=try NativeNotesWire.result(F.encode(good),source:source)
        XCTAssertEqual(parsed.status,"completed");XCTAssertEqual(parsed.requestSequence,1)
        XCTAssertEqual(parsed.notes?.summary[0].citations[0].quote,"original quote")
        var bad=good;bad["sourceDigest"]=String(repeating:"0",count:64);XCTAssertThrowsError(try NativeNotesWire.result(F.encode(bad),source:source))
        bad=good;bad["notes"]=F.output(quote:"invented source quotation");XCTAssertThrowsError(try NativeNotesWire.result(F.encode(bad),source:source))
        bad=good;bad["recordRevision"]="8";XCTAssertThrowsError(try NativeNotesWire.result(F.encode(bad),source:source))
    }
    func testPendingCancelledUnavailableResultsNeverCarryNotesOrCompetingRevisions()throws{
        let source=try HistoryNotesData.source(F.encode(F.source()))
        for status in ["pending","cancelled","unavailable"]{
            var good=result(status,reason:status=="pending" ? "generating":status=="cancelled" ? "cancelled":"source_unavailable");good["sourceDigest"]=source.sourceDigest
            XCTAssertNoThrow(try NativeNotesWire.result(F.encode(good),source:source))
            var bad=good;bad["notes"]=F.output();XCTAssertThrowsError(try NativeNotesWire.result(F.encode(bad),source:source))
            bad=good;bad["resultRevision"]=status=="pending" ? 2:1;XCTAssertThrowsError(try NativeNotesWire.result(F.encode(bad),source:source))
        }
    }
    func testResultFieldSetAndFrameCapStayStrict()throws{
        let source=try HistoryNotesData.source(F.encode(F.source()));var good=result();good["sourceDigest"]=source.sourceDigest
        for key in good.keys{var bad=good;bad.removeValue(forKey:key);XCTAssertThrowsError(try NativeNotesWire.result(F.encode(bad),source:source))}
        var bad=good;bad["modelID"]="model cannot claim configuration";XCTAssertThrowsError(try NativeNotesWire.result(F.encode(bad),source:source))
        XCTAssertThrowsError(try NativeNotesWire.result(Data(repeating:32,count:16385),source:source))
        let raw=String(decoding:try F.encode(good),as:UTF8.self).replacingOccurrences(of:"\"schemaVersion\":1",with:"\"schemaVersion\":1,\"schemaVersion\":1")
        XCTAssertThrowsError(try NativeNotesWire.result(Data(raw.utf8),source:source))
    }
}
