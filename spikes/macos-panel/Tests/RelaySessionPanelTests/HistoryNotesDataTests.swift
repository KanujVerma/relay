import Foundation
import CryptoKit
import XCTest
@testable import RelaySessionPanel

final class HistoryNotesDataTests:XCTestCase {
    private typealias F=HistoryNotesFixtures
    func testSourcePreservesOriginalUTF8AndHashWithoutIssuingAuthority()throws{
        let raw=try F.encode(F.source()),value=try HistoryNotesData.source(raw)
        XCTAssertEqual(value.rawBytes,raw);XCTAssertEqual(value.rows[0].text,"  A stable original quote.\n")
        var domain=Data("relay.notes.source.v1\n".utf8);domain.append(raw)
        XCTAssertEqual(value.sourceDigest,SHA256.hash(data:domain).map{String(format:"%02x",$0)}.joined())
        XCTAssertEqual(value.selection.includedRows,1);XCTAssertEqual(value.recordRevision,7)
        XCTAssertEqual(value.rows[0].rowID,F.id());XCTAssertEqual(value.rows[0].revision,1)
    }
    func testExactFieldsCounterAndScalarTypes()throws{
        let original=F.source()
        for key in original.keys{var value=original;value.removeValue(forKey:key);XCTAssertThrowsError(try HistoryNotesData.source(F.encode(value)),key)}
        for extra in ["authorized","current","accountID","model"]{var value=original;value[extra]=true;XCTAssertThrowsError(try HistoryNotesData.source(F.encode(value)),extra)}
        for invalid in [true,"1"] as [Any]{var value=original;value["schemaVersion"]=invalid;XCTAssertThrowsError(try HistoryNotesData.source(F.encode(value)))}
        for invalid in ["0","01","+1","١",String(UInt64.max),true] as [Any]{var value=original;value["recordRevision"]=invalid;XCTAssertThrowsError(try HistoryNotesData.source(F.encode(value)))}
        var value=original;value["recordID"]=F.record.uppercased();XCTAssertThrowsError(try HistoryNotesData.source(F.encode(value)))
    }
    func testDuplicateNonfiniteDepthAndNodeBudgetsBeforeDataAdmission()throws{
        let raw=String(decoding:try F.encode(F.source()),as:UTF8.self)
        XCTAssertThrowsError(try HistoryNotesData.source(Data(raw.replacingOccurrences(of:"\"schemaVersion\":1",with:"\"schemaVersion\":1.0").utf8)))
        let duplicate=raw.replacingOccurrences(of:"\"schemaVersion\":1",with:"\"schemaVersion\":1,\"schemaVersion\":1")
        XCTAssertThrowsError(try HistoryNotesData.source(Data(duplicate.utf8)))
        XCTAssertThrowsError(try HistoryNotesData.source(Data(raw.replacingOccurrences(of:"\"schemaVersion\":1",with:"\"schemaVersion\":NaN").utf8)))
        XCTAssertThrowsError(try HistoryNotesData.source(Data((String(repeating:"[",count:9)+"0"+String(repeating:"]",count:9)).utf8)))
        XCTAssertThrowsError(try HistoryNotesData.source(Data(("["+Array(repeating:"0",count:8193).joined(separator:",")+"]").utf8)))
        XCTAssertThrowsError(try HistoryNotesData.source(Data(repeating:32,count:2*1024*1024+1)))
    }
    func testFullMaximumControlsRowsAndUInt64DomainFitTheApprovedSourceCap()throws{
        var value=F.source(Array(repeating:String(repeating:"\u{1}",count:256),count:1024))
        var rows=value["rows"] as! [[String:String]]
        for i in rows.indices{rows[i]["id"]="\(F.capture):\(UInt64.max):2:\(UInt64.max):\(UInt64.max-UInt64(i))"}
        value["rows"]=rows;value["recordState"]="partial";value["gaps"]=F.gaps
        value["selection"]=["kind":"full_saved_transcript","totalSavedRows":1024,"includedRows":1024,"firstRowID":rows.first!["id"]!,"lastRowID":rows.last!["id"]!]
        let raw=try F.encode(value),parsed=try HistoryNotesData.source(raw)
        XCTAssertLessThan(raw.count,2*1024*1024);XCTAssertGreaterThan(raw.count,768*1024)
        XCTAssertEqual(parsed.rows.count,1024);XCTAssertEqual(parsed.rows.reduce(0){$0+$1.text.utf8.count},262144)
        XCTAssertEqual(parsed.gaps,F.gaps)
        rows[0]["text"]!+="x";value["rows"]=rows
        XCTAssertThrowsError(try HistoryNotesData.source(F.encode(value)))
    }
    func testFullAndExcerptConsistencyDoesNotClaimActualCompleteness()throws{
        var value=F.source(["first","second"])
        value["selection"]=["kind":"explicit_excerpt","totalSavedRows":9,"includedRows":2,"firstRowID":F.id(),"lastRowID":F.id(2)]
        XCTAssertEqual(try HistoryNotesData.source(F.encode(value)).selection.totalSavedRows,9)
        var selection=value["selection"] as! [String:Any];selection["kind"]="full_saved_transcript";value["selection"]=selection
        XCTAssertThrowsError(try HistoryNotesData.source(F.encode(value)))
        selection["kind"]="explicit_excerpt";selection["includedRows"]=true;value["selection"]=selection
        XCTAssertThrowsError(try HistoryNotesData.source(F.encode(value)))
    }
    func testRowsAndElevenGapsAreExactAndSourceLabelled()throws{
        var value=F.source(["one","two"]),rows=value["rows"] as! [[String:String]]
        rows[1]["id"]=rows[0]["id"];value["rows"]=rows
        XCTAssertThrowsError(try HistoryNotesData.source(F.encode(value)))
        value=F.source();rows=value["rows"] as! [[String:String]];rows[0]["source"]="microphone";value["rows"]=rows
        XCTAssertThrowsError(try HistoryNotesData.source(F.encode(value)))
        for text in [""," \n\t","bad\0value",String(repeating:"a",count:1201)]{XCTAssertThrowsError(try HistoryNotesData.source(F.encode(F.source([text]))))}
        for gaps in [[F.gaps[0],F.gaps[0]],Array(F.gaps.reversed()),["unknown"]]{value=F.source();value["recordState"]="partial";value["gaps"]=gaps;XCTAssertThrowsError(try HistoryNotesData.source(F.encode(value)))}
        value=F.source();value["gaps"]=[F.gaps[0]];XCTAssertThrowsError(try HistoryNotesData.source(F.encode(value)))
    }
    func testOutputCitationsUseExactOriginalBytesAndIncludedRows()throws{
        let source=try HistoryNotesData.source(F.encode(F.source(["é original e\u{301} quote \u{1}"])))
        let valid=try HistoryNotesData.output(F.encode(F.output(quote:"e\u{301}")),source:source)
        XCTAssertEqual(valid.summary[0].citations[0].quote,"e\u{301}")
        XCTAssertThrowsError(try HistoryNotesData.output(F.encode(F.output(quote:"é quote")),source:source))
        var value=F.output();var items=value["summary"] as! [[String:Any]]
        items[0]["citations"]=[["rowID":F.id(99),"quote":"quote"]];value["summary"]=items
        XCTAssertThrowsError(try HistoryNotesData.output(F.encode(value),source:source))
        XCTAssertNoThrow(try HistoryNotesData.output(F.encode(F.output(quote:"\u{1}")),source:source))
    }
    func testOutputIsBoundedAndRoundtripsCanonicalData()throws{
        let source=try HistoryNotesData.source(F.encode(F.source())),raw=try F.encode(F.output())
        let parsed=try HistoryNotesData.output(raw,source:source)
        XCTAssertEqual(try HistoryNotesData.output(parsed.canonicalBytes,source:source).canonicalBytes,parsed.canonicalBytes)
        XCTAssertNoThrow(try HistoryNotesData.output(raw+Data(repeating:32,count:8192-raw.count),source:source))
        XCTAssertThrowsError(try HistoryNotesData.output(raw+Data(repeating:32,count:8193-raw.count),source:source))
        var value=F.output();value["summary"]=[];XCTAssertThrowsError(try HistoryNotesData.output(F.encode(value),source:source))
        value=F.output();value["authorized"]=true;XCTAssertThrowsError(try HistoryNotesData.output(F.encode(value),source:source))
    }
    func testFiniteUnicodeAndEscapingMatrixPreservesOriginalQuoteBytes()throws{
        let samples=["a","é","e\u{301}","汉字","👩🏽‍💻","\"","\\","/","\n","\t","\u{1}","\u{2028}","\u{200d}","𐐷","<tag>"]
        for left in samples{for right in samples{
            let quote="q:"+left+right,raw=try F.encode(F.source(["begin "+quote+" end"]))
            let source=try HistoryNotesData.source(raw)
            XCTAssertEqual(source.rawBytes,raw)
            let result=try HistoryNotesData.output(F.encode(F.output(quote:quote)),source:source)
            XCTAssertEqual(Data(result.summary[0].citations[0].quote.utf8),Data(quote.utf8))
            XCTAssertEqual(try HistoryNotesData.output(result.canonicalBytes,source:source).canonicalBytes,result.canonicalBytes)
        }}
    }
    func testDocumentValidatesFullMembershipAndRetainsGenerationAcrossClockRollback()throws{
        let rawSource=F.source(),source=try HistoryNotesData.source(F.encode(rawSource))
        var value=try F.document(rawSource)
        XCTAssertEqual(try HistoryNotesData.document(F.encode(value),source:source).origin,"generated")
        value["origin"]="generated_user_edited";value["editedAt"]="2026-10-24T09:00:00.000Z"
        let parsed=try HistoryNotesData.document(F.encode(value),source:source)
        XCTAssertEqual(parsed.sourceRows.count,source.rows.count);XCTAssertEqual(parsed.sourceRecordRevision,7)
        XCTAssertEqual(parsed.savedAtRecordRevision,8);XCTAssertEqual(parsed.generation.completedAt,"2026-10-24T10:00:00.000Z")
        XCTAssertEqual(parsed.editedAt,"2026-10-24T09:00:00.000Z")
        XCTAssertEqual(try HistoryNotesData.document(parsed.canonicalBytes,source:source).canonicalBytes,parsed.canonicalBytes)
    }
    func testDocumentRejectsInventedMembershipSourceDigestOrGenerationShape()throws{
        let rawSource=F.source(),source=try HistoryNotesData.source(F.encode(rawSource)),original=try F.document(rawSource)
        for key in original.keys{var value=original;value.removeValue(forKey:key);XCTAssertThrowsError(try HistoryNotesData.document(F.encode(value),source:source),key)}
        for pair in [("sourceDigest",String(repeating:"0",count:64)),("savedAtRecordRevision","7"),("modelID","bad\u{1}"),("origin","user"),("editedAt","2026-10-24T09:00:00.000Z")]{var value=original;value[pair.0]=pair.1;XCTAssertThrowsError(try HistoryNotesData.document(F.encode(value),source:source),pair.0)}
        var value=original;value["sourceRows"]=[];XCTAssertThrowsError(try HistoryNotesData.document(F.encode(value),source:source))
        var generation=original["generation"] as! [String:String];generation["completedAt"]="2026-02-30T10:00:00.000Z";value=original;value["generation"]=generation
        XCTAssertThrowsError(try HistoryNotesData.document(F.encode(value),source:source))
    }
}
