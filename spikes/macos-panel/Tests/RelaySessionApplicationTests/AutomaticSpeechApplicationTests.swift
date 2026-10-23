import Foundation
import XCTest
@testable import RelaySessionCapture
@testable import RelayPanelSession

private actor AutomaticSpeechCalls {
    private(set) var count=0
    func prepare()throws->PreparedSpeechAssets{count+=1;throw SpeechSetupError.downloadUnavailable}
}
private actor AutomaticSpeechGate {
    var entered=false
    private var completion:CheckedContinuation<PreparedSpeechAssets,Never>?
    func prepare()async->PreparedSpeechAssets{entered=true;return await withCheckedContinuation{completion=$0}}
    func release(){completion?.resume(returning:PreparedSpeechAssets(manifestID:"synthetic-v1",asrModelRoot:URL(fileURLWithPath:"/private/tmp/not-loaded"),vadCompiledModel:URL(fileURLWithPath:"/private/tmp/not-loaded/vad.mlmodelc")));completion=nil}
}
@MainActor final class AutomaticSpeechApplicationTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func waitUntil(_ predicate:()async->Bool)async throws{
        for _ in 0..<200{if await predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NSError(domain:"automatic speech did not reach its boundary",code:1)
    }
    private func launcher()throws->(URL,URL,URL){
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-speech-app-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let file=directory.appendingPathComponent("helper"),marker=directory.appendingPathComponent("started")
        let script="#!/usr/bin/env python3\nimport sys\nopen('\(marker.path)','w').close()\nsys.stdin.buffer.read()\n"
        try Data(script.utf8).write(to:file);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:file.path)
        return(directory,file,marker)
    }
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
    func testRecordingConsentIsCheckedBeforeDownloadOrHelperStartup()async throws{
        let (directory,file,marker)=try launcher();defer{try? FileManager.default.removeItem(at:directory)}
        let calls=AutomaticSpeechCalls(),setup=SpeechSetupCoordinator(prepare:{_ in try await calls.prepare()})
        let model=SessionApplicationModel(arguments:["relay","--repository",root.path,"--python",file.path],speechSetup:setup)
        await model.start();try await Task.sleep(for:.milliseconds(50))
        let count=await calls.count;XCTAssertEqual(count,0);XCTAssertFalse(FileManager.default.fileExists(atPath:marker.path))
        XCTAssertNotNil(model.error);XCTAssertFalse(model.running);XCTAssertFalse(model.starting)
        await model.stop()
    }
    func testUnavailablePreparationSurfacesItsRecoveryWithoutLaunchingHelperOrCapture()async throws{
        let (directory,file,marker)=try launcher();defer{try? FileManager.default.removeItem(at:directory)}
        let setup=SpeechSetupCoordinator(prepare:{_ in throw SpeechSetupError.offline})
        let model=SessionApplicationModel(arguments:["relay","--repository",root.path,"--python",file.path],speechSetup:setup)
        model.authorizedConversation=true
        await model.start();try await Task.sleep(for:.milliseconds(50))
        XCTAssertEqual(setup.snapshot.stage,.unavailable);XCTAssertEqual(setup.snapshot.recovery,.retry)
        XCTAssertEqual(model.error,setup.snapshot.userMessage);XCTAssertFalse(FileManager.default.fileExists(atPath:marker.path))
        XCTAssertFalse(model.running);XCTAssertFalse(model.starting);XCTAssertNil(model.currentSessionID)
        await model.stop()
    }
    func testCancelledStartWaitsForOwnedPreparationAndCannotStartFromLateAssets()async throws{
        let (directory,file,marker)=try launcher();defer{try? FileManager.default.removeItem(at:directory)}
        let gate=AutomaticSpeechGate(),setup=SpeechSetupCoordinator(prepare:{_ in await gate.prepare()})
        let model=SessionApplicationModel(arguments:["relay","--repository",root.path,"--python",file.path],speechSetup:setup)
        model.authorizedConversation=true
        let starting=Task{await model.start()}
        do{try await waitUntil{await gate.entered}}catch{await model.stop();throw error}
        model.cancelPreparation()
        XCTAssertEqual(setup.snapshot.stage,.cancelled);XCTAssertTrue(setup.snapshot.isBusy)
        XCTAssertTrue(model.stopping);XCTAssertFalse(model.canStartSession);XCTAssertFalse(model.paused)
        var ended=false
        let ending=Task{await model.stop();ended=true}
        for _ in 0..<5{await Task.yield()}
        XCTAssertFalse(ended)
        await gate.release();await starting.value;await ending.value
        XCTAssertFalse(model.running);XCTAssertFalse(model.starting);XCTAssertFalse(model.stopping);XCTAssertFalse(model.paused)
        XCTAssertFalse(FileManager.default.fileExists(atPath:marker.path));XCTAssertNil(model.currentSessionID)
    }
}
