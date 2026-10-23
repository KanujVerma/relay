import CryptoKit
import Darwin
import Foundation

private final class SpeechCacheLease:@unchecked Sendable {
    let descriptor:Int32
    init(_ descriptor:Int32){self.descriptor=descriptor}
    deinit{_ = flock(descriptor,LOCK_UN);_ = Darwin.close(descriptor)}
}

private final class SpeechByteProgress:@unchecked Sendable {
    private let lock=NSLock()
    private var counts:[UInt64]
    private let sizes:[UInt64]
    private var sequence:UInt64=0
    private let publish:@Sendable(SpeechSetupProgress)->Void
    init(artifacts:[SpeechAssetArtifact],publish:@escaping @Sendable(SpeechSetupProgress)->Void){
        sizes=artifacts.map(\.byteCount);counts=Array(repeating:0,count:artifacts.count);self.publish=publish
    }
    func update(_ bytes:UInt64,index:Int){
        let snapshot=lock.withLock{counts[index]=min(bytes,sizes[index]);sequence+=1;return SpeechSetupProgress(.downloading,completedBytes:counts.reduce(0,+),totalBytes:sizes.reduce(0,+),sequence:sequence)}
        publish(snapshot)
    }
    func validating(){
        let snapshot=lock.withLock{sequence+=1;return SpeechSetupProgress(.validating,completedBytes:sizes.reduce(0,+),totalBytes:sizes.reduce(0,+),sequence:sequence)}
        publish(snapshot)
    }
}

