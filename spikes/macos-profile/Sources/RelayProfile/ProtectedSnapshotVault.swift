import CryptoKit
import Foundation

/// A real storage receipt is the return from these synchronous calls. A caller
/// cancelling its async waiter must still join any call already in progress.
public protocol ProtectedSnapshotStorage:Sendable {
    func exists()throws->Bool
    func load()throws->Data
    func save(_ payload:Data,createKey:Bool)throws
}
public enum ProtectedSnapshotPurpose:Sendable {
    case profile,history,responsePreferences
    fileprivate var filename:String{switch self{case .profile:"profile.relayvault";case .history:"history.relayvault";case .responsePreferences:"preferences.relayvault"}}
    fileprivate var header:Data{Data(headerText.utf8)}
    private var headerText:String{switch self{case .profile:"RELAYPROFILE1\n";case .history:"RELAYHISTORY1\n";case .responsePreferences:"RELAYPREFERENCES1\n"}}
}

/// Whole-payload authenticated encryption, with ciphertext-only atomic files.
/// Construction is inert. No secure erase, backup removal or same-user process
/// isolation is promised. Keys and directories must be explicitly scoped by the
/// native owner; the history format never reuses the profile header/key.
public final class ProtectedSnapshotVault:ProtectedSnapshotStorage,@unchecked Sendable {
    public static let maxPayloadBytes=8*1024*1024
    private let directory:URL
    private let purpose:ProtectedSnapshotPurpose
    private let keys:any ProfileKeyProvider
    private let lock=NSLock()
    public init(directory:URL,purpose:ProtectedSnapshotPurpose,keys:any ProfileKeyProvider){
        self.directory=directory;self.purpose=purpose;self.keys=keys
    }
    private var file:URL{directory.appendingPathComponent(purpose.filename)}

    public func exists()throws->Bool{
        lock.lock();defer{lock.unlock()}
        guard FileManager.default.fileExists(atPath:directory.path) else{return false}
        try checkDirectory(create:false)
        guard FileManager.default.fileExists(atPath:file.path) else{return false}
        try checkFile();return true
    }
    private func checkOneDirectory(_ url:URL,create:Bool,recursive:Bool)throws{
        let manager=FileManager.default
        if !manager.fileExists(atPath:url.path),create{
            try manager.createDirectory(at:url,withIntermediateDirectories:recursive,attributes:[.posixPermissions:0o700])
        }
        let a=try manager.attributesOfItem(atPath:url.path)
        guard a[.type] as? FileAttributeType == .typeDirectory,
              (a[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (a[.posixPermissions] as? NSNumber)?.intValue == 0o700
        else{throw ProfileError.invalidLocation}
    }
    private func checkDirectory(create:Bool)throws{
        if purpose != .profile{
            // Shared Relay0700 may already belong to profile/account storage.
            // History and response preferences use fixed sibling directories.
            // Never recursively manufacture or permission-heal its ancestry.
            try checkOneDirectory(directory.deletingLastPathComponent(),create:create,recursive:false)
            try checkOneDirectory(directory,create:create,recursive:false)
        }else{
            // Preserve the original ProfileVault directory behavior/API.
            try checkOneDirectory(directory,create:create,recursive:true)
        }
    }
    private func checkFile()throws{
        let a=try FileManager.default.attributesOfItem(atPath:file.path)
        guard a[.type] as? FileAttributeType == .typeRegular,
              (a[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (a[.referenceCount] as? NSNumber)?.intValue == 1,
              (a[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              let size=a[.size] as? NSNumber,size.intValue<=Self.maxPayloadBytes+128
        else{throw ProfileError.invalidLocation}
    }
    public func load()throws->Data{
        lock.lock();defer{lock.unlock()}
        try checkDirectory(create:false);try checkFile()
        let encrypted=try Data(contentsOf:file),header=purpose.header
        guard encrypted.starts(with:header) else{throw ProfileError.corruptVault}
        let rawKey=try keys.key(createIfMissing:false)
        guard rawKey.count==32 else{throw ProfileError.invalidKey}
        do{
            let box=try AES.GCM.SealedBox(combined:encrypted.dropFirst(header.count))
            let payload=try AES.GCM.open(box,using:SymmetricKey(data:rawKey),authenticating:header)
            guard !payload.isEmpty,payload.count<=Self.maxPayloadBytes else{throw ProfileError.invalidPayload}
            return payload
        }catch{throw ProfileError.corruptVault}
    }
    public func save(_ payload:Data,createKey:Bool=false)throws{
        lock.lock();defer{lock.unlock()}
        guard !payload.isEmpty,payload.count<=Self.maxPayloadBytes else{throw ProfileError.invalidPayload}
        try checkDirectory(create:true)
        if FileManager.default.fileExists(atPath:file.path){
            guard !createKey else{throw ProfileError.invalidLocation};try checkFile()
        }else if !createKey{throw ProfileError.invalidLocation}
        let rawKey=try keys.key(createIfMissing:createKey)
        guard rawKey.count==32 else{throw ProfileError.invalidKey}
        let box=try AES.GCM.seal(payload,using:SymmetricKey(data:rawKey),authenticating:purpose.header)
        guard let combined=box.combined else{throw ProfileError.invalidPayload}
        try (purpose.header+combined).write(to:file,options:[.atomic])
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
}
