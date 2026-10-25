import Foundation
import XCTest
import RelayProfile
@testable import RelaySessionPanel

private final class NotesSourceKey:ProfileKeyProvider,@unchecked Sendable {
    private let lock=NSLock();private var count=0
    var calls:Int{lock.withLock{count}}
    func key(createIfMissing:Bool)throws->Data{lock.withLock{count+=1};return Data(repeating:83,count:32)}
}
@MainActor final class HistoryNotesStoreSourceTests:XCTestCase {
    private func fixture(rows:Int=0)throws->(HistoryStore,ProtectedSnapshotVault,NotesSourceKey,UUID,[HistoryFinal]){
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-notes-source-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let key=NotesSourceKey(),vault=ProtectedSnapshotVault(directory:directory.appendingPathComponent("Relay/History"),purpose:.history,keys:key)
        let store=HistoryStore(storage:HistoryVaultStorage(directory:directory.appendingPathComponent("Relay/History"),keys:key));addTeardownBlock{try? store.close();try? FileManager.default.removeItem(at:directory)}
        try store.open(create:true);let record=try store.createRecord()
        let transcript=SessionTranscriptStore();var observations:[ValidatedTranscriptObservation]=[]
        transcript.onHistoryObservation={observations.append($0)};var events=HistoryTestEvents();events.start(transcript)
        for index in 1...max(1,rows){if rows>0{events.final(UInt64(index),text:"Fictional original row \(index).",source:index.isMultiple(of:2) ? 1:2,into:transcript)}}
        events.stop(into:transcript)
        for observation in observations{try store.append(observation,to:record.id)}
        try store.finish(record.id,outcome:.completed)
        return(store,vault,key,record.id,observations.compactMap(\.final))
    }
    func testActualSourceReadIncludesAllOriginalRowsBeyondThe64RowViewPage()throws{
        let(store,_,_,id,actual)=try fixture(rows:128),detail=try store.detail(id)
        XCTAssertEqual(detail.rows.count,64);XCTAssertEqual(detail.totalRows,128)
        let intent=UUID(),read=try store.readNotesSource(id,expectedRevision:detail.record.revision,selection:.fullSavedTranscript,intentID:intent,admission:{true})
        XCTAssertEqual(read.sourceData.rows.map(\.rowID),actual.map(\.id))
        XCTAssertEqual(read.sourceData.rows.map(\.text),actual.map(\.text))
        XCTAssertEqual(read.sourceData.selection.totalSavedRows,128);XCTAssertEqual(read.sourceData.selection.includedRows,128)
        XCTAssertEqual(read.intentID,intent)
        let parsed=try HistoryNotesData.source(read.sourceData.rawBytes)
        XCTAssertEqual(parsed.sourceDigest,read.sourceData.sourceDigest)
        XCTAssertFalse(String(decoding:parsed.rawBytes,as:UTF8.self).contains("originalEventJSON"))
    }
    func testExplicitExcerptSelectsExactContiguousEndpointsInCompleteStoreOrder()throws{
        let(store,_,_,id,actual)=try fixture(rows:70),revision=try store.detail(id).record.revision
        let read=try store.readNotesSource(id,expectedRevision:revision,selection:.excerpt(firstRowID:actual[63].id,lastRowID:actual[68].id),intentID:UUID(),admission:{true})
        XCTAssertEqual(read.sourceData.rows.map(\.rowID),Array(actual[63...68]).map(\.id))
        XCTAssertEqual(read.sourceData.selection.totalSavedRows,70);XCTAssertEqual(read.sourceData.selection.includedRows,6)
        for selection in [HistoryNotesSelection.excerpt(firstRowID:actual[68].id,lastRowID:actual[63].id),.excerpt(firstRowID:HistoryNotesFixtures.id(),lastRowID:actual[68].id)]{
            XCTAssertThrowsError(try store.readNotesSource(id,expectedRevision:revision,selection:selection,intentID:UUID(),admission:{true}))
        }
    }
    func testSourceReadRejectsEmptyStaleOrRetiredAndRevalidatesActualVault()throws{
        let(empty,_,_,emptyID,_)=try fixture();let revision=try empty.detail(emptyID).record.revision
        XCTAssertThrowsError(try empty.readNotesSource(emptyID,expectedRevision:revision,selection:.fullSavedTranscript,intentID:UUID(),admission:{true}))
        let(store,vault,_,id,_)=try fixture(rows:1),old=try store.detail(id).record.revision
        _=try store.edit(id,expectedRevision:old,title:"User-owned title",note:"This manual note must not enter the source.")
        XCTAssertThrowsError(try store.readNotesSource(id,expectedRevision:old,selection:.fullSavedTranscript,intentID:UUID(),admission:{true}))
        let current=try store.detail(id).record.revision
        XCTAssertThrowsError(try store.readNotesSource(id,expectedRevision:current,selection:.fullSavedTranscript,intentID:UUID(),admission:{false}))
        let read=try store.readNotesSource(id,expectedRevision:current,selection:.fullSavedTranscript,intentID:UUID(),admission:{true})
        XCTAssertFalse(String(decoding:read.sourceData.rawBytes,as:UTF8.self).contains("manual note"))
        try vault.save(Data("Changed but encrypted source".utf8),createKey:false)
        XCTAssertThrowsError(try store.readNotesSource(id,expectedRevision:current,selection:.fullSavedTranscript,intentID:UUID(),admission:{true}))
    }
    func testClosedSourceReadDoesNotCreateAFileOrReadAKey()throws{
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-notes-missing-"+UUID().uuidString)
        let key=NotesSourceKey(),vault=ProtectedSnapshotVault(directory:directory.appendingPathComponent("Relay/History"),purpose:.history,keys:key)
        let store=HistoryStore(storage:vault)
        XCTAssertThrowsError(try store.readNotesSource(UUID(),expectedRevision:1,selection:.fullSavedTranscript,intentID:UUID(),admission:{true}))
        XCTAssertEqual(key.calls,0);XCTAssertFalse(FileManager.default.fileExists(atPath:directory.path))
    }
}