/// Owns only a named immutable manifest tree and UUID staging inside its root.
/// No model is loaded and no shared FluidAudio/user override cache is changed.
struct SpeechAssetStore:Sendable {
    let directory:URL
    let manifest:SpeechAssetManifest
    private let availableCapacity:@Sendable(URL)throws->UInt64
    private let preparationTimeoutNanoseconds:UInt64
    private static let marker=".verified-manifest"
    static var defaultDirectory:URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .resolvingSymlinksInPath().appendingPathComponent("Relay/Speech/v1")
    }
    init(directory:URL,manifest:SpeechAssetManifest = .managedDefault,
         preparationTimeoutNanoseconds:UInt64=900_000_000_000,
         availableCapacity:@escaping @Sendable(URL)throws->UInt64 = {url in
             var existing=url
             while !FileManager.default.fileExists(atPath:existing.path),existing.path != "/"{existing.deleteLastPathComponent()}
             let attrs=try FileManager.default.attributesOfFileSystem(forPath:existing.path)
             guard let bytes=attrs[.systemFreeSize] as? NSNumber else{throw SpeechSetupError.insufficientStorage}
             return bytes.uint64Value
         })throws{
        guard directory.isFileURL,directory.path != "/",!directory.pathComponents.contains(where:{$0=="." || $0==".."}) else{throw SpeechSetupError.unsafeCache}
        // Foundation may retain macOS's /var alias even after resolution.
        // Do not normalize any user-controlled managed child through symlinks.
        self.directory=directory;self.manifest=manifest;self.availableCapacity=availableCapacity
        self.preparationTimeoutNanoseconds=min(900_000_000_000,max(1,preparationTimeoutNanoseconds))
    }
    private var entry:URL{directory.appendingPathComponent(manifest.id)}
    private func kind(_ url:URL)throws->FileAttributeType?{
        var value=stat()
        if lstat(url.path,&value) != 0 {
            if errno==ENOENT{return nil};throw SpeechSetupError.unsafeCache
        }
        if value.st_mode&S_IFMT==S_IFLNK{return .typeSymbolicLink}
        if value.st_mode&S_IFMT==S_IFDIR{return .typeDirectory}
        if value.st_mode&S_IFMT==S_IFREG{return .typeRegular}
        return .typeUnknown
    }
    private func checkRoot()throws{
        var current=directory
        while current.path != "/" {
            if let type=try kind(current),type != .typeDirectory {
                // These OS-owned top-level aliases are returned by Foundation
                // itself. No arbitrary or managed-directory symlink is adopted.
                let expected=["/var":"private/var","/tmp":"private/tmp"]
                guard type == .typeSymbolicLink,let target=expected[current.path],
                      let actual=try? FileManager.default.destinationOfSymbolicLink(atPath:current.path),
                      actual==target || actual=="/"+target else{throw SpeechSetupError.unsafeCache}
            }
            current.deleteLastPathComponent()
        }
    }
    private func ensureRoot()throws{
        try checkRoot()
        do{try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])}
        catch{throw SpeechSetupError.unsafeCache}
        try checkRoot()
    }
    func cachedAssets()throws->PreparedSpeechAssets?{
        try checkRoot()
        guard let type=try kind(entry) else{return nil}
        guard type == .typeDirectory else{throw SpeechSetupError.unsafeCache}
        do{try validateTree(entry,requiresMarker:true);return assets(at:entry)}
        catch SpeechSetupError.invalidArtifacts{return nil}
    }
    private func assets(at root:URL)->PreparedSpeechAssets{
        PreparedSpeechAssets(manifestID:manifest.id,asrModelRoot:root,vadCompiledModel:root.appendingPathComponent(SpeechAssetManifest.vadDirectory),byteCount:manifest.totalBytes)
    }
    private func validateTree(_ root:URL,requiresMarker:Bool)throws{
        let expected=Set(manifest.artifacts.map(\.localPath))
        var directories=Set<String>()
        for path in expected {
            var parts=path.split(separator:"/").map(String.init);parts.removeLast()
            while !parts.isEmpty{directories.insert(parts.joined(separator:"/"));parts.removeLast()}
        }
        guard let iterator=FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil) else{throw SpeechSetupError.invalidArtifacts}
        guard let resolved=realpath(root.path,nil) else{throw SpeechSetupError.unsafeCache}
        let prefixes=[root.path+"/",String(cString:resolved)+"/"];free(resolved)
        for case let url as URL in iterator {
            try Task.checkCancellation()
            guard let prefix=prefixes.first(where:{url.path.hasPrefix($0)}) else{throw SpeechSetupError.unsafeCache}
            let relative=String(url.path.dropFirst(prefix.count))
            switch try kind(url){
            case .typeDirectory:guard directories.contains(relative) else{throw SpeechSetupError.invalidArtifacts}
            case .typeRegular:guard expected.contains(relative) || (requiresMarker && relative==Self.marker) else{throw SpeechSetupError.invalidArtifacts}
            default:throw SpeechSetupError.unsafeCache
            }
        }
        if requiresMarker {
            let marker=root.appendingPathComponent(Self.marker)
            let expectedMarker=Data((manifest.id+"\n").utf8)
            guard try kind(marker) == .typeRegular,
                  (try FileManager.default.attributesOfItem(atPath:marker.path)[.size] as? NSNumber)?.uint64Value==UInt64(expectedMarker.count),
                  (try? Data(contentsOf:marker))==expectedMarker else{throw SpeechSetupError.invalidArtifacts}
        }
        for artifact in manifest.artifacts{try validateFile(root.appendingPathComponent(artifact.localPath),artifact:artifact)}
    }
    private func validateFile(_ url:URL,artifact:SpeechAssetArtifact)throws{
        let fd=Darwin.open(url.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else{throw SpeechSetupError.invalidArtifacts}
        let file=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        defer{try? file.close()}
        var attrs=stat()
        guard fstat(fd,&attrs)==0,attrs.st_mode&S_IFMT==S_IFREG,attrs.st_size>=0,UInt64(attrs.st_size)==artifact.byteCount else{throw SpeechSetupError.invalidArtifacts}
        var hash=SHA256(),count:UInt64=0
        while let chunk=try file.read(upToCount:256*1024),!chunk.isEmpty {
            try Task.checkCancellation();count+=UInt64(chunk.count)
            guard count<=artifact.byteCount else{throw SpeechSetupError.invalidArtifacts};hash.update(data:chunk)
        }
        let digest=hash.finalize().map{String(format:"%02x",$0)}.joined()
        guard count==artifact.byteCount,digest==artifact.sha256 else{throw SpeechSetupError.invalidArtifacts}
    }
    private func lease(deadline:UInt64)async throws->SpeechCacheLease{
        try ensureRoot()
        let fd=Darwin.open(directory.appendingPathComponent(".preparation-lock").path,O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard fd>=0 else{throw SpeechSetupError.unsafeCache}
        let owned=SpeechCacheLease(fd)
        while true {
            try Task.checkCancellation()
            guard DispatchTime.now().uptimeNanoseconds<deadline else{throw SpeechSetupError.downloadUnavailable}
            if flock(fd,LOCK_EX|LOCK_NB)==0{break}
            guard errno==EWOULDBLOCK || errno==EAGAIN else{throw SpeechSetupError.unsafeCache}
            try Task.checkCancellation();try await Task.sleep(for:.milliseconds(10))
        }
        return owned
    }
    private func cleanAbandonedStaging()throws{
        for name in try FileManager.default.contentsOfDirectory(atPath:directory.path) {
            guard let prefix=[".stage-",".invalid-"].first(where:{name.hasPrefix($0)}),UUID(uuidString:String(name.dropFirst(prefix.count))) != nil else{continue}
            let url=directory.appendingPathComponent(name)
            guard try kind(url) == .typeDirectory else{throw SpeechSetupError.unsafeCache}
            try FileManager.default.removeItem(at:url)
        }
    }
    private func checkCurrent(deadline:UInt64)throws{
        try Task.checkCancellation()
        guard DispatchTime.now().uptimeNanoseconds<deadline else{throw SpeechSetupError.downloadUnavailable}
    }
    func prepare(using downloader:any SpeechAssetDownloading,progress:@escaping @Sendable(SpeechSetupProgress)->Void)async throws->PreparedSpeechAssets{
        try Task.checkCancellation()
        let deadline=DispatchTime.now().uptimeNanoseconds+preparationTimeoutNanoseconds
        let ownership=try await lease(deadline:deadline)
        return try await withExtendedLifetimeAsync(ownership){
            try cleanAbandonedStaging()
            progress(SpeechSetupProgress(.checking,totalBytes:manifest.totalBytes))
            if let cached=try cachedAssets(){try checkCurrent(deadline:deadline);return cached}
            guard try availableCapacity(directory)>=1_073_741_824 else{throw SpeechSetupError.insufficientStorage}
            let staging=directory.appendingPathComponent(".stage-"+UUID().uuidString)
            try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            do {
                for item in manifest.artifacts{try FileManager.default.createDirectory(at:staging.appendingPathComponent(item.localPath).deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])}
                let bytes=SpeechByteProgress(artifacts:manifest.artifacts,publish:progress)
                try await withThrowingTaskGroup(of:Void.self){group in
                    var next=0
                    func add(_ index:Int){group.addTask{
                        try Task.checkCancellation()
                        let item=manifest.artifacts[index],destination=staging.appendingPathComponent(item.localPath)
                        try await downloader.download(item,to:destination,deadline:deadline,progress:{bytes.update($0,index:index)})
                        try checkCurrent(deadline:deadline);try validateFile(destination,artifact:item);bytes.update(item.byteCount,index:index)
                    }}
                    for _ in 0..<min(2,manifest.artifacts.count){add(next);next+=1}
                    while try await group.next() != nil{if next<manifest.artifacts.count{add(next);next+=1}}
                }
                try checkCurrent(deadline:deadline);bytes.validating()
                try validateTree(staging,requiresMarker:false)
                try Data((manifest.id+"\n").utf8).write(to:staging.appendingPathComponent(Self.marker),options:.atomic)
                try checkCurrent(deadline:deadline)
                if let cached=try cachedAssets(){try FileManager.default.removeItem(at:staging);return cached}
                var previous:URL?
                if try kind(entry) != nil {
                    let old=directory.appendingPathComponent(".invalid-"+UUID().uuidString)
                    try FileManager.default.moveItem(at:entry,to:old);previous=old
                }
                do{try FileManager.default.moveItem(at:staging,to:entry)}catch{
                    if let previous{try FileManager.default.moveItem(at:previous,to:entry)}
                    throw error
                }
                if let previous{try FileManager.default.removeItem(at:previous)}
                return assets(at:entry)
            }catch{
                if FileManager.default.fileExists(atPath:staging.path){do{try FileManager.default.removeItem(at:staging)}catch{throw SpeechSetupError.unsafeCache}}
                throw error
            }
        }
    }
}

/// Keep the filesystem lock alive through all asynchronous child cleanup.
private func withExtendedLifetimeAsync<T>(_ owner:SpeechCacheLease,body:()async throws->T)async rethrows->T{
    defer{withExtendedLifetime(owner){}}
    return try await body()
}
