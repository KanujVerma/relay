import Foundation
import XCTest
@testable import RelaySessionCapture

private actor SpeechPreparationProbe {
    private(set) var calls=0
    private var continuation:CheckedContinuation<PreparedSpeechAssets,Never>?
    func prepare()async->PreparedSpeechAssets {
        calls+=1
        return await withCheckedContinuation{continuation=$0}
    }
    func release(_ assets:PreparedSpeechAssets){continuation?.resume(returning:assets);continuation=nil}
}

@MainActor final class SpeechSetupTests:XCTestCase {
    private func waitUntil(_ predicate:()async->Bool)async throws{
        for _ in 0..<200{if await predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        XCTFail("synthetic speech preparation did not reach its boundary")
    }
    private var assets:PreparedSpeechAssets {
        PreparedSpeechAssets(manifestID:"synthetic-v1",asrModelRoot:URL(fileURLWithPath:"/private/tmp/synthetic-speech"),vadCompiledModel:URL(fileURLWithPath:"/private/tmp/synthetic-speech/vad.mlmodelc"))
    }
    func testConstructionIsInertAndConcurrentPreparationSharesOneOwnedOperation()async throws{
        let probe=SpeechPreparationProbe()
        let setup=SpeechSetupCoordinator(prepare:{_ in await probe.prepare()})
        XCTAssertEqual(setup.snapshot.stage,.notPrepared);XCTAssertFalse(setup.snapshot.isBusy)
        let initialCalls=await probe.calls;XCTAssertEqual(initialCalls,0)
        let first=Task{try await setup.prepare()},second=Task{try await setup.prepare()}
        try await waitUntil{await probe.calls==1}
        await probe.release(assets)
        let a=try await first.value,b=try await second.value
        XCTAssertEqual(a,b);XCTAssertEqual(setup.snapshot.stage,.ready);XCTAssertFalse(setup.snapshot.isBusy)
        let calls=await probe.calls;XCTAssertEqual(calls,1)
    }
    func testCancellationRetiresIntentButWaitsForActualPreparationBeforeBecomingAvailable()async throws{
        let probe=SpeechPreparationProbe()
        let setup=SpeechSetupCoordinator(prepare:{_ in await probe.prepare()})
        let preparing=Task{try await setup.prepare()}
        try await waitUntil{await probe.calls==1}
        setup.cancel()
        XCTAssertEqual(setup.snapshot.stage,.cancelled);XCTAssertTrue(setup.snapshot.isBusy)
        var quiesced=false
        let joining=Task{await setup.waitForQuiescence();quiesced=true}
        for _ in 0..<5{await Task.yield()}
        XCTAssertFalse(quiesced)
        await probe.release(assets)
        do{_=try await preparing.value;XCTFail("late cancelled assets were published")}catch{}
        await joining.value
        XCTAssertTrue(quiesced);XCTAssertFalse(setup.snapshot.isBusy);XCTAssertEqual(setup.snapshot.stage,.cancelled)
    }
    func testManifestUsesOnlyPinnedPublicURLsAndRejectsPathsOrHashesThatCannotBeValidated()throws{
        let manifest=SpeechAssetManifest.managedDefault
        XCTAssertEqual(manifest.artifacts.count,21);XCTAssertEqual(manifest.totalBytes,225_301_695)
        XCTAssertEqual(Set(manifest.artifacts.map{$0.url.host}),["huggingface.co"])
        XCTAssertFalse(manifest.artifacts.contains{$0.url.path.contains("/main/")})
        let item=manifest.artifacts[0]
        for path in ["../escape","/absolute","part/../escape","part//file","link%2fescape"] {
            XCTAssertThrowsError(try SpeechAssetManifest(id:"synthetic-v1",artifacts:[SpeechAssetArtifact(repository:item.repository,revision:item.revision,remotePath:item.remotePath,localPath:path,byteCount:1,sha256:item.sha256)]))
        }
        XCTAssertThrowsError(try SpeechAssetManifest(id:"synthetic-v1",artifacts:[SpeechAssetArtifact(repository:item.repository,revision:"main",remotePath:item.remotePath,localPath:"safe/file",byteCount:1,sha256:item.sha256)]))
        XCTAssertThrowsError(try SpeechAssetManifest(id:"synthetic-v1",artifacts:[SpeechAssetArtifact(repository:item.repository,revision:item.revision,remotePath:item.remotePath,localPath:"safe/file",byteCount:1,sha256:"bad")]))
    }
}
