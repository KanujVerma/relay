import Foundation
import GRDB
import GRDBSQLite

enum ProbeError: Error { case failed(String), abortBackup }
func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw ProbeError.failed(message) }
}
func check(_ rc: Int32, _ label: String) throws {
    try require(rc == SQLITE_OK, "\(label): sqlite \(rc)")
}
func execute(_ db: OpaquePointer, _ sql: String) throws {
    try check(sqlite3_exec(db, sql, nil, nil, nil), "exec")
}
func scalar(_ db: OpaquePointer, _ sql: String) throws -> String {
    var statement: OpaquePointer?
    try check(sqlite3_prepare_v2(db, sql, -1, &statement, nil), "prepare")
    defer { sqlite3_finalize(statement) }
    try require(sqlite3_step(statement) == SQLITE_ROW, "step")
    guard let bytes = sqlite3_column_text(statement, 0) else { throw ProbeError.failed("null") }
    return String(cString: bytes)
}
func serialize(_ db: OpaquePointer) throws -> Data {
    var size: sqlite3_int64 = 0
    guard let bytes = sqlite3_serialize(db, "main", &size, 0) else { throw ProbeError.failed("serialize") }
    defer { sqlite3_free(bytes) }
    try require(size > 0 && size <= 8 * 1024 * 1024, "serialize cap")
    return Data(bytes: bytes, count: Int(size))
}
func deserialize(_ data: Data, into db: OpaquePointer) throws {
    try require(!data.isEmpty && data.count <= 8 * 1024 * 1024, "input cap")
    let capacity = data.count + 20
    guard let memory = sqlite3_malloc64(sqlite3_uint64(capacity)) else { throw ProbeError.failed("malloc") }
    _ = data.withUnsafeBytes { memcpy(memory, $0.baseAddress!, data.count) }
    memset(memory.advanced(by: data.count), 0, 20)
    // FREEONCLOSE transfers ownership even on failure; never free it twice.
    try check(sqlite3_deserialize(db, "main", memory.assumingMemoryBound(to: UInt8.self),
                                sqlite3_int64(data.count), sqlite3_int64(capacity),
                                UInt32(SQLITE_DESERIALIZE_FREEONCLOSE | SQLITE_DESERIALIZE_RESIZEABLE)), "deserialize")
    var maximum: sqlite3_int64 = 8 * 1024 * 1024
    try check(sqlite3_file_control(db, "main", SQLITE_FCNTL_SIZE_LIMIT, &maximum), "deserialized size cap")
    try require(maximum <= 8 * 1024 * 1024, "returned cap")
}
func openMemory() throws -> OpaquePointer {
    var db: OpaquePointer?
    try check(sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil), "open")
    guard let db else { throw ProbeError.failed("no db") }
    return db
}

