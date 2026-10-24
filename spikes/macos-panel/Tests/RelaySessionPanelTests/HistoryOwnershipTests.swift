import Darwin
import Foundation
import XCTest
import RelayProfile
@testable import RelaySessionPanel

private final class OwnershipKey:ProfileKeyProvider,@unchecked Sendable{
    private let lock=NSLock();private var count=0
    var calls:Int{lock.withLock{count}}
    func key(createIfMissing:Bool)throws->Data{lock.withLock{count+=1};return Data(repeating:99,count:32)}
}
private final class HeldHistoryClose:HistoryOwnedSnapshotStorage,@unchecked Sendable{
    private let real:HistoryVaultStorage
    private let lock=NSLock(),gate=DispatchSemaphore(value:0)
    private var held=false,calls=0
    var isHeld:Bool{lock.withLock{held}}
    var closes:Int{lock.withLock{calls}}
    init(_ real:HistoryVaultStorage){self.real=real}
    func beginAccess(create:Bool)throws{try real.beginAccess(create:create)}
    func endAccess()throws{
        lock.withLock{held=true;calls+=1}
        guard gate.wait(timeout:.now()+8) == .success else{throw HistoryError.unavailable}
        try real.endAccess();lock.withLock{held=false}
    }
    func release(){gate.signal()}
    func exists()throws->Bool{try real.exists()}
    func load()throws->Data{try real.load()}
    func save(_ data:Data,createKey:Bool)throws{try real.save(data,createKey:createKey)}
}
private final class HeldHistoryBegin:HistoryOwnedSnapshotStorage,@unchecked Sendable{
    private let real:HistoryVaultStorage,lock=NSLock(),gate=DispatchSemaphore(value:0)
    private var held=false
    var isHeld:Bool{lock.withLock{held}}
    init(_ real:HistoryVaultStorage){self.real=real}
    func release(){gate.signal()}
    func beginAccess(create:Bool)throws{
        try real.beginAccess(create:create);lock.withLock{held=true}
        guard gate.wait(timeout:.now()+8) == .success else{throw HistoryError.unavailable}
        lock.withLock{held=false}
    }
    func endAccess()throws{try real.endAccess()}
    func exists()throws->Bool{try real.exists()}
    func load()throws->Data{try real.load()}
    func save(_ data:Data,createKey:Bool)throws{try real.save(data,createKey:createKey)}
}
@MainActor final class HistoryOwnershipTests:XCTestCase{
    private func fixture()throws->(URL,URL,OwnershipKey){
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("relay-history-owner-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        addTeardownBlock{try? FileManager.default.removeItem(at:root)}
        return(root,root.appendingPathComponent("Relay/History"),OwnershipKey())
    }
    private func until(_ condition:()->Bool)async throws{
        let end=ContinuousClock.now+Duration.seconds(5)
        while !condition(){guard ContinuousClock.now<end else{throw HistoryError.unavailable};try await Task.sleep(for:.milliseconds(3))}
    }
    private func probe(_ path:URL)async throws->Int32{
        let python=ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"] ?? "/usr/bin/python3"
        let process=Process();process.executableURL=URL(fileURLWithPath:python)
        process.arguments=["-I","-c","import fcntl,os,sys\nf=os.open(sys.argv[1],os.O_RDWR|os.O_NOFOLLOW)\ntry: fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)\nexcept BlockingIOError: sys.exit(17)\nos.close(f)\n",path.path]
        process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
        try process.run()
        do{try await until{!process.isRunning}}
        catch{process.terminate();try? await until{!process.isRunning};throw error}
        return process.terminationStatus
    }
    func testConstructorAndMissingExistingAccessCreateNoDirectoryKeyVaultOrLock()async throws{
        let(root,directory,key)=try fixture(),port=HistoryVaultStorage(directory:directory,keys:key)
        XCTAssertEqual(key.calls,0);XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("Relay").path))
        let store=HistoryStore(storage:port)
        XCTAssertThrowsError(try store.open(create:false));XCTAssertEqual(key.calls,0)
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("Relay").path))
        try FileManager.default.createDirectory(at:root.appendingPathComponent("Relay"),withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        XCTAssertThrowsError(try store.open(create:false));XCTAssertEqual(key.calls,0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
        try store.close()
    }
    func testTwoIndependentStoresCannotReadOrOverwriteWhileOriginalLeaseIsHeld()async throws{
        let(_,directory,key)=try fixture()
        let first=HistoryStore(storage:HistoryVaultStorage(directory:directory,keys:key))
        try first.open(create:true);let record=try first.createRecord();try first.finish(record.id,outcome:.completed)
        let second=HistoryStore(storage:HistoryVaultStorage(directory:directory,keys:key))
        let calls=key.calls
        XCTAssertThrowsError(try second.open(create:false))
        XCTAssertEqual(key.calls,calls,"A competing owner cannot read the key or plaintext before its lease")
        let before=try first.detail(record.id).record
        _=try first.edit(record.id,expectedRevision:before.revision,title:"Newer owner",note:"Must survive the independent owner")
        try first.close();try second.open(create:false)
        XCTAssertEqual(try second.detail(record.id).record.note,"Must survive the independent owner")
        XCTAssertThrowsError(try first.edit(record.id,expectedRevision:before.revision,title:"Stale",note:"Cannot overwrite"))
        try second.close()
    }
    func testSeparateProcessCannotAcquireUntilActualOwnerClose()async throws{
        let(_,directory,key)=try fixture(),port=HistoryVaultStorage(directory:directory,keys:key),store=HistoryStore(storage:port)
        try store.open(create:true)
        let file=directory.appendingPathComponent("owner.lock")
        XCTAssertEqual(try Data(contentsOf:file),Data())
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:file.path)[.posixPermissions] as? NSNumber)?.intValue,0o600)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath:directory.path)),["owner.lock","history.relayvault"])
        let held=try await probe(file);XCTAssertEqual(held,17)
        try store.close();let released=try await probe(file);XCTAssertEqual(released,0)
    }
    func testRepeatedLockJoinsActualStorageCloseAndRetainsCrossProcessLease()async throws{
        let(_,directory,key)=try fixture(),port=HeldHistoryClose(HistoryVaultStorage(directory:directory,keys:key))
        let coordinator=SessionHistoryCoordinator(storageFactory:{port},preferences:HistoryFixturePreferences(),canEnable:{true})
        addTeardownBlock{port.release();await coordinator.waitForQuiescence()}
        try await coordinator.enableSaving();coordinator.lock();try await until{port.isHeld}
        coordinator.lock();coordinator.lock()
        XCTAssertTrue(coordinator.isBusy);XCTAssertTrue(coordinator.snapshot.records.isEmpty)
        let next=HistoryStore(storage:HistoryVaultStorage(directory:directory,keys:key))
        XCTAssertThrowsError(try next.open(create:false))
        let held=try await probe(directory.appendingPathComponent("owner.lock"));XCTAssertEqual(held,17)
        port.release();await coordinator.waitForQuiescence()
        XCTAssertEqual(port.closes,1);XCTAssertFalse(coordinator.isBusy)
        try next.open(create:false);XCTAssertTrue(try next.list().records.isEmpty);try next.close()
    }
    func testLockEntriesAreNeverTruncatedOverwrittenOrPermissionHealed()async throws{
        for mode in ["nonzero","permissions","symlink","hardlink"]{
            let(root,directory,key)=try fixture(),store=HistoryStore(storage:HistoryVaultStorage(directory:directory,keys:key))
            try store.open(create:true);try store.close()
            let lock=directory.appendingPathComponent("owner.lock"),outside=root.appendingPathComponent("fixture-only-outside")
            try FileManager.default.removeItem(at:lock)
            try Data("preserve owned fixture".utf8).write(to:outside);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:outside.path)
            switch mode{
            case "symlink":try FileManager.default.createSymbolicLink(at:lock,withDestinationURL:outside)
            case "hardlink":try FileManager.default.linkItem(at:outside,to:lock)
            default:try Data((mode=="nonzero" ? "preserve lock":"").utf8).write(to:lock)
            }
            if mode=="permissions"{try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:lock.path)}
            else if mode=="nonzero"{try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:lock.path)}
            let before=try Data(contentsOf:lock),attributes=try FileManager.default.attributesOfItem(atPath:lock.path)
            let rejected=HistoryStore(storage:HistoryVaultStorage(directory:directory,keys:key))
            XCTAssertThrowsError(try rejected.open(create:false),mode);XCTAssertThrowsError(try rejected.open(create:true),mode)
            XCTAssertEqual(try Data(contentsOf:lock),before)
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:lock.path)[.posixPermissions] as? NSNumber),attributes[.posixPermissions] as? NSNumber)
            XCTAssertEqual(try Data(contentsOf:outside),Data("preserve owned fixture".utf8));try rejected.close()
        }
    }
    func testInodeReplacementVetoesOldWriterAndOldCloseCannotUnlockReplacementOwner()async throws{
        let(_,directory,key)=try fixture(),first=HistoryStore(storage:HistoryVaultStorage(directory:directory,keys:key))
        try first.open(create:true);let record=try first.createRecord();try first.finish(record.id,outcome:.completed)
        let lock=directory.appendingPathComponent("owner.lock")
        try FileManager.default.removeItem(at:lock);try Data().write(to:lock);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:lock.path)
        let replacement=HistoryStore(storage:HistoryVaultStorage(directory:directory,keys:key));try replacement.open(create:false)
        let file=directory.appendingPathComponent("history.relayvault"),before=try Data(contentsOf:file)
        XCTAssertThrowsError(try first.edit(record.id,expectedRevision:2,title:"Retired inode",note:"Must not write"))
        XCTAssertEqual(try Data(contentsOf:file),before);try first.close()
        let stillOwned=try await probe(lock);XCTAssertEqual(stillOwned,17)
        try replacement.close();let released=try await probe(lock);XCTAssertEqual(released,0)
    }
    func testDirectoryReplacementCannotRedirectRetainedOwnerWrites()async throws{
        let(_,directory,key)=try fixture(),store=HistoryStore(storage:HistoryVaultStorage(directory:directory,keys:key))
        try store.open(create:true);let record=try store.createRecord()
        let moved=directory.deletingLastPathComponent().appendingPathComponent("History-old")
        try FileManager.default.moveItem(at:directory,to:moved)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let before=try Data(contentsOf:moved.appendingPathComponent("history.relayvault"))
        XCTAssertThrowsError(try store.edit(record.id,expectedRevision:1,title:"Wrong directory",note:"Must not redirect"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf:moved.appendingPathComponent("history.relayvault")),before);try store.close()
    }
    func testSharedDirectoriesAreNotPermissionHealedOrFollowedThroughSymlinks()async throws{
        for scenario in ["parent-mode","parent-link","history-link"]{
            let(root,directory,key)=try fixture(),parent=directory.deletingLastPathComponent(),outside=root.appendingPathComponent("fixture-target")
            try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            if scenario=="parent-link"{try FileManager.default.createSymbolicLink(at:parent,withDestinationURL:outside)}
            else{
                try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:false,attributes:[.posixPermissions:scenario=="parent-mode" ? 0o755:0o700])
                if scenario=="history-link"{try FileManager.default.createSymbolicLink(at:directory,withDestinationURL:outside)}
            }
            let store=HistoryStore(storage:HistoryVaultStorage(directory:directory,keys:key))
            XCTAssertThrowsError(try store.open(create:true),scenario);XCTAssertEqual(key.calls,0)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:outside.path).isEmpty)
            if scenario=="parent-mode"{XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:parent.path)[.posixPermissions] as? NSNumber)?.intValue,0o755)}
            try store.close()
        }
    }
    func testLockDuringActualAcquisitionJoinsLeaseWithoutStartingCancelledKeyRead()async throws{
        let(_,directory,key)=try fixture(),seed=HistoryStore(storage:HistoryVaultStorage(directory:directory,keys:key))
        try seed.open(create:true);try seed.close();let calls=key.calls
        let port=HeldHistoryBegin(HistoryVaultStorage(directory:directory,keys:key))
        let history=SessionHistoryCoordinator(storageFactory:{port},preferences:HistoryFixturePreferences(),canEnable:{true})
        addTeardownBlock{port.release();await history.waitForQuiescence()}
        let opening=Task{try await history.openExisting()};try await until{port.isHeld}
        history.lock();XCTAssertTrue(history.isBusy)
        let held=try await probe(directory.appendingPathComponent("owner.lock"));XCTAssertEqual(held,17)
        port.release();_=await opening.result;await history.waitForQuiescence()
        XCTAssertEqual(key.calls,calls,"A cancelled, unstarted snapshot load cannot read its key after acquisition returns")
        XCTAssertEqual(history.snapshot.phase,.locked)
        let released=try await probe(directory.appendingPathComponent("owner.lock"));XCTAssertEqual(released,0)
    }
    func testEarlierVaultWithoutLockNeedsExplicitEnableAndPreservesExistingCiphertext()async throws{
        let(_,directory,key)=try fixture(),earlier=HistoryStore(storage:ProtectedSnapshotVault(directory:directory,purpose:.history,keys:key))
        try earlier.open(create:true);try earlier.close()
        let file=directory.appendingPathComponent("history.relayvault"),before=try Data(contentsOf:file),calls=key.calls
        let owned=HistoryStore(storage:HistoryVaultStorage(directory:directory,keys:key))
        XCTAssertThrowsError(try owned.open(create:false))
        XCTAssertFalse(FileManager.default.fileExists(atPath:directory.appendingPathComponent("owner.lock").path));XCTAssertEqual(key.calls,calls)
        try owned.open(create:true)
        XCTAssertEqual(try Data(contentsOf:file),before);XCTAssertTrue(try owned.list().records.isEmpty)
        try owned.close()
    }
}
