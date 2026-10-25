import CryptoKit
import Foundation

public struct HelperRuntimeLocation:Sendable,Equatable {
    public let executable:URL
    public let arguments:[String]
    public let resourceRoot:URL
}

public enum HelperRuntimeError:Error,Sendable,Equatable,LocalizedError {
    case bundledRuntimeUnavailable,invalidBundledRuntime,developerOverrideInvalid
    public var errorDescription:String? {
        switch self {
        case .bundledRuntimeUnavailable:"Relay's bundled runtime is missing. Reinstall the complete app."
        case .invalidBundledRuntime:"Relay's bundled runtime could not be verified. Reinstall the complete app."
        case .developerOverrideInvalid:"The explicit developer runtime paths are incomplete or unavailable."
        }
    }
}

/// Packaged launches resolve their own immutable runtime. Only an explicit
/// developer override or a non-app tool can select external Python/repository.
public enum HelperRuntimeResolver {
    private static let resourcePaths:Set<String>=[
        "EVALS/interview-questions.jsonl","EVALS/publication-policy-cases.jsonl",
        "EVALS/technical-answer-gate.jsonl","EVALS/asr-intent-cases.jsonl",
        "ROLE_PACKS/junior-data-analytics.md","ROLE_PACKS/epic-software-developer.md"
    ]
    public static func resolve(bundleURL:URL,arguments:[String],workingDirectory:URL)throws->HelperRuntimeLocation {
        let repository=try option("--repository",arguments),python=try option("--python",arguments)
        if repository != nil || python != nil || bundleURL.pathExtension.lowercased() != "app" {
            let root=repository.map{URL(fileURLWithPath:$0,isDirectory:true)} ?? workingDirectory
            var isDirectory:ObjCBool=false
            guard root.isFileURL,FileManager.default.fileExists(atPath:root.path,isDirectory:&isDirectory),isDirectory.boolValue else{throw HelperRuntimeError.developerOverrideInvalid}
            return HelperRuntimeLocation(executable:URL(fileURLWithPath:python ?? "/usr/bin/env"),arguments:python==nil ? ["python3"]:[],resourceRoot:root)
        }
        let runtime=bundleURL.appendingPathComponent("Contents/Helpers/RelayRuntime.app",isDirectory:true)
        let executable=runtime.appendingPathComponent("Contents/MacOS/relay-helper"),data=runtime.appendingPathComponent("Contents/Resources",isDirectory:true)
        guard FileManager.default.isExecutableFile(atPath:executable.path),FileManager.default.fileExists(atPath:data.path) else{throw HelperRuntimeError.bundledRuntimeUnavailable}
        do {
            try requireContained(executable,in:bundleURL);try requireContained(data,in:bundleURL)
            let manifest=try boundedData(data.appendingPathComponent("runtime-manifest.json"),within:bundleURL,limit:16_384)
            let fields=try StrictJSON.decode(manifest).object(["schema","python","packager","architecture","resources"])
            guard try fields["schema"]!.uint()==1,try fields["python"]!.string(32)=="3.14.9",
                  try fields["packager"]!.string(32)=="6.22.3",try fields["architecture"]!.string(32)=="arm64" else{throw HelperRuntimeError.invalidBundledRuntime}
            let resources=try fields["resources"]!.array(6)
            var seen=Set<String>(),total:UInt64=0
            for item in resources {
                let resource=try item.object(["path","size","sha256"]),path=try resource["path"]!.string(128)
                let size=try resource["size"]!.uint(),digest=try resource["sha256"]!.string(64)
                guard resourcePaths.contains(path),seen.insert(path).inserted,size<=131_072,
                      digest.utf8.count==64,digest.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else{throw HelperRuntimeError.invalidBundledRuntime}
                total+=size;guard total<=262_144 else{throw HelperRuntimeError.invalidBundledRuntime}
                let bytes=try boundedData(data.appendingPathComponent(path),within:bundleURL,limit:Int(size))
                guard bytes.count==size,SHA256.hash(data:bytes).map({String(format:"%02x",$0)}).joined()==digest else{throw HelperRuntimeError.invalidBundledRuntime}
            }
            guard seen==resourcePaths else{throw HelperRuntimeError.invalidBundledRuntime}
            return HelperRuntimeLocation(executable:executable,arguments:[],resourceRoot:data)
        }catch{throw HelperRuntimeError.invalidBundledRuntime}
    }
    private static func option(_ key:String,_ arguments:[String])throws->String? {
        let indices=arguments.indices.filter{arguments[$0]==key}
        guard indices.count<=1 else{throw HelperRuntimeError.developerOverrideInvalid}
        guard let index=indices.first else{return nil}
        guard arguments.indices.contains(index+1),!arguments[index+1].isEmpty,!arguments[index+1].hasPrefix("--") else{throw HelperRuntimeError.developerOverrideInvalid}
        return arguments[index+1]
    }
    private static func requireContained(_ url:URL,in bundle:URL)throws {
        let root=bundle.resolvingSymlinksInPath().path+"/",path=url.resolvingSymlinksInPath().path
        guard path.hasPrefix(root) else{throw HelperRuntimeError.invalidBundledRuntime}
    }
    private static func boundedData(_ url:URL,within bundle:URL,limit:Int)throws->Data {
        try requireContained(url,in:bundle)
        let values=try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
        guard values.isRegularFile==true,let count=values.fileSize,count>0,count<=limit else{throw HelperRuntimeError.invalidBundledRuntime}
        let data=try Data(contentsOf:url)
        guard data.count==count else{throw HelperRuntimeError.invalidBundledRuntime};return data
    }
}
