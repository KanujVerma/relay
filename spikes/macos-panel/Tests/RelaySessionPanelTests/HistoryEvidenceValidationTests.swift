import Foundation
import XCTest
import RelayProfile
import RelayNativeSession
import GRDB
@testable import RelaySessionPanel

private struct EvidenceHistoryKey:ProfileKeyProvider{func key(createIfMissing:Bool)throws->Data{Data(repeating:77,count:32)}}
@MainActor final class HistoryEvidenceValidationTests:XCTestCase{
    typealias Object=[String:Any]
    private func dictionary(_ data:Data)throws->Object{try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? Object)}
    private func roundTrip(_ mutation:(inout Object,inout Object)throws->Void)throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("relay-history-evidence-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer{try? FileManager.default.removeItem(at:root)}
        let vault=ProtectedSnapshotVault(directory:root.appendingPathComponent("Relay/History"),purpose:.history,keys:EvidenceHistoryKey())
        let store=HistoryStore(storage:vault);try store.open(create:true);let record=try store.createRecord()
        let transcript=SessionTranscriptStore();var observations:[ValidatedTranscriptObservation]=[]
        transcript.onHistoryObservation={observations.append($0)};var events=HistoryTestEvents();events.start(transcript);events.final(1,text:"Fictional original evidence",into:transcript)
        for value in observations{try store.append(value,to:record.id)}
        let original=try XCTUnwrap(store.detail(record.id).rows.first)
        try store.close();let queue=try HistorySnapshotCodec.decode(vault.load())
        var row=try dictionary(HistoryJSON.encode(original)),event=try dictionary(original.originalEventJSON)
        try mutation(&row,&event)
        row["originalEventJSON"]=try JSONSerialization.data(withJSONObject:event,options:[.sortedKeys]).base64EncodedString()
        let changed=try JSONDecoder().decode(HistoryFinal.self,from:JSONSerialization.data(withJSONObject:row,options:[.sortedKeys]))
        try queue.write{db in
            try db.execute(sql:"UPDATE history_final SET id=?,source=?,sort_ticks=?,payload=?",arguments:[changed.id,changed.source.rawValue,changed.startUptimeNanoseconds.sortBytes,try HistoryJSON.encode(changed)])
        }
        try vault.save(HistorySnapshotCodec.encode(queue));try queue.close()
        let saved=try Data(contentsOf:root.appendingPathComponent("Relay/History/history.relayvault"))
        let fresh=HistoryStore(storage:vault);defer{try? fresh.close()}
        XCTAssertThrowsError(try fresh.open(create:false))
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("Relay/History/history.relayvault")),saved)
    }
    private func inner(_ event:inout Object,_ change:(inout Object)->Void)throws{
        var payload=try XCTUnwrap(event["payload"] as? Object),value=try XCTUnwrap(payload["event"] as? Object)
        change(&value);payload["event"]=value;event["payload"]=payload
    }
    func testInnerSourceAndGenerationMustMatchOriginalOuterAndStoredIdentity()async throws{
        try roundTrip{row,event in
            row["source"]=1;row["id"]=(row["id"] as! String).replacingOccurrences(of:":2:1:1",with:":1:1:1");event["sourceCode"]=1
        }
        try roundTrip{row,event in
            row["streamGeneration"]="2";row["id"]=(row["id"] as! String).replacingOccurrences(of:":2:1:1",with:":2:2:1");event["streamGeneration"]=2
        }
    }
    func testClosedInputIntervalAndExactInnerSchemaAreRevalidatedOnRestore()async throws{
        for field in ["firstInputSequence","lastSpeechInputSequence","activityClosed","extra"]{
            try roundTrip{_,event in
                var payload=try XCTUnwrap(event["payload"] as? Object)
                if field=="firstInputSequence"{payload[field]=3}
                else if field=="activityClosed"{payload[field]=false}
                else if field=="extra"{payload[field]=true}
                else{payload[field]=9}
                event["payload"]=payload
            }
        }
        for field in ["status","version","segmentID","revision","extra"]{
            try roundTrip{_,event in try self.inner(&event){value in value[field]=field=="status" ? "partial":2}}
        }
    }
    func testCompletionOrderDurationAnchorAndClockConversionUseExistingValidatedBounds()async throws{
        for field in ["finalizedUptimeNanoseconds","receivedUptimeNanoseconds","confidence"]{
            try roundTrip{_,event in try self.inner(&event){value in value[field]=field=="confidence" ? 2:100}}
        }
        try roundTrip{_,event in event["emittedUptimeNanoseconds"]=100}
        for field in ["nsDenom","nsNumer","uptimeNsAtAnchor","hostTicksAtAnchor"]{
            try roundTrip{_,event in try self.inner(&event){value in
                var clock=value["timebase"] as! Object;clock[field]=field=="nsDenom" ? 0:2;value["timebase"]=clock
            }}
        }
        try roundTrip{_,event in try self.inner(&event){$0["finalizedUptimeNanoseconds"]=31_000_000_151;$0["receivedUptimeNanoseconds"]=31_000_000_152};event["emittedUptimeNanoseconds"]=31_000_000_153}
        try roundTrip{row,event in
            row["endUptimeNanoseconds"]="120000000101"
            try self.inner(&event){$0["endHostTime"]=120_000_000_101;$0["finalizedUptimeNanoseconds"]=120_000_000_101;$0["receivedUptimeNanoseconds"]=120_000_000_101};event["emittedUptimeNanoseconds"]=120_000_000_101
        }
        try roundTrip{row,event in
            row["startUptimeNanoseconds"]="601000000100";row["endUptimeNanoseconds"]="601000000150"
            try self.inner(&event){$0["startHostTime"]=601_000_000_100;$0["endHostTime"]=601_000_000_150;$0["finalizedUptimeNanoseconds"]=601_000_000_151;$0["receivedUptimeNanoseconds"]=601_000_000_152};event["emittedUptimeNanoseconds"]=601_000_000_153
        }
    }
    func testActualValidatorIssuedNontrivialCalibrationSurvivesEncryptedRestore()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("relay-history-calibration-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer{try? FileManager.default.removeItem(at:root)}
        let vault=ProtectedSnapshotVault(directory:root.appendingPathComponent("Relay/History"),purpose:.history,keys:EvidenceHistoryKey())
        let store=HistoryStore(storage:vault);try store.open(create:true);let record=try store.createRecord()
        let transcript=SessionTranscriptStore();var observations:[ValidatedTranscriptObservation]=[]
        transcript.onHistoryObservation={observations.append($0)};var events=HistoryTestEvents();events.start(transcript)
        let clock:WireValue = .object(["hostTicksAtAnchor":.uint(121),"uptimeNsAtAnchor":.uint(100),"nsNumer":.uint(3),"nsDenom":.uint(2)])
        transcript.observe(events.event(.speechStarted,source:2,payload:["activityID":.uint(1),"startHostTime":.uint(100),"detectedUptimeNanoseconds":.uint(1000),"timebase":clock]))
        transcript.observe(events.event(.speechEnded,source:2,payload:["activityID":.uint(1),"endHostTime":.uint(150),"lastSpeechInputSequence":.uint(2),"timebase":clock]))
        let inner:[String:WireValue] = ["version":.uint(1),"status":.string("final"),"sourceCode":.uint(2),"streamGeneration":.uint(1),"segmentID":.uint(1),"revision":.uint(1),"startHostTime":.uint(100),"endHostTime":.uint(150),"finalizedUptimeNanoseconds":.uint(1_000_000),"receivedUptimeNanoseconds":.uint(1_000_001),"text":.string("Fictional fractional calibration"),"confidence":.null,"timebase":clock]
        transcript.observe(events.event(.eou,source:2,payload:["event":.object(inner),"activityID":.uint(1),"firstInputSequence":.uint(1),"lastInputSequence":.uint(2),"lastSpeechInputSequence":.uint(2),"activityClosed":.bool(true)]))
        XCTAssertEqual(transcript.snapshot.rows.count,1)
        for value in observations{try store.append(value,to:record.id)}
        try store.close();let fresh=HistoryStore(storage:vault);try fresh.open(create:false)
        let row=try XCTUnwrap(fresh.detail(record.id).rows.first)
        XCTAssertEqual(row.startUptimeNanoseconds.value,68);XCTAssertEqual(row.endUptimeNanoseconds.value,143)
        try fresh.close()
    }
}
