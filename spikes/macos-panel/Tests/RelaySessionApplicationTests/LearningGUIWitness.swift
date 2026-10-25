import AppKit
import Darwin
import Foundation
import XCTest

private final class LearningWindowTail:@unchecked Sendable {
    private let lock=NSLock();private var bytes=Data()
    private let handle:FileHandle
    init(_ handle:FileHandle){self.handle=handle}
    func append(_ value:Data){lock.withLock{bytes.append(value);if bytes.count>65_536{bytes=Data(bytes.suffix(65_536))}}}
    var text:String{lock.withLock{String(decoding:bytes,as:UTF8.self)}}
    func drain(){while true{let data=handle.readData(ofLength:4096);if data.isEmpty{return};append(data)}}
}
private final class LearningWindowExited:@unchecked Sendable {
    private let lock=NSLock();private var value=false
    var finished:Bool{lock.withLock{value}}
    func finish(){lock.withLock{value=true}}
}

/// Isolates AppKit process/window lifecycle only. The actual original test body
/// executes inside the named child and must produce its complete XCTest result.
@MainActor enum LearningGUIWitness {
    static func run(caseClass:XCTestCase.Type,method:String)async throws->Bool{
        let key="RELAY_LEARNING_WINDOW_CHILD",environment=ProcessInfo.processInfo.environment
        let marker="LEARNING_WINDOW_CHILD_STARTED "+method
        if environment[key]==method{FileHandle.standardError.write(Data((marker+"\n").utf8));return false}
        guard environment[key]==nil else{XCTFail("Unexpected owned window-test child selection");return true}
        let foreground=NSWorkspace.shared.frontmostApplication
        let child=Process(),exited=LearningWindowExited(),pipe=Pipe()
        let tail=LearningWindowTail(pipe.fileHandleForReading)
        let python=try XCTUnwrap(environment["RELAY_TEST_PYTHON"])
        child.executableURL=URL(fileURLWithPath:python)
        // Isolate this test host's group. A completed named suite also requires
        // Model teardown to join its independently owned helper transports; do
        // not assume Foundation places every helper in the host's group.
        child.arguments=["-c","import os,sys\nif os.getpgrp()!=os.getpid(): os.setsid()\nif os.getpgrp()!=os.getpid(): raise RuntimeError('Owned test host group is not isolated')\nos.execv('/usr/bin/xcrun', ['xcrun','xctest',*sys.argv[1:]])",
            "-XCTest","RelaySessionApplicationTests.LearningApplicationTests/"+method,Bundle(for:caseClass).bundleURL.path]
        var values=environment;values[key]=method;child.environment=values
        child.standardOutput=pipe;child.standardError=pipe;child.terminationHandler={_ in exited.finish()}
        try child.run();try pipe.fileHandleForWriting.close()
        let reader=Task.detached(priority:.utility){tail.drain()}
        let group=child.processIdentifier,deadline=ContinuousClock.now+Duration.seconds(20)
        while !exited.finished,ContinuousClock.now<deadline{try? await Task.sleep(for:.milliseconds(5))}
        let timedOut = !exited.finished
        if timedOut{_=Darwin.kill(-group,SIGTERM)}
        for _ in 0..<200{if exited.finished{break};try? await Task.sleep(for:.milliseconds(5))}
        if !exited.finished{_=Darwin.kill(-group,SIGKILL)}
        while !exited.finished{try? await Task.sleep(for:.milliseconds(2))}
        // A premature host exit is a failure even if its helpers are still alive.
        if Darwin.kill(-group,0)==0{
            _=Darwin.kill(-group,SIGTERM)
            for _ in 0..<200{if Darwin.kill(-group,0) != 0{break};try? await Task.sleep(for:.milliseconds(5))}
            if Darwin.kill(-group,0)==0{_=Darwin.kill(-group,SIGKILL)}
        }
        await reader.value;try? pipe.fileHandleForReading.close()
        if let foreground,!foreground.isTerminated{
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != foreground.processIdentifier{_=foreground.activate(options:[])}
            for _ in 0..<50{if NSWorkspace.shared.frontmostApplication?.processIdentifier==foreground.processIdentifier{break};try? await Task.sleep(for:.milliseconds(10))}
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier,foreground.processIdentifier)
        }
        let output=tail.text
        let complete=output.contains(marker) && output.contains(method+"]' passed") && output.contains("Executed 1 test, with 0 failures")
        XCTAssertFalse(timedOut,"Owned window-test child exceeded its deadline")
        XCTAssertTrue(child.terminationStatus==0 && complete,"Owned window-test did not finish its named case and one-case suite.\n"+output)
        return true
    }
}
