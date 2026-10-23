import Foundation
import XCTest
@testable import RelaySessionCapture

private actor TinySpeechDownloader:SpeechAssetDownloading {
    private(set) var calls=0
    let bytes:Data
    init(_ bytes:Data=Data("abc".utf8)){self.bytes=bytes}
    func download(_ artifact:SpeechAssetArtifact,to destination:URL,deadline:UInt64,progress:@escaping @Sendable(UInt64)->Void)async throws{
        calls+=1;try Task.checkCancellation();try bytes.write(to:destination);progress(UInt64(bytes.count))
    }
}
private struct OfflineSpeechDownloader:SpeechAssetDownloading {
    func download(_ artifact:SpeechAssetArtifact,to destination:URL,deadline:UInt64,progress:@escaping @Sendable(UInt64)->Void)async throws{throw SpeechSetupError.offline}
}
private struct LateSpeechDownloader:SpeechAssetDownloading {
    func download(_ artifact:SpeechAssetArtifact,to destination:URL,deadline:UInt64,progress:@escaping @Sendable(UInt64)->Void)async throws{
        try await Task.sleep(for:.milliseconds(40));try Data("abc".utf8).write(to:destination)
    }
}
private actor HeldSpeechDownloader:SpeechAssetDownloading {
    private(set) var entered=false
    private(set) var calls=0,active=0,peak=0
    private var releases:[CheckedContinuation<Void,Never>]=[]
    private var released=false
    func download(_ artifact:SpeechAssetArtifact,to destination:URL,deadline:UInt64,progress:@escaping @Sendable(UInt64)->Void)async throws{
        try Task.checkCancellation();entered=true;calls+=1;active+=1;peak=max(peak,active)
        defer{active-=1}
        if !released{await withCheckedContinuation{releases.append($0)}}
        try Task.checkCancellation()
        try Data("abc".utf8).write(to:destination)
    }
    func finish(){released=true;let pending=releases;releases.removeAll();pending.forEach{$0.resume()}}
}

