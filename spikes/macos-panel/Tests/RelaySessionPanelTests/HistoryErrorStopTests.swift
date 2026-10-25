import Foundation
import XCTest
import RelayNativeSession
import RelayProfile
@testable import RelaySessionPanel

private struct HistoryErrorStopKey:ProfileKeyProvider{
    func key(createIfMissing:Bool)throws->Data{Data(repeating:117,count:32)}
}
@MainActor final class HistoryErrorStopTests:XCTestCase{
    func testQuiescedErrorStopsKeepOriginalEndEvidenceButSavedTextRemainsPartial()async throws{
        for reason in [SessionReason.captureError,.shutdownTimeout,.consentRevoked]{
            let root=FileManager.default.temporaryDirectory.appendingPathComponent("relay-history-reason-"+UUID().uuidString)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            addTeardownBlock{try? FileManager.default.removeItem(at:root)}
            let vault=ProtectedSnapshotVault(directory:root.appendingPathComponent("Relay/History"),purpose:.history,keys:HistoryErrorStopKey())
            let store=HistoryStore(storage:vault);try store.open(create:true)
            let record=try store.createRecord(),transcript=SessionTranscriptStore()
            var observations:[ValidatedTranscriptObservation]=[];transcript.onHistoryObservation={observations.append($0)}
            var events=HistoryTestEvents();events.start(transcript)
            events.final(1,text:"Fictional passage before the source stopped.",into:transcript)
            transcript.observe(events.event(.stopping,payload:["reasonCode":.string(reason.rawValue)]))
            let stopped=events.event(.stopped,payload:["reasonCode":.string(reason.rawValue),"quiesced":.bool(true)])
            transcript.observe(stopped)
            for value in observations{try store.append(value,to:record.id)}
            try store.finish(record.id,outcome:.completed)
            let detail=try store.detail(record.id),capture=try XCTUnwrap(detail.captures.first)
            XCTAssertTrue(capture.stop?.quiesced==true)
            XCTAssertEqual(capture.stop?.originalEventJSON,try HistoryJSON.encode(stopped))
            XCTAssertEqual(capture.observedEndUptimeNanoseconds?.value,stopped.emittedUptimeNanoseconds)
            XCTAssertEqual(detail.rows.map(\.text),["Fictional passage before the source stopped."])
            XCTAssertEqual(detail.record.state,.partial,"Actual cleanup does not prove an error-free transcript: \(reason)")
            XCTAssertTrue(detail.record.gaps.contains(.captureFailure),"The original error reason remains visible as a fixed gap")
            try store.close();let restored=HistoryStore(storage:vault);try restored.open(create:false)
            let reopened=try restored.detail(record.id)
            XCTAssertEqual(reopened.record.state,.partial);XCTAssertEqual(reopened,detail)
            XCTAssertNotNil(reopened.captures[0].observedEndUptimeNanoseconds)
            try restored.close()
        }
    }
}
