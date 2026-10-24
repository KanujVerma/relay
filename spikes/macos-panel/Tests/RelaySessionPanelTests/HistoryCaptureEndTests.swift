import Foundation
import XCTest
import RelayNativeSession
import RelayProfile
import GRDB
@testable import RelaySessionPanel

private struct PatchedCaptureStop:Encodable{
    let observedWallTime:TimeInterval
    let originalEventJSON:Data
}
private struct CaptureEndKey:ProfileKeyProvider{
    func key(createIfMissing:Bool)throws->Data{Data(repeating:107,count:32)}
}
@MainActor final class HistoryCaptureEndTests:XCTestCase{
    private func storage()throws->ProtectedSnapshotVault{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("relay-history-capture-end-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        addTeardownBlock{try? FileManager.default.removeItem(at:root)}
        return ProtectedSnapshotVault(directory:root.appendingPathComponent("Relay/History"),purpose:.history,keys:CaptureEndKey())
    }
    private func observations(quiesced:Bool?)->[ValidatedTranscriptObservation]{
        let transcript=SessionTranscriptStore();var values:[ValidatedTranscriptObservation]=[]
        transcript.onHistoryObservation={values.append($0)};var events=HistoryTestEvents()
        events.start(transcript);events.final(1,text:"A fictional final passage.",into:transcript)
        if let quiesced{events.stop(quiesced:quiesced,into:transcript)}
        return values
    }
    func testOriginalQuiescedStopIsRetainedAcrossEncryptedRestartAndExport()async throws{
        let vault=try storage(),store=HistoryStore(storage:vault);try store.open(create:true)
        let record=try store.createRecord(),values=observations(quiesced:true)
        for value in values{try store.append(value,to:record.id)}
        try store.finish(record.id,outcome:.completed)
        let before=try store.detail(record.id),stop=try XCTUnwrap(before.captures.first?.stop)
        XCTAssertTrue(stop.quiesced);XCTAssertEqual(stop.eventSequence?.value,values.last?.event.eventSequence)
        XCTAssertEqual(before.captures.first?.observedEndUptimeNanoseconds?.value,values.last?.event.emittedUptimeNanoseconds)
        XCTAssertEqual(before.record.state,.completed);XCTAssertFalse(before.record.gaps.contains(.captureEndUnknown))
        let original=try HistoryJSON.encode(try XCTUnwrap(values.last?.event))
        XCTAssertEqual(stop.originalEventJSON,original)
        try store.close();let fresh=HistoryStore(storage:vault);try fresh.open(create:false)
        let after=try fresh.detail(record.id);XCTAssertEqual(after,before)
        let markdown=String(decoding:try HistoryExport.encode(after,format:.markdown),as:UTF8.self)
        XCTAssertTrue(markdown.contains("Capture cleanup observed"))
        let json=try XCTUnwrap(JSONSerialization.jsonObject(with:HistoryExport.encode(after,format:.json)) as? [String:Any])
        let captures=try XCTUnwrap(json["captures"] as? [[String:Any]]),exportedStop=try XCTUnwrap(captures.first?["stop"] as? [String:Any])
        XCTAssertEqual(captures.first?["cleanupEndStatus"] as? String,"observed")
        XCTAssertEqual(exportedStop["quiesced"] as? Bool,true)
        XCTAssertEqual((exportedStop["originalNativeEvidence"] as? [String:Any])?["kind"] as? String,"stopped")
        try fresh.close()
    }
    func testFalseOrMissingStopNeverUsesLogicalEndedAtAsCaptureEnd()async throws{
        for quiesced in [Bool?.some(false),nil]{
            let vault=try storage(),store=HistoryStore(storage:vault);try store.open(create:true)
            let record=try store.createRecord()
            for value in observations(quiesced:quiesced){try store.append(value,to:record.id)}
            try store.finish(record.id,outcome:.completed)
            let detail=try store.detail(record.id)
            XCTAssertEqual(detail.record.state,.partial);XCTAssertNotNil(detail.record.endedAt)
            XCTAssertTrue(detail.record.gaps.contains(.captureEndUnknown));XCTAssertNil(detail.captures[0].observedEndUptimeNanoseconds)
            if quiesced != nil{XCTAssertNotNil(detail.captures[0].stop);XCTAssertFalse(detail.captures[0].stop!.quiesced)}
            try store.close();let reopened=HistoryStore(storage:vault);try reopened.open(create:false)
            XCTAssertEqual(try reopened.detail(record.id),detail);try reopened.close()
        }
    }
    func testReservedOriginalStopDrainsAfterRetiredRowsAndLockCannotReopenIt()async throws{
        let vault=try storage(),preferences=HistoryFixturePreferences()
        let history=SessionHistoryCoordinator(storageFactory:{vault},preferences:preferences,canEnable:{true})
        try await history.enableSaving();let issued=try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{true})
        let permit=try XCTUnwrap(issued)
        let transcript=SessionTranscriptStore();transcript.onHistoryObservation=history.observe
        var events=HistoryTestEvents();events.start(transcript);events.final(1,text:"Before admission retirement",into:transcript)
        history.retireCurrentSession();transcript.pause()
        events.final(2,text:"Must remain absent",into:transcript);events.stop(into:transcript)
        try await history.finishSession(permit,paused:false);try await history.openRecord(permit.recordID)
        let detail=try XCTUnwrap(history.snapshot.selected)
        XCTAssertEqual(detail.rows.map(\.text),["Before admission retirement"])
        XCTAssertTrue(detail.captures[0].stop?.quiesced==true);XCTAssertEqual(detail.record.state,.completed)
        history.lock();events.stop(into:transcript);await history.waitForQuiescence()
        XCTAssertEqual(history.snapshot.phase,.locked);XCTAssertNil(history.snapshot.selected)
    }
    func testGapBeforeOriginalStopRetainsReceiptButNeverClaimsCompleteText()async throws{
        let vault=try storage(),preferences=HistoryFixturePreferences()
        let history=SessionHistoryCoordinator(storageFactory:{vault},preferences:preferences,canEnable:{true})
        try await history.enableSaving();let issued=try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{true})
        let permit=try XCTUnwrap(issued),transcript=SessionTranscriptStore();transcript.onHistoryObservation=history.observe
        var events=HistoryTestEvents();events.start(transcript);events.final(1,text:"Before a missing event",into:transcript)
        events.sequence+=1
        transcript.observe(events.event(.stopped,payload:["reasonCode":.string("user_stop"),"quiesced":.bool(true)]))
        history.retireCurrentSession();try await history.finishSession(permit,paused:false)
        try await history.openRecord(permit.recordID);let detail=try XCTUnwrap(history.snapshot.selected)
        XCTAssertTrue(detail.captures[0].stop?.quiesced==true)
        XCTAssertEqual(detail.record.state,.partial);XCTAssertTrue(detail.record.gaps.contains(.sequenceGap))
        history.lock();await history.waitForQuiescence()
    }
    func testOldStartOnlyCompletedSnapshotReopensAsPartialWithoutInventingEnd()async throws{
        let vault=try storage(),store=HistoryStore(storage:vault);try store.open(create:true)
        let record=try store.createRecord();for value in observations(quiesced:nil){try store.append(value,to:record.id)}
        try store.finish(record.id,outcome:.completed);try store.close()
        // Reconstruct the already-issued version1 predecessor shape exactly:
        // no stop field, Completed, original logical endedAt and no end gap.
        let queue=try HistorySnapshotCodec.decode(vault.load())
        try await queue.write{db in
            let raw=try XCTUnwrap(try Data.fetchOne(db,sql:"SELECT payload FROM history_record"))
            var predecessor=try HistoryJSON.decode(HistoryRecord.self,raw)
            predecessor.state = .completed;predecessor.gaps=[]
            // Preserve canonical Double bytes and SQL column identity. Generic
            // JSONSerialization can spell endedAt differently from JSONEncoder.
            try db.execute(sql:"UPDATE history_record SET payload=?",arguments:[try HistoryJSON.encode(predecessor)])
        }
        try vault.save(HistorySnapshotCodec.encode(queue));try queue.close()
        let fresh=HistoryStore(storage:vault);try fresh.open(create:false)
        let detail=try fresh.detail(record.id)
        XCTAssertEqual(detail.record.state,.partial);XCTAssertTrue(detail.record.gaps.contains(.captureEndUnknown))
        XCTAssertNil(detail.captures[0].stop);XCTAssertNil(detail.captures[0].observedEndUptimeNanoseconds);try fresh.close()
    }
    func testMalformedStopOrContradictoryFinalOrderRollsBackActualCiphertext()async throws{
        for variant in 0..<6{
            let vault=try storage(),store=HistoryStore(storage:vault);try store.open(create:true)
            let record=try store.createRecord(),values=observations(quiesced:true)
            for value in values{try store.append(value,to:record.id)};try store.close()
            let queue=try HistorySnapshotCodec.decode(vault.load())
            try await queue.write{db in
                let raw=try XCTUnwrap(try Data.fetchOne(db,sql:"SELECT payload FROM history_capture"))
                var capture=try HistoryJSON.decode(HistoryCapture.self,raw)
                let stop=try XCTUnwrap(capture.stop)
                var event=try XCTUnwrap(JSONSerialization.jsonObject(with:stop.originalEventJSON) as? [String:Any])
                switch variant{
                case 0:event["captureSessionID"]=UUID().uuidString.lowercased()
                case 1:event["sessionEpoch"]=2
                case 2:event["eventSequence"]=2 // before the actual admitted final
                case 3:event["emittedUptimeNanoseconds"]=0
                case 4:event["sourceCode"]=2
                default:event["payload"]=["reasonCode":"user_stop","quiesced":true,"invented":true]
                }
                let patched=PatchedCaptureStop(observedWallTime:stop.observedWallTime,
                    originalEventJSON:try JSONSerialization.data(withJSONObject:event,options:[.sortedKeys]))
                capture.stop=try JSONDecoder().decode(HistoryCaptureStop.self,from:HistoryJSON.encode(patched))
                try db.execute(sql:"UPDATE history_capture SET payload=?",arguments:[try HistoryJSON.encode(capture)])
            }
            try vault.save(HistorySnapshotCodec.encode(queue));try queue.close()
            let before=try vault.load(),fresh=HistoryStore(storage:vault)
            XCTAssertThrowsError(try fresh.open(create:false),"Malformed original stop variant \(variant)")
            XCTAssertEqual(try vault.load(),before)
        }
    }
}
