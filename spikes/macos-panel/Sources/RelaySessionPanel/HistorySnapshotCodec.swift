import Foundation
import GRDB
import GRDBSQLite

/// Only used inside an owned GRDB closure. Normal serialization copies bytes;
/// a pointer into mutable SQLite pages never escapes the queue.
enum HistorySnapshotCodec {
    static func configure(_ db:Database,deserialized:Bool=false)throws{
        guard sqlite3_compileoption_used("OMIT_DESERIALIZE")==0,let connection=db.sqliteConnection else{throw HistoryError.unavailable}
        try db.execute(sql:"PRAGMA foreign_keys=ON; PRAGMA secure_delete=ON; PRAGMA temp_store=MEMORY; PRAGMA journal_mode=MEMORY; PRAGMA trusted_schema=OFF;")
        guard try Int.fetchOne(db,sql:"PRAGMA foreign_keys")==1,
              try Int.fetchOne(db,sql:"PRAGMA temp_store")==2,
              try String.fetchOne(db,sql:"PRAGMA journal_mode")=="memory" else{throw HistoryError.unavailable}
        let pageSize=try Int.fetchOne(db,sql:"PRAGMA page_size") ?? 0
        guard pageSize>=512,pageSize<=65_536 else{throw HistoryError.invalid}
        let pages=HistoryBounds.snapshot/pageSize
        try db.execute(sql:"PRAGMA max_page_count=\(pages)")
        guard (try Int.fetchOne(db,sql:"PRAGMA page_count") ?? Int.max)<=pages else{throw HistoryError.capacity}
        sqlite3_limit(connection,SQLITE_LIMIT_LENGTH,512*1024)
        sqlite3_limit(connection,SQLITE_LIMIT_SQL_LENGTH,32*1024)
        sqlite3_limit(connection,SQLITE_LIMIT_COLUMN,32)
        sqlite3_limit(connection,SQLITE_LIMIT_ATTACHED,0)
        if deserialized{
            var maximum=sqlite3_int64(HistoryBounds.snapshot)
            guard sqlite3_file_control(connection,"main",SQLITE_FCNTL_SIZE_LIMIT,&maximum)==SQLITE_OK,
                  maximum<=HistoryBounds.snapshot else{throw HistoryError.unavailable}
        }
    }
    static func makeQueue()throws->DatabaseQueue{
        var configuration=Configuration()
        configuration.prepareDatabase{try configure($0)}
        return try DatabaseQueue(configuration:configuration)
    }
    static func encode(_ queue:DatabaseQueue)throws->Data{
        try queue.read{db in
            guard let connection=db.sqliteConnection else{throw HistoryError.closed}
            var size:sqlite3_int64=0
            guard let bytes=sqlite3_serialize(connection,"main",&size,0) else{throw HistoryError.unavailable}
            defer{sqlite3_free(bytes)}
            guard size>0,size<=HistoryBounds.snapshot else{throw HistoryError.capacity}
            return Data(bytes:bytes,count:Int(size))
        }
    }
    static func decode(_ data:Data)throws->DatabaseQueue{
        guard data.count>=100,data.count<=HistoryBounds.snapshot,data.starts(with:Data("SQLite format 3\0".utf8)),
              data[18]==1,data[19]==1 else{throw HistoryError.invalid}
        let queue=try makeQueue()
        do{
            try queue.writeWithoutTransaction{db in
                let capacity=data.count+20
                guard let connection=db.sqliteConnection,
                      let buffer=sqlite3_malloc64(sqlite3_uint64(capacity)) else{throw HistoryError.unavailable}
                _=data.withUnsafeBytes{memcpy(buffer,$0.baseAddress!,data.count)}
                memset(buffer.advanced(by:data.count),0,20)
                // SQLite frees this allocation on deserialize failure as well
                // as eventual close. Never free it a second time in catch.
                let rc=sqlite3_deserialize(connection,"main",buffer.assumingMemoryBound(to:UInt8.self),
                    sqlite3_int64(data.count),sqlite3_int64(capacity),UInt32(SQLITE_DESERIALIZE_FREEONCLOSE|SQLITE_DESERIALIZE_RESIZEABLE))
                guard rc==SQLITE_OK else{throw HistoryError.invalid}
                db.clearSchemaCache();try configure(db,deserialized:true)
                guard try String.fetchAll(db,sql:"PRAGMA quick_check")==["ok"],
                      try Row.fetchAll(db,sql:"PRAGMA foreign_key_check").isEmpty,
                      try Row.fetchAll(db,sql:"PRAGMA database_list").allSatisfy({($0["file"] as String).isEmpty}) else{throw HistoryError.invalid}
            }
            return queue
        }catch{try? queue.close();throw error}
    }
}