print("SQLite \(String(cString: sqlite3_libversion())); OMIT_DESERIALIZE=\(sqlite3_compileoption_used("OMIT_DESERIALIZE"))")
do {
    let source = try openMemory(), restored = try openMemory()
    defer { sqlite3_close(source); sqlite3_close(restored) }
    try execute(source, "PRAGMA temp_store=MEMORY; PRAGMA journal_mode=MEMORY; CREATE TABLE fixture(value TEXT NOT NULL); INSERT INTO fixture VALUES ('Fictional birch');")
    let payload = try serialize(source)
    try deserialize(payload, into: restored)
    try execute(restored, "PRAGMA temp_store=MEMORY; PRAGMA journal_mode=MEMORY;")
    try require(try scalar(restored, "SELECT value FROM fixture") == "Fictional birch", "raw roundtrip")
    try require(try scalar(restored, "PRAGMA quick_check") == "ok", "raw integrity")
    try require(try scalar(restored, "PRAGMA temp_store") == "2", "raw temp policy")
    try require(sqlite3_exec(restored, "INSERT INTO fixture VALUES(zeroblob(9437184));", nil, nil, nil) == SQLITE_FULL,
                "raw actual memory cap")
    try require(try scalar(restored, "SELECT count(*) FROM fixture") == "1", "capped insert rolled back")
    print("direct SQLite: bounded serialize/deserialize + integrity + memory temp + actual size-limit rollback PASS (\(payload.count) bytes)")
}
do {
    var config = Configuration()
    config.prepareDatabase { db in try db.execute(sql: "PRAGMA temp_store=MEMORY; PRAGMA journal_mode=MEMORY;") }
    let source = try DatabaseQueue(configuration: config)
    let candidate = try DatabaseQueue(configuration: config)
    let restored = try DatabaseQueue(configuration: config)
    defer { try? source.close(); try? candidate.close(); try? restored.close() }
    try source.write { db in
        try db.execute(sql: "CREATE TABLE fixture(value TEXT NOT NULL); INSERT INTO fixture VALUES ('Fictional cedar'); CREATE TABLE padding(value BLOB); INSERT INTO padding VALUES(zeroblob(32768));")
    }
    try candidate.write { db in
        try db.execute(sql: "CREATE TABLE fixture(value TEXT NOT NULL); INSERT INTO fixture VALUES ('Prior candidate');")
    }
    var abortObserved = false
    do {
        try source.backup(to: candidate, pagesPerStep: 1) { progress in
            if !progress.isCompleted { abortObserved = true; throw ProbeError.abortBackup }
        }
        throw ProbeError.failed("backup unexpectedly completed")
    } catch ProbeError.abortBackup { }
    try require(abortObserved, "backup has multiple pages")
    let prior = try candidate.read { try String.fetchOne($0, sql: "SELECT value FROM fixture") }
    try require(prior == "Prior candidate", "backup rollback")
    try source.backup(to: candidate)
    let copied = try candidate.read { try String.fetchOne($0, sql: "SELECT value FROM fixture") }
    try require(copied == "Fictional cedar", "backup success")
    let payload = try candidate.read { db in try serialize(db.sqliteConnection!) }
    try restored.writeWithoutTransaction { db in
        try deserialize(payload, into: db.sqliteConnection!)
        db.clearSchemaCache()
        try db.execute(sql: "PRAGMA temp_store=MEMORY; PRAGMA journal_mode=MEMORY;")
    }
    let values = try restored.read { db in
        (try String.fetchOne(db, sql: "SELECT value FROM fixture"),
         try String.fetchOne(db, sql: "PRAGMA quick_check"),
         try Int.fetchOne(db, sql: "PRAGMA temp_store"),
         try Row.fetchAll(db, sql: "PRAGMA database_list"))
    }
    try require(values.0 == "Fictional cedar" && values.1 == "ok" && values.2 == 2, "GRDB restored fidelity")
    try require(values.3.allSatisfy { ($0["file"] as String).isEmpty }, "no disk database")
    try restored.write { db in try db.execute(sql: "INSERT INTO fixture VALUES ('After restore');") }
    let rowCount = try restored.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM fixture") }
    try require(rowCount == 2, "GRDB mutable restored")
    do {
        try restored.write { db in try db.execute(sql: "INSERT INTO fixture VALUES(zeroblob(9437184));") }
        throw ProbeError.failed("GRDB actual memory cap")
    } catch let error as DatabaseError { try require(error.resultCode == .SQLITE_FULL, "expected full") }
    let afterFull = try restored.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM fixture") }
    try require(afterFull == 2, "GRDB full rollback")
    print("GRDB pinned v7.11.1: abort backup preserves prior + successful backup + bounded serializer bridge + writable restore PASS")

    let held = try DatabaseQueue(configuration: config)
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    let closeEntered = DispatchSemaphore(value: 0), closeFinished = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        try! held.write { db in
            try db.execute(sql: "CREATE TABLE held(value TEXT);")
            entered.signal()
            precondition(release.wait(timeout: .now() + 3) == .success)
        }
    }
    try require(entered.wait(timeout: .now() + 2) == .success, "held writer entered")
    DispatchQueue.global().async { closeEntered.signal(); try! held.close(); closeFinished.signal() }
    try require(closeEntered.wait(timeout: .now() + 2) == .success, "close entered")
    try require(closeFinished.wait(timeout: .now() + 0.1) == .timedOut, "close joined writer")
    release.signal()
    try require(closeFinished.wait(timeout: .now() + 2) == .success, "close actually finished")
    do { _ = try held.read { try Int.fetchOne($0, sql: "SELECT 1") }; throw ProbeError.failed("read after close") }
    catch is DatabaseError { }
    print("GRDB actual close: waits for held writer; read after close rejects PASS")
}
let children = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.currentDirectoryPath)
try require(children == ["tmp"], "contained working directory has unexpected files: \(children)")
try require(try FileManager.default.contentsOfDirectory(atPath: "tmp").isEmpty, "temp spill")
print("owned working directory + TMPDIR: zero database/WAL/journal/temp files PASS")
