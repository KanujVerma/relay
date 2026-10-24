import CryptoKit
import Foundation
import XCTest
@testable import RelaySessionPanel

final class HelperRuntimeResolverTests:XCTestCase {
    private func fixture()throws->URL {
        let app=FileManager.default.temporaryDirectory.appendingPathComponent("relay-runtime-"+UUID().uuidString).appendingPathComponent("Moved Relay.app")
        let runtime=app.appendingPathComponent("Contents/Helpers/RelayRuntime.app"),data=runtime.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at:data,withIntermediateDirectories:true)
        let executable=runtime.appendingPathComponent("Contents/MacOS/relay-helper")
        try FileManager.default.createDirectory(at:executable.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("synthetic executable".utf8).write(to:executable)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:executable.path)
        let paths=["EVALS/interview-questions.jsonl","EVALS/publication-policy-cases.jsonl","EVALS/technical-answer-gate.jsonl","EVALS/asr-intent-cases.jsonl","ROLE_PACKS/junior-data-analytics.md","ROLE_PACKS/epic-software-developer.md"]
        var resources:[[String:Any]]=[]
        for path in paths {
            let file=data.appendingPathComponent(path),bytes=Data("public synthetic resource".utf8)
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try bytes.write(to:file)
            resources.append(["path":path,"size":bytes.count,"sha256":SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()])
        }
        let manifest:[String:Any]=["schema":1,"python":"3.14.9","packager":"6.22.3","architecture":"arm64","resources":resources]
        try JSONSerialization.data(withJSONObject:manifest,options:[.sortedKeys]).write(to:data.appendingPathComponent("runtime-manifest.json"))
        return app
    }
    private func remove(_ app:URL){try? FileManager.default.removeItem(at:app.deletingLastPathComponent())}
    func testBundledLocationUsesItsOwnExecutableDataAndNoPythonPrefix()throws{
        let app=try fixture();defer{remove(app)}
        let value=try HelperRuntimeResolver.resolve(bundleURL:app,arguments:["Relay"],workingDirectory:URL(fileURLWithPath:"/"))
        XCTAssertEqual(value.executable,app.appendingPathComponent("Contents/Helpers/RelayRuntime.app/Contents/MacOS/relay-helper"))
        XCTAssertEqual(value.resourceRoot,app.appendingPathComponent("Contents/Helpers/RelayRuntime.app/Contents/Resources"));XCTAssertEqual(value.arguments,[])
    }
    func testBrokenAppNeverUsesWorkingDirectoryOrSystemPython()throws{
        let app=try fixture();defer{remove(app)}
        try FileManager.default.removeItem(at:app.appendingPathComponent("Contents/Helpers/RelayRuntime.app/Contents/MacOS/relay-helper"))
        XCTAssertThrowsError(try HelperRuntimeResolver.resolve(bundleURL:app,arguments:["Relay"],workingDirectory:URL(fileURLWithPath:FileManager.default.currentDirectoryPath)))
    }
    func testCorruptedResourceOrUnsafeManifestFailsClosed()throws{
        let app=try fixture();defer{remove(app)}
        let data=app.appendingPathComponent("Contents/Helpers/RelayRuntime.app/Contents/Resources")
        try Data("changed".utf8).write(to:data.appendingPathComponent("EVALS/interview-questions.jsonl"))
        XCTAssertThrowsError(try HelperRuntimeResolver.resolve(bundleURL:app,arguments:["Relay"],workingDirectory:URL(fileURLWithPath:"/")))
        try Data("{\"schema\":true}".utf8).write(to:data.appendingPathComponent("runtime-manifest.json"))
        XCTAssertThrowsError(try HelperRuntimeResolver.resolve(bundleURL:app,arguments:["Relay"],workingDirectory:URL(fileURLWithPath:"/")))
    }
    func testExplicitDevelopmentOverridesAndNonAppFixtureRetainTheirMeaning()throws{
        let directory=FileManager.default.temporaryDirectory
        let explicit=try HelperRuntimeResolver.resolve(bundleURL:URL(fileURLWithPath:"/broken/Relay.app"),arguments:["relay","--repository",directory.path,"--python","/usr/bin/python3"],workingDirectory:URL(fileURLWithPath:"/"))
        XCTAssertEqual(explicit.executable.path,"/usr/bin/python3");XCTAssertEqual(explicit.resourceRoot.path,directory.path);XCTAssertEqual(explicit.arguments,[])
        let fixture=try HelperRuntimeResolver.resolve(bundleURL:URL(fileURLWithPath:"/private/tmp/test.xctest"),arguments:["relay","--fixture-suite","coding","--repository",directory.path],workingDirectory:URL(fileURLWithPath:"/"))
        XCTAssertEqual(fixture.executable.path,"/usr/bin/env");XCTAssertEqual(fixture.arguments,["python3"])
    }
    func testBundledExecutableSymlinkCannotEscapeTheApp()throws{
        let app=try fixture();defer{remove(app)}
        let executable=app.appendingPathComponent("Contents/Helpers/RelayRuntime.app/Contents/MacOS/relay-helper")
        try FileManager.default.removeItem(at:executable)
        try FileManager.default.createSymbolicLink(at:executable,withDestinationURL:URL(fileURLWithPath:"/usr/bin/true"))
        XCTAssertThrowsError(try HelperRuntimeResolver.resolve(bundleURL:app,arguments:["Relay"],workingDirectory:URL(fileURLWithPath:"/")))
    }
    func testActualPackagedArtifactUsesItsVerifiedManifest()throws{
        guard let path=ProcessInfo.processInfo.environment["RELAY_TEST_PRODUCT_APP"] else{throw XCTSkip("actual product bundle is an explicit packaging gate")}
        let app=URL(fileURLWithPath:path,isDirectory:true)
        let value=try HelperRuntimeResolver.resolve(bundleURL:app,arguments:["Relay"],workingDirectory:URL(fileURLWithPath:"/"))
        XCTAssertEqual(value.executable.path,app.appendingPathComponent("Contents/Helpers/RelayRuntime.app/Contents/MacOS/relay-helper").path)
        XCTAssertEqual(value.arguments,[])
    }
}
