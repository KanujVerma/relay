import Foundation
import XCTest
@testable import RelaySessionCapture

private final class SpeechHTTPProtocol:URLProtocol,@unchecked Sendable {
    struct Reply:Sendable {let status:Int;let body:Data;var type="application/octet-stream";var hold=false}
    private static let lock=NSLock()
    nonisolated(unsafe) private static var replies:[Reply]=[]
    nonisolated(unsafe) private static var recorded:[URLRequest]=[]
    nonisolated(unsafe) private static var stops=0
    static func reset(_ values:[Reply]){lock.withLock{replies=values;recorded=[];stops=0}}
    static var requests:[URLRequest]{lock.withLock{recorded}}
    static var stopCount:Int{lock.withLock{stops}}
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){
        let reply=Self.lock.withLock{Self.recorded.append(request);return Self.replies.isEmpty ? Reply(status:404,body:Data()):Self.replies.removeFirst()}
        let response=HTTPURLResponse(url:request.url!,statusCode:reply.status,httpVersion:"HTTP/1.1",headerFields:["Content-Type":reply.type,"Content-Length":String(reply.body.count)])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        if !reply.hold{client?.urlProtocol(self,didLoad:reply.body);client?.urlProtocolDidFinishLoading(self)}
    }
    override func stopLoading(){Self.lock.withLock{Self.stops+=1}}
}
private final class SpeechObservedBytes:@unchecked Sendable {
    private let lock=NSLock();private var values:[UInt64]=[]
    func append(_ value:UInt64){lock.withLock{values.append(value)}}
    var all:[UInt64]{lock.withLock{values}}
}
@MainActor final class SpeechAssetDownloaderTests:XCTestCase {
    private var directory:URL!
    override func setUpWithError()throws{directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-model-http-"+UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)}
    override func tearDownWithError()throws{try FileManager.default.removeItem(at:directory);SpeechHTTPProtocol.reset([])}
    private var artifact:SpeechAssetArtifact{SpeechAssetArtifact(repository:"FluidInference/silero-vad-coreml",revision:String(repeating:"a",count:40),remotePath:"model/weight.bin",localPath:"model/weight.bin",byteCount:3,sha256:"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")}
    private func downloader()->SpeechAssetDownloader {
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[SpeechHTTPProtocol.self]
        config.httpAdditionalHeaders=["Authorization":"synthetic-credential-must-not-leave","Cookie":"synthetic-cookie"]
        return SpeechAssetDownloader(configuration:config,sleep:{_ in})
    }
    private var deadline:UInt64{DispatchTime.now().uptimeNanoseconds+2_000_000_000}
    func testDownloadUsesExactPublicPinnedURLWithoutAmbientCredentialsAndStreamsToFile()async throws{
        SpeechHTTPProtocol.reset([.init(status:200,body:Data("abc".utf8))]);let bytes=SpeechObservedBytes(),file=directory.appendingPathComponent("asset")
        try await downloader().download(artifact,to:file,deadline:deadline,progress:bytes.append)
        XCTAssertEqual(try Data(contentsOf:file),Data("abc".utf8))
        let request=try XCTUnwrap(SpeechHTTPProtocol.requests.first)
        XCTAssertEqual(request.url,artifact.url);XCTAssertNil(request.value(forHTTPHeaderField:"Authorization"));XCTAssertNil(request.value(forHTTPHeaderField:"Cookie"))
        XCTAssertTrue(bytes.all.allSatisfy{$0<=3})
        XCTAssertEqual(bytes.all.last,3)
    }
    func testTransientFailureRetriesWithinBudgetButPermanentOrInvalidArtifactsDoNot()async throws{
        for reply in [SpeechHTTPProtocol.Reply(status:404,body:Data()),.init(status:200,body:Data("ab".utf8)),.init(status:200,body:Data("abcd".utf8)),.init(status:200,body:Data("abc".utf8),type:"text/html")] {
            SpeechHTTPProtocol.reset([reply]);let file=directory.appendingPathComponent(UUID().uuidString)
            do{try await downloader().download(artifact,to:file,deadline:deadline,progress:{_ in});XCTFail("invalid response accepted")}catch{}
            XCTAssertFalse(FileManager.default.fileExists(atPath:file.path));XCTAssertEqual(SpeechHTTPProtocol.requests.count,1)
        }
        SpeechHTTPProtocol.reset([.init(status:503,body:Data()),.init(status:200,body:Data("abc".utf8))])
        let file=directory.appendingPathComponent("retried")
        try await downloader().download(artifact,to:file,deadline:deadline,progress:{_ in})
        XCTAssertEqual(try Data(contentsOf:file),Data("abc".utf8));XCTAssertEqual(SpeechHTTPProtocol.requests.count,2)
        SpeechHTTPProtocol.reset(Array(repeating:.init(status:503,body:Data()),count:5))
        do{try await downloader().download(artifact,to:directory.appendingPathComponent("failed"),deadline:DispatchTime.now().uptimeNanoseconds+10_000_000_000,progress:{_ in});XCTFail("retry budget ignored")}catch{}
        XCTAssertEqual(SpeechHTTPProtocol.requests.count,3)
    }
    func testPreCancelledOrExpiredActionNeverStartsAURLTask()async throws{
        SpeechHTTPProtocol.reset([.init(status:200,body:Data("abc".utf8))])
        let transport=downloader(),file=directory.appendingPathComponent("not-started"),item=artifact
        let task=Task{
            while !Task.isCancelled{await Task.yield()}
            try await transport.download(item,to:file,deadline:DispatchTime.now().uptimeNanoseconds+1_000_000_000,progress:{_ in})
        }
        task.cancel();do{try await task.value;XCTFail("cancelled request started")}catch{}
        do{try await transport.download(item,to:file,deadline:0,progress:{_ in});XCTFail("expired request started")}catch{}
        XCTAssertTrue(SpeechHTTPProtocol.requests.isEmpty);XCTAssertFalse(FileManager.default.fileExists(atPath:file.path))
    }
    func testCancellationWaitsForActualURLTaskCompletionAndLeavesNoArtifact()async throws{
        SpeechHTTPProtocol.reset([.init(status:200,body:Data("abc".utf8),hold:true)])
        let transport=downloader(),file=directory.appendingPathComponent("cancelled"),item=artifact,limit=deadline
        let task=Task{try await transport.download(item,to:file,deadline:limit,progress:{_ in})}
        for _ in 0..<200 where SpeechHTTPProtocol.requests.isEmpty{try await Task.sleep(for:.milliseconds(2))}
        XCTAssertEqual(SpeechHTTPProtocol.requests.count,1);task.cancel()
        do{try await task.value;XCTFail("cancelled response completed")}catch{}
        XCTAssertGreaterThan(SpeechHTTPProtocol.stopCount,0);XCTAssertFalse(FileManager.default.fileExists(atPath:file.path))
    }
    func testTransientErrorPageLargerThanAnArtifactStillUsesTheFiniteRetryPolicy()async throws{
        SpeechHTTPProtocol.reset([.init(status:503,body:Data(repeating:65,count:4096),type:"text/html"),.init(status:200,body:Data("abc".utf8))])
        let file=directory.appendingPathComponent("after-error-page")
        try await downloader().download(artifact,to:file,deadline:deadline,progress:{_ in})
        XCTAssertEqual(SpeechHTTPProtocol.requests.count,2);XCTAssertEqual(try Data(contentsOf:file),Data("abc".utf8))
    }
}
