import Foundation
import XCTest
import RelayNativeSession
import RelayProfile
import GRDB
@testable import RelaySessionPanel

private struct ErrorStopRestoreKey:ProfileKeyProvider{
    func key(createIfMissing:Bool)throws->Data{Data(repeating:119,count:32)}
}
@MainActor final class HistoryErrorStopRestoreTests:XCTestCase{
    func testActualErrorReceiptCannotRestoreAsCompletedAfterItsProjectedGapIsRemoved()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("relay-history-error-restore-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        addTeardownBlock{try? FileManager.default.removeItem(at:root)}
        let vault=ProtectedSnapshotVault(directory:root.appendingPathComponent("Relay/History"),purpose:.history,keys:ErrorStopRestoreKey())
        let store=HistoryStore(storage:vault);try store.open(create:true)
        let record=try store.createRecord(),transcript=SessionTranscriptStore()
        var observations:[ValidatedTranscriptObservation]=[];transcript.onHistoryObservation={observations.append($0)}
        var events=HistoryTestEvents();events.start(transcript);events.final(1,text:"Fictional source text.",into:transcript)
        transcript.observe(events.event(.stopping,payload:["reasonCode":.string("capture_error")]))
        transcript.observe(events.event(.stopped,payload:["reasonCode":.string("capture_error"),"quiesced":.bool(true)]))
        for value in observations{try store.append(value,to:record.id)}
        try store.finish(record.id,outcome:.completed);try store.close()
        let queue=try HistorySnapshotCodec.decode(vault.load())
        try await queue.write{db in
            let raw=try XCTUnwrap(try Data.fetchOne(db,sql:"SELECT payload FROM history_record"))
            var contradictory=try HistoryJSON.decode(HistoryRecord.self,raw)
            contradictory.state = .completed;contradictory.gaps=[]
            try db.execute(sql:"UPDATE history_record SET payload=?",arguments:[try HistoryJSON.encode(contradictory)])
        }
        try vault.save(HistorySnapshotCodec.encode(queue));try queue.close()
        let before=try vault.load(),restored=HistoryStore(storage:vault)
        XCTAssertThrowsError(try restored.open(create:false),"A contradictory projection must not erase original fault evidence")
        XCTAssertEqual(try vault.load(),before)
        try restored.close()
    }
}
