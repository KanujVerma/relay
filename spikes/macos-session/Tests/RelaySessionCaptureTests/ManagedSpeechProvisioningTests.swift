import Foundation
import XCTest
@testable import RelaySessionCapture

/// Explicit public-asset provisioning proof only. Ordinary tests/CI never
/// fetch weights or load models; an isolated /private/tmp cache is mandatory.
@MainActor final class ManagedSpeechProvisioningTests:XCTestCase {
    func testPinnedPublicAssetsProvisionAndThenVerifyOfflineWithoutLoadingModels()async throws{
        let environment=ProcessInfo.processInfo.environment
        guard environment["RELAY_TEST_SPEECH_DOWNLOAD"]=="1" else{throw XCTSkip("225 MB public asset download is opt-in")}
        let path=try XCTUnwrap(environment["RELAY_TEST_SPEECH_CACHE"])
        guard path.hasPrefix("/private/tmp/relay-auto-speech-") else{throw SpeechSetupError.unsafeCache}
        let store=try SpeechAssetStore(directory:URL(fileURLWithPath:path))
        let prepared=try await store.prepare(using:SpeechAssetDownloader(),progress:{_ in})
        XCTAssertEqual(prepared.byteCount,225_301_695)
        try NativeCaptureConfiguration(microphoneEnabled:true,selectedBundleID:nil,preparedSpeechAssets:prepared,authorizedConversation:true).validateLocalModels()
        let reused=try await store.prepare(using:ProvisioningOfflineTransport(),progress:{_ in})
        XCTAssertEqual(reused,prepared);XCTAssertEqual(try store.cachedAssets(),prepared)
    }
}
private struct ProvisioningOfflineTransport:SpeechAssetDownloading {
    func download(_ artifact:SpeechAssetArtifact,to destination:URL,deadline:UInt64,progress:@escaping @Sendable(UInt64)->Void)async throws{
        XCTFail("verified warm cache attempted network");throw SpeechSetupError.offline
    }
}
