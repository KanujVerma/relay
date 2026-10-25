import Foundation
import Combine
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
private actor SpeechProgressProbe {
    private var update:(@Sendable(SpeechSetupProgress)->Void)?
    private var completion:CheckedContinuation<PreparedSpeechAssets,Never>?
    var entered:Bool{completion != nil}
    func prepare(_ update:@escaping @Sendable(SpeechSetupProgress)->Void)async->PreparedSpeechAssets{
        self.update=update;return await withCheckedContinuation{completion=$0}
    }
    func report(_ progress:SpeechSetupProgress){update?(progress)}
    func release(_ assets:PreparedSpeechAssets){completion?.resume(returning:assets);completion=nil}
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
    func testDelayedProgressCannotRegressValidationOrOverwriteCancelledIntent()async throws{
        let probe=SpeechProgressProbe(),setup=SpeechSetupCoordinator(prepare:{await probe.prepare($0)})
        let task=Task{try await setup.prepare()}
        try await waitUntil{await probe.entered}
        await probe.report(SpeechSetupProgress(.validating,completedBytes:15,totalBytes:15,sequence:2))
        try await waitUntil{setup.snapshot.stage == .validating}
        await probe.report(SpeechSetupProgress(.downloading,completedBytes:3,totalBytes:15,sequence:1))
        for _ in 0..<5{await Task.yield()}
        XCTAssertEqual(setup.snapshot.stage,.validating);XCTAssertEqual(setup.snapshot.completedBytes,15)
        setup.cancel()
        await probe.report(SpeechSetupProgress(.downloading,completedBytes:12,totalBytes:15,sequence:3))
        await probe.release(assets)
        do{_=try await task.value;XCTFail("cancelled progress authorized assets")}catch{}
        XCTAssertEqual(setup.snapshot.stage,.cancelled)
    }
    func testManagedCapturePolicyNeverPretendsToBeUserAcknowledgmentOrRecordingConsent()throws{
        let prepared=assets
        let valid=NativeCaptureConfiguration(microphoneEnabled:true,selectedBundleID:nil,preparedSpeechAssets:prepared,authorizedConversation:true)
        try valid.validate()
        XCTAssertEqual(valid.asrModelRoot,prepared.asrModelRoot);XCTAssertEqual(valid.vadCompiledModel,prepared.vadCompiledModel)
        XCTAssertFalse(valid.localModelLicensesAcknowledged,"managed dependency review is not a user attestation")
        XCTAssertThrowsError(try NativeCaptureConfiguration(microphoneEnabled:true,selectedBundleID:nil,preparedSpeechAssets:prepared,authorizedConversation:false).validate())
        XCTAssertThrowsError(try NativeCaptureConfiguration(microphoneEnabled:false,selectedBundleID:nil,preparedSpeechAssets:prepared,authorizedConversation:true).validate())
        XCTAssertThrowsError(try NativeCaptureConfiguration(microphoneEnabled:true,selectedBundleID:nil,asrModelRoot:prepared.asrModelRoot,vadCompiledModel:prepared.vadCompiledModel,authorizedConversation:true,localModelLicensesAcknowledged:false).validate())
    }
    func testCancelledObsoleteCoalescedWaiterCannotCancelReplacementPreparation()async throws{
        for _ in 0..<3 {
            let probe=SpeechPreparationProbe(),setup=SpeechSetupCoordinator(prepare:{_ in await probe.prepare()})
            var oldWaiter:Task<PreparedSpeechAssets,any Error>?
            var replacement:Task<PreparedSpeechAssets,any Error>?
            var launched=false
            let observer=setup.$snapshot.sink{snapshot in
                if snapshot.stage == .ready && !launched {
                    launched=true
                    replacement=Task(priority:.high){try await setup.prepare()}
                    oldWaiter?.cancel()
                }
            }
            let first=Task(priority:.high){try await setup.prepare()}
            oldWaiter=Task(priority:.background){try await setup.prepare()}
            try await waitUntil{await probe.calls==1}
            for _ in 0..<10{await Task.yield()}
            await probe.release(assets);_=await first.result
            try await waitUntil{await probe.calls==2}
            for _ in 0..<20{await Task.yield()}
            XCTAssertEqual(setup.snapshot.stage,.checking,"an obsolete waiter's delayed cancellation retired the new operation")
            XCTAssertTrue(setup.snapshot.isBusy)
            await probe.release(assets)
            switch await replacement?.result {
            case .success(let result):XCTAssertEqual(result,assets)
            default:XCTFail("replacement must complete after cancellation of only the obsolete waiter")
            }
            _=await oldWaiter?.result;await setup.waitForQuiescence()
            XCTAssertEqual(setup.snapshot.stage,.ready);XCTAssertFalse(setup.snapshot.isBusy)
            observer.cancel()
        }
    }
}
