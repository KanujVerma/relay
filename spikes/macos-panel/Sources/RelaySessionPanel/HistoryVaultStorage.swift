import Darwin
import Foundation
import RelayProfile

/// The store calls begin before any snapshot access and end only after its
/// actual GRDB queues close. Reusing one port does not issue a second owner.
public protocol HistoryOwnedSnapshotStorage:ProtectedSnapshotStorage {
    func beginAccess(create:Bool)throws
    func endAccess()throws
}

/// Cooperating-process consistency for the fixed local History domain. The
/// zero-content lock is retained, never truncated/unlinked, and has no PID,
/// title, timestamp or private index. It is not hostile same-user isolation.
public final class HistoryVaultStorage:HistoryOwnedSnapshotStorage,@unchecked Sendable {
    private struct Identity:Equatable{let device:dev_t,inode:ino_t}
    private struct Lease{
        var relay:Int32?,history:Int32?,file:Int32?
        let relayID:Identity,historyID:Identity,fileID:Identity
        var closeFailed=false
    }
    private let directory:URL
    private let vault:ProtectedSnapshotVault
    private let lock=NSLock()
    private var lease:Lease?
    public init(directory:URL,keys:any ProfileKeyProvider){
        self.directory=directory;vault=ProtectedSnapshotVault(directory:directory,purpose:.history,keys:keys)
    }
    private func identity(_ value:stat)->Identity{Identity(device:value.st_dev,inode:value.st_ino)}
    private func descriptor(_ fd:Int32,directory:Bool)throws->stat{
        var value=stat()
        guard fstat(fd,&value)==0,value.st_uid==getuid(),
              value.st_mode & mode_t(S_IFMT)==mode_t(directory ? S_IFDIR:S_IFREG),
              value.st_mode & 0o7777 == (directory ? 0o700:0o600),
              directory || (value.st_nlink==1 && value.st_size==0) else{throw HistoryError.unavailable}
        return value
    }
    private func path(_ url:URL)throws->stat{
        var value=stat()
        guard url.withUnsafeFileSystemRepresentation({name in name.map{lstat($0,&value)} ?? -1})==0 else{throw HistoryError.unavailable}
        return value
    }
    private func entry(_ parent:Int32,_ name:String)throws->stat{
        var value=stat()
        guard name.withCString({fstatat(parent,$0,&value,AT_SYMLINK_NOFOLLOW)})==0 else{throw HistoryError.unavailable}
        return value
    }
    private func openDirectory(_ url:URL,parent:Int32?=nil,name:String?=nil,create:Bool)throws->Int32{
        let flags=O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC
        func opened()->Int32{
            if let parent,let name{return name.withCString{openat(parent,$0,flags)}}
            return url.withUnsafeFileSystemRepresentation{$0.map{Darwin.open($0,flags)} ?? -1}
        }
        var fd=opened()
        if fd<0,errno==ENOENT,create{
            let made:Int32
            if let parent,let name{made=name.withCString{mkdirat(parent,$0,0o700)}}
            else{made=url.withUnsafeFileSystemRepresentation{$0.map{mkdir($0,0o700)} ?? -1}}
            guard made==0 || errno==EEXIST else{throw HistoryError.unavailable};fd=opened()
        }
        guard fd>=0 else{throw HistoryError.unavailable}
        do{_=try descriptor(fd,directory:true);return fd}catch{_=Darwin.close(fd);throw error}
    }
    public func beginAccess(create:Bool)throws{
        try lock.withLock{
            guard lease==nil else{throw HistoryError.closed}
            guard directory.isFileURL,!directory.path.utf8.contains(0),directory.lastPathComponent=="History",
                  directory.deletingLastPathComponent().lastPathComponent=="Relay" else{throw HistoryError.invalid}
            // No existing-only missing path creates even a lock. New stores
            // establish their lock through the explicit Enable action.
            if !create{guard try vault.exists() else{throw HistoryError.missing}}
            let parent=directory.deletingLastPathComponent()
            let relay=try openDirectory(parent,create:create)
            var history:Int32 = -1,file:Int32 = -1,retained=false
            defer{if !retained{if file>=0{_=Darwin.close(file)};if history>=0{_=Darwin.close(history)};_=Darwin.close(relay)}}
            history=try openDirectory(directory,parent:relay,name:"History",create:create)
            file="owner.lock".withCString{openat(history,$0,O_RDWR|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC|(create ? O_CREAT:0),0o600)}
            guard file>=0 else{throw HistoryError.unavailable}
            let fileStat=try descriptor(file,directory:false)
            guard flock(file,LOCK_EX|LOCK_NB)==0 else{
                if errno==EWOULDBLOCK{throw HistoryError.inUse};throw HistoryError.unavailable
            }
            lease=Lease(relay:relay,history:history,file:file,relayID:identity(try descriptor(relay,directory:true)),
                historyID:identity(try descriptor(history,directory:true)),fileID:identity(fileStat))
            retained=true
            do{try validateOwned()}
            catch{try? endOwned();throw error}
        }
    }
    private func validateOwned()throws{
        guard let lease,!lease.closeFailed,let relay=lease.relay,let history=lease.history,let file=lease.file else{throw HistoryError.closed}
        let parent=directory.deletingLastPathComponent()
        guard try identity(descriptor(relay,directory:true))==lease.relayID,
              try identity(descriptor(history,directory:true))==lease.historyID,
              try identity(descriptor(file,directory:false))==lease.fileID,
              try identity(path(parent))==lease.relayID,try identity(path(directory))==lease.historyID,
              try identity(entry(relay,"History"))==lease.historyID,
              try identity(entry(history,"owner.lock"))==lease.fileID else{throw HistoryError.unavailable}
    }
    public func exists()throws->Bool{try lock.withLock{try validateOwned();return try vault.exists()}}
    public func load()throws->Data{try lock.withLock{try validateOwned();return try vault.load()}}
    public func save(_ data:Data,createKey:Bool)throws{try lock.withLock{try validateOwned();try vault.save(data,createKey:createKey)}}
    public func endAccess()throws{try lock.withLock{try endOwned()}}
    private func endOwned()throws{
        guard var value=lease else{return}
        guard !value.closeFailed else{throw HistoryError.closed}
        // Close directories before the lock descriptor. These owner descriptors
        // never write data. A failed close is not retried against a reused fd.
        for kind in 0..<3{
            let fd=kind==0 ? value.history:kind==1 ? value.relay:value.file
            guard let fd else{continue}
            if kind==0{value.history=nil}else if kind==1{value.relay=nil}else{value.file=nil}
            lease=value
            guard Darwin.close(fd)==0 else{value.closeFailed=true;lease=value;throw HistoryError.closed}
        }
        lease=nil
    }
    deinit{
        if let lease{if let fd=lease.history{_=Darwin.close(fd)};if let fd=lease.relay{_=Darwin.close(fd)};if let fd=lease.file{_=Darwin.close(fd)}}
    }
}
