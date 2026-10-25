import Foundation
import XCTest
import RelayProfile
import GRDB
@testable import RelaySessionPanel
private struct RootHistoryKey:ProfileKeyProvider {func key(createIfMissing:Bool)throws->Data{Data(repeating:67,count:32)}}
@MainActor final class HistoryRootReviewTests:XCTestCase {
 func testContradictoryStoredTimingCannotOverrideOriginalNativeEvidenceOnRestore()async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
  defer{try? FileManager.default.removeItem(at:root)}
  let vault=ProtectedSnapshotVault(directory:root.appendingPathComponent("Relay/History"),purpose:.history,keys:RootHistoryKey())
  let store=HistoryStore(storage:vault);try store.open(create:true);let record=try store.createRecord()
  let transcript=SessionTranscriptStore();var observations:[ValidatedTranscriptObservation]=[]
  transcript.onHistoryObservation={observations.append($0)};var events=HistoryTestEvents();events.start(transcript);events.final(1,text:"Fictional timing test.",into:transcript)
  for o in observations{try store.append(o,to:record.id)}
  let original=try XCTUnwrap(store.detail(record.id).rows.first)
  XCTAssertEqual(original.startUptimeNanoseconds.value,100);XCTAssertEqual(original.endUptimeNanoseconds.value,150)
  try store.close();let queue=try HistorySnapshotCodec.decode(vault.load())
  try await queue.write{db in
   let bytes=try XCTUnwrap(Data.fetchOne(db,sql:"SELECT payload FROM history_final"))
   var object=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
   object["startUptimeNanoseconds"]="200";object["endUptimeNanoseconds"]="250"
   let changed=try JSONDecoder().decode(HistoryFinal.self,from:JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]))
   XCTAssertEqual(changed.originalEventJSON,original.originalEventJSON)
   try db.execute(sql:"UPDATE history_final SET payload=?,sort_ticks=?",arguments:[try HistoryJSON.encode(changed),HistoryCounter(200).sortBytes])
  }
  try vault.save(HistorySnapshotCodec.encode(queue));try queue.close()
  let fresh=HistoryStore(storage:vault);defer{try? fresh.close()}
  XCTAssertThrowsError(try fresh.open(create:false),"Contradictory timing should fail strict original-evidence validation")
 }
}
