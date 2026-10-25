import Foundation
import XCTest
@testable import RelaySessionCapture

private actor RetainedSpeechNoDownload:SpeechAssetDownloading {
    private(set) var attempts=0
    func download(_ artifact:SpeechAssetArtifact,to destination:URL,deadline:UInt64,
                  progress:@escaping @Sendable(UInt64)->Void)async throws {
        attempts+=1
        throw SpeechSetupError.downloadUnavailable
    }
}

@MainActor final class RetainedManagedSpeechAssetsTests:XCTestCase {
    func testOptInExistingPublicModelsPrepareAtNormalLocationWithoutDownloadOrModelLoad()async throws {
        guard ProcessInfo.processInfo.environment["RELAY_TEST_EXISTING_MANAGED_SPEECH_CACHE"]=="1" else {
            throw XCTSkip("Explicit retained public model installation acceptance; no model load or download.")
        }
        let store=try SpeechAssetStore(directory:SpeechAssetStore.defaultDirectory)
        let cached=try XCTUnwrap(store.cachedAssets())
        XCTAssertEqual(cached.manifestID,SpeechAssetManifest.managedDefault.id)
        XCTAssertEqual(cached.byteCount,225_301_695)
        XCTAssertEqual(cached.asrModelRoot,SpeechAssetStore.defaultDirectory.appendingPathComponent(cached.manifestID))
        let downloader=RetainedSpeechNoDownload()
        let coordinator=SpeechSetupCoordinator(store:store,downloader:downloader)
        let prepared=try await coordinator.prepare()
        XCTAssertEqual(prepared,cached)
        XCTAssertEqual(coordinator.snapshot.stage,.ready)
        let attempts=await downloader.attempts
        XCTAssertEqual(attempts,0)
        await coordinator.waitForQuiescence()
        XCTAssertEqual(try store.cachedAssets(),cached)
    }
}