@MainActor final class SpeechAssetStoreTests:XCTestCase {
    private var directory:URL!
    override func setUpWithError()throws{
        directory=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("relay-speech-store-"+UUID().uuidString)
    }
    override func tearDownWithError()throws{if FileManager.default.fileExists(atPath:directory.path){try FileManager.default.removeItem(at:directory)}}
    private func manifest()throws->SpeechAssetManifest {
        let paths=["parakeet-eou-streaming/320ms/streaming_encoder.mlmodelc/weights/weight.bin","parakeet-eou-streaming/320ms/decoder.mlmodelc/model.mil","parakeet-eou-streaming/320ms/joint_decision.mlmodelc/model.mil","parakeet-eou-streaming/320ms/vocab.json",SpeechAssetManifest.vadDirectory+"/model.mil"]
        return try SpeechAssetManifest(id:"synthetic-v1",artifacts:paths.enumerated().map{index,path in
            SpeechAssetArtifact(repository:"FluidInference/silero-vad-coreml",revision:String(repeating:"a",count:40),remotePath:"fixture/file\(index)",localPath:path,byteCount:3,sha256:"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        })
    }
    private func store(space:UInt64=2*1024*1024*1024)throws->SpeechAssetStore{try SpeechAssetStore(directory:directory,manifest:manifest(),availableCapacity:{_ in space})}
    func testVerifiedCacheWorksOfflineAndNoCacheDirectoryIsCreatedByInspection()async throws{
        let store=try store();XCTAssertNil(try store.cachedAssets());XCTAssertFalse(FileManager.default.fileExists(atPath:directory.path))
        let first=try await store.prepare(using:TinySpeechDownloader(),progress:{_ in})
        let offline=try await store.prepare(using:OfflineSpeechDownloader(),progress:{_ in})
        XCTAssertEqual(first,offline)
        XCTAssertEqual(try Data(contentsOf:first.asrModelRoot.appendingPathComponent("parakeet-eou-streaming/320ms/vocab.json")),Data("abc".utf8))
        XCTAssertEqual(first.manifestID,"synthetic-v1");XCTAssertEqual(first.vadCompiledModel.lastPathComponent,SpeechAssetManifest.vadDirectory)
    }
    func testSameLengthCorruptFileCannotAuthorizeReadinessAndManagedRepairPublishesOnlyVerifiedBytes()async throws{
        let store=try store();let assets=try await store.prepare(using:TinySpeechDownloader(),progress:{_ in})
        let file=assets.asrModelRoot.appendingPathComponent("parakeet-eou-streaming/320ms/vocab.json")
        try Data("abd".utf8).write(to:file)
        XCTAssertNil(try store.cachedAssets())
        let repaired=try await store.prepare(using:TinySpeechDownloader(),progress:{_ in})
        XCTAssertEqual(try Data(contentsOf:repaired.asrModelRoot.appendingPathComponent("parakeet-eou-streaming/320ms/vocab.json")),Data("abc".utf8))
        XCTAssertNotNil(try store.cachedAssets())
    }
    func testShortOrHashMismatchedDownloadNeverPublishesAReadyCache()async throws{
        for data in [Data("ab".utf8),Data("abd".utf8)] {
            let store=try store()
            do{_=try await store.prepare(using:TinySpeechDownloader(data),progress:{_ in});XCTFail("invalid artifact accepted")}catch{}
            XCTAssertNil(try store.cachedAssets())
        }
    }
    func testSymlinkInManagedEntryIsRejectedWithoutFollowingOrChangingItsTarget()async throws{
        let store=try store();let assets=try await store.prepare(using:TinySpeechDownloader(),progress:{_ in})
        let file=assets.asrModelRoot.appendingPathComponent("parakeet-eou-streaming/320ms/vocab.json")
        let external=directory.appendingPathComponent("unrelated-synthetic.txt")
        try Data("abc".utf8).write(to:external);try FileManager.default.removeItem(at:file)
        try FileManager.default.createSymbolicLink(at:file,withDestinationURL:external)
        XCTAssertThrowsError(try store.cachedAssets())
        do{_=try await store.prepare(using:TinySpeechDownloader(),progress:{_ in});XCTFail("unsafe entry repaired through a symlink")}catch{}
        XCTAssertEqual(try Data(contentsOf:external),Data("abc".utf8))
    }
    func testInsufficientSpaceFailsBeforeArtifactDownload()async throws{
        let store=try store(space:100)
        do{_=try await store.prepare(using:TinySpeechDownloader(),progress:{_ in});XCTFail("storage bound ignored")}
        catch let error as SpeechSetupError{XCTAssertEqual(error,.insufficientStorage)}
        XCTAssertNil(try store.cachedAssets())
    }
    func testCancelledDownloadDoesNotPromoteItsStagingDirectory()async throws{
        let store=try store(),downloader=HeldSpeechDownloader()
        let preparing=Task{try await store.prepare(using:downloader,progress:{_ in})}
        for _ in 0..<100{if await downloader.entered{break};try await Task.sleep(for:.milliseconds(2))}
        preparing.cancel();await downloader.finish()
        do{_=try await preparing.value;XCTFail("cancelled tree promoted")}catch{}
        XCTAssertNil(try store.cachedAssets())
        let entries=(try? FileManager.default.contentsOfDirectory(atPath:directory.path)) ?? []
        XCTAssertFalse(entries.contains{$0.hasPrefix(".stage-")})
    }
    func testManagedCoordinatorReportsVerifiedSizeAndReusesItsReadyFilesWithoutNetwork()async throws{
        let store=try store(),setup=SpeechSetupCoordinator(store:store,downloader:TinySpeechDownloader())
        let prepared=try await setup.prepare()
        XCTAssertEqual(setup.snapshot.stage,.ready);XCTAssertEqual(setup.snapshot.completedBytes,15);XCTAssertEqual(setup.snapshot.totalBytes,15)
        let offline=SpeechSetupCoordinator(store:store,downloader:OfflineSpeechDownloader())
        let reused=try await offline.prepare()
        XCTAssertEqual(reused,prepared);XCTAssertEqual(offline.snapshot.stage,.ready);XCTAssertEqual(offline.snapshot.totalBytes,15)
    }
    func testSameRootPreparationsCoalesceUnderLockAndNeverExceedTwoActiveFiles()async throws{
        let store=try store(),downloader=HeldSpeechDownloader()
        let first=Task{try await store.prepare(using:downloader,progress:{_ in})}
        for _ in 0..<200{if await downloader.active==2{break};try await Task.sleep(for:.milliseconds(2))}
        let second=Task{try await store.prepare(using:downloader,progress:{_ in})}
        for _ in 0..<10{await Task.yield()}
        let inFlight=await downloader.calls;XCTAssertEqual(inFlight,2)
        await downloader.finish()
        let a=try await first.value,b=try await second.value
        let calls=await downloader.calls,peak=await downloader.peak
        XCTAssertEqual(a,b);XCTAssertEqual(calls,5);XCTAssertEqual(peak,2)
    }
    func testWaitingForAnotherCacheOwnerIsBoundedByTheSamePreparationDeadline()async throws{
        let store=try store(),downloader=HeldSpeechDownloader()
        let first=Task{try await store.prepare(using:downloader,progress:{_ in})}
        for _ in 0..<200{if await downloader.entered{break};try await Task.sleep(for:.milliseconds(2))}
        let bounded=try SpeechAssetStore(directory:directory,manifest:manifest(),preparationTimeoutNanoseconds:30_000_000)
        do{_=try await bounded.prepare(using:OfflineSpeechDownloader(),progress:{_ in});XCTFail("cache lock ignored preparation deadline")}
        catch let error as SpeechSetupError{XCTAssertEqual(error,.downloadUnavailable)}
        await downloader.finish();_=try await first.value
    }
    func testCancellationAtValidationBoundaryCannotPublishOrRetainStaging()async throws{
        let store=try store()
        let preparing=Task{try await store.prepare(using:TinySpeechDownloader(),progress:{progress in
            if progress.stage == .validating{withUnsafeCurrentTask{$0?.cancel()}}
        })}
        do{_=try await preparing.value;XCTFail("cancelled validation published assets")}catch is CancellationError{}
        XCTAssertNil(try store.cachedAssets())
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:directory.path).contains{$0.hasPrefix(".stage-")})
    }
    func testLateChildCompletionCannotPromoteAnExpiredPreparation()async throws{
        let store=try SpeechAssetStore(directory:directory,manifest:manifest(),preparationTimeoutNanoseconds:20_000_000)
        do{_=try await store.prepare(using:LateSpeechDownloader(),progress:{_ in});XCTFail("late child authorized expired setup")}
        catch let error as SpeechSetupError{XCTAssertEqual(error,.downloadUnavailable)}
        XCTAssertNil(try store.cachedAssets())
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:directory.path).contains{$0.hasPrefix(".stage-")})
    }
}
