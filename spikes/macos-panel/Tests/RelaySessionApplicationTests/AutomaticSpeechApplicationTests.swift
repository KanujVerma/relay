import Foundation
import XCTest
@testable import RelaySessionCapture
@testable import RelayPanelSession

private actor AutomaticSpeechCalls {
    private(set) var count=0
    func prepare()throws->PreparedSpeechAssets{count+=1;throw SpeechSetupError.downloadUnavailable}
}
@MainActor final class AutomaticSpeechApplicationTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    func testModelConstructionAndFixtureStartDoNotProvisionOrLoadSpeech()async throws{
        let calls=AutomaticSpeechCalls()
        let setup=SpeechSetupCoordinator(prepare:{_ in try await calls.prepare()})
        let model=SessionApplicationModel(arguments:["relay","--fixture-suite","coding","--repository",root.path],speechSetup:setup)
        XCTAssertTrue(model.speechSetup === setup)
        XCTAssertEqual(setup.snapshot.stage,.notPrepared)
        await model.start()
        XCTAssertTrue(model.running)
        let count=await calls.count;XCTAssertEqual(count,0)
        await model.stop()
        XCTAssertFalse(setup.snapshot.isBusy)
    }
}
