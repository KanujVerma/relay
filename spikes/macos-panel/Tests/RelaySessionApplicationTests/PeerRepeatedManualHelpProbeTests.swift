import Foundation
import XCTest
import RelayAccount
import RelayNativeSession
import RelayProfile
@testable import RelayPanelSession

private struct PeerManualKey:ProfileKeyProvider {func key(createIfMissing:Bool)throws->Data{Data(repeating:93,count:32)}}
@MainActor private final class PeerManualContextPreferences:SessionContextUsePreferences{var useInSessions=false}
@MainActor final class PeerRepeatedManualHelpProbeTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func waitUntil(_ predicate:()->Bool)async throws{
        for _ in 0..<2500{if predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NSError(domain:"actual manual-help probe boundary not reached",code:1)
    }
    private func run(guided:Bool)async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-peer-manual-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer{try? FileManager.default.removeItem(at:directory)}
        let repository=root
        let ports=AccountApplicationPorts(storage:AccountStorage(sharedDirectory:directory.appendingPathComponent("Relay"),keys:PeerManualKey()),preferences:FixtureChatGPTPlanPreferences(),control:{runtime,bootstrap in
            PipeAccountPort(python:runtime.executable,repository:runtime.resourceRoot,bootstrap:bootstrap,pythonArguments:[repository.appendingPathComponent("tests/support/account_backend_helper.py").path,"--synthetic-account-test","--log",directory.appendingPathComponent("control.jsonl").path])
        },openBrowser:{_ in false},sessionArguments:{runtime,mode in
            mode == .protectedOAuth ? [repository.appendingPathComponent("tests/support/account_product_helper.py").path,"--synthetic-product-account-test","--log",directory.appendingPathComponent("requests.jsonl").path]:runtime.arguments
        })
        var audioSequences:[UInt64]=[],manualAnchors:[UInt64]=[],manualIDs:[UUID]=[]
        let model=SessionApplicationModel(arguments:["Relay","--fixture-suite","reviewed","--repository",root.path,"--python",try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"]),"--role","analytics"],ingressEnqueued:{ingress in
            switch ingress{case .audio(let event):audioSequences.append(event.eventSequence)
            case .manual(let request):manualAnchors.append(request.anchorEventSequence);manualIDs.append(request.requestID)}
        },contextPreferences:PeerManualContextPreferences(),responsePreferencesStorage:ApplicationPreferenceStorage(),responsePreferencesReceipts:ApplicationPreferenceReceipts(),accountPorts:ports)
        if guided{try await model.responsePreferences.useBuiltin(.coding)}
        await model.start()
        do {
            try await waitUntil{model.snapshot.card != nil}
            XCTAssertTrue(model.running);XCTAssertEqual(model.snapshot.question,"What is the difference between WHERE and HAVING?")
            let helper=try model.ensureHelper(),session=try XCTUnwrap(model.currentSessionID),anchor=try XCTUnwrap(audioSequences.last)
            XCTAssertNil(model.snapshot.responsePreferencesRevision,"Reviewed reference does not consume the guide")
            var completed=0
            for attempt in 1...12 {
                try await Task.sleep(for:.milliseconds(320))
                let replacement=model.snapshot.replacement
                try model.perform(.requestHelp)
                try await waitUntil{!model.running || (model.snapshot.replacement>replacement && model.snapshot.card != nil)}
                print("PEER manual",guided ? "coding":"general","attempt",attempt,"running",model.running,"card",model.snapshot.card != nil,"manualFrames",manualIDs.count,"audioAnchor",anchor,"lastAudio",audioSequences.last ?? 0,"status",model.snapshot.status)
                guard model.running,model.snapshot.card != nil else{break}
                completed+=1
                XCTAssertEqual(model.currentSessionID,session);XCTAssertTrue(try model.ensureHelper() === helper)
                XCTAssertEqual(audioSequences.last,anchor);XCTAssertEqual(manualAnchors.last,anchor)
            }
            XCTAssertEqual(Set(manualIDs).count,manualIDs.count,"Real issuer must stamp fresh manual UUIDs")
            XCTAssertEqual(completed,12,"A guide must not exhaust native records during ordinary repeated Help")
            XCTAssertTrue(model.running);XCTAssertNotNil(model.snapshot.card)
            XCTAssertEqual(model.currentSessionID,session);XCTAssertFalse(helper.hasExited)
            XCTAssertFalse(FileManager.default.fileExists(atPath:directory.appendingPathComponent("control.jsonl").path))
            await model.shutdown()
        }catch{await model.shutdown();throw error}
    }
    func testGeneralActualAudioTwelveManualHelpsControl()async throws{try await run(guided:false)}
    func testCodingActualAudioTwelveManualHelpsKeepsOriginalScope()async throws{try await run(guided:true)}
}
