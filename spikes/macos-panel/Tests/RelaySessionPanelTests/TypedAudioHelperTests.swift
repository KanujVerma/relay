import Darwin
import Foundation
import XCTest
import RelayNativeSession
import RelayContextComposition
import RelayAudioBuffer
@testable import RelaySessionPanel

private actor ProofVAD:SpeechActivityDetector {
    nonisolated let chunkSamples=512;private var count=0
    func accept(_ samples:[Float])async throws->[SpeechBoundary] {
        count+=1
        if count==1 || count==3{return [SpeechBoundary(kind:.start,sampleIndex:UInt64((count-1)*512))]}
        if count==2{return [SpeechBoundary(kind:.end,sampleIndex:1024)]}
        return []
    }
}
private actor ProofRecognizer:ActivityRecognizer {
    func recognize(_ samples:[Float])async throws->String{"Explain event loops."}
}
private enum ProofIngress:Sendable {case audio(NativeSessionEvent),user(NativeUserQuestionRequest),cancel(NativeAnswerCancelRequest)}
private final class ProofQueue:@unchecked Sendable {
    private let lock=NSLock();private var values:[ProofIngress]=[]
    func append(_ value:ProofIngress){lock.withLock{values.append(value)}}
    func take()->[ProofIngress]{lock.withLock{let copy=values;values=[];return copy}}
    var hasFinal:Bool{lock.withLock{values.contains{if case .audio(let event)=$0{return event.kind == .eou};return false}}}
    var finalCount:Int{lock.withLock{values.filter{if case .audio(let event)=$0{return event.kind == .eou};return false}.count}}
    var hasOnset:Bool{lock.withLock{values.contains{if case .audio(let event)=$0{return event.kind == .speechStarted};return false}}}
}
private final class ProofReplies:@unchecked Sendable {
    private let lock=NSLock();private var values:[SessionAnswerDecision]=[]
    func append(_ data:Data)throws{let value=try SessionAnswerDecision(data:data);lock.withLock{if values.count<16{values.append(value)}}}
    var answers:[SessionAnswerDecision]{lock.withLock{values.filter{$0.disposition=="answer"}}}
    func terminal(_ id:UUID)->SessionAnswerDecision?{lock.withLock{values.last{$0.requestID==id && $0.disposition != "pending"}}}
}
@MainActor private final class ProofCapture {
    var target:PanelRequestBinding?;var entered=false
    private var continuation:CheckedContinuation<[Data],Never>?
    func hold(_ binding:PanelRequestBinding)async->[Data]{target=binding;entered=true;return await withCheckedContinuation{continuation=$0}}
    func finish(){continuation?.resume(returning:[]);continuation=nil}
}

@MainActor final class TypedAudioHelperTests:XCTestCase {
    private enum Mode {case unchanged,stop,supersede}
    func testUnstoppedActualAudioFinalUsesOriginalStagedPNGExactlyOnce()async throws{try await run(.unchanged)}
    func testStoppedHeldActualAudioFinalWithPNGStartsZeroPOSTBeforeLaterOnset()async throws{try await run(.stop)}
    func testTypedSupersessionRetiresHeldAudioPNGAndOnlyPostsFreshText()async throws{try await run(.supersede)}
    private var root:URL {URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    func testTranscriptConsumesActualNativeFinalsFromBothSources()async throws {
        let queue=ProofQueue(),store=SessionTranscriptStore()
        let native=NativeSessionController(onEvent:{queue.append(.audio($0))})
        try native.start(selectedBundleID:"com.example.fixture",microphoneEnabled:true,
            components:[1:SourceComponents(vad:ProofVAD(),recognizer:ProofRecognizer()),
                        2:SourceComponents(vad:ProofVAD(),recognizer:ProofRecognizer())])
        let clock=NativeClockCalibration.now()
        let origin=mach_absolute_time()-UInt64(2_000_000_000*Double(clock.nsDenom)/Double(clock.nsNumer))
        for source:PCMSource in [.microphone,.remoteAudio] {
            for index:UInt64 in 1...2 {
                let delta=UInt64(Double(index-1)*32_000_000*Double(clock.nsDenom)/Double(clock.nsNumer))
                native.ingest(SessionAudioPacket(source:source,streamGeneration:1,sequence:index,
                    hostTime:origin+delta,samples:Array(repeating:0.2,count:512)))
            }
        }
        for _ in 0..<1000 where queue.finalCount<2{try await Task.sleep(for:.milliseconds(1))}
        XCTAssertEqual(queue.finalCount,2)
        for item in queue.take(){if case .audio(let event)=item{store.observe(event)}}
        XCTAssertEqual(store.snapshot.rows.count,2)
        XCTAssertEqual(Set(store.snapshot.rows.map(\.source.rawValue)),[1,2])
        XCTAssertTrue(store.snapshot.rows.allSatisfy{$0.text=="Explain event loops."})
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
    }
    func testTypedBeforeAnyRemoteFinalUsesPersonalReferenceAndCompletedOAuthGates()async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:directory)}
        let log=directory.appendingPathComponent("requests.jsonl"),replies=ProofReplies(),queue=ProofQueue()
        let helper=HelperTransport(root:root,python:URL(fileURLWithPath:try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])),
            pythonArguments:[root.appendingPathComponent("tests/support/visual_backend_helper.py").path,"--synthetic-visual-test","--log",log.path],
            mode:.oauth,onFrame:replies.append,onFailure:{})
        try helper.start();addTeardownBlock{await helper.shutdownAndWait()}
        _=try await helper.requestVisualInput(.status,onUpdate:{_ in})
        let native=NativeSessionController(onEvent:{queue.append(.audio($0))})
        try native.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,
            components:[2:SourceComponents(vad:ProofVAD(),recognizer:ProofRecognizer())])
        let ports=ExplicitContextForwardingPorts(shouldCapture:{_ in false},capture:{_ in []},
            retire:{try helper.sendJSON($0.retirementJSON())},sendQuestion:{request,_ in try helper.sendJSON(request.encodedJSON())},
            sendCancellation:{try helper.sendJSON($0.encodedJSON())})
        let pump=OrderedContextForwarder(shouldCapture:{_ in false},capture:{_ in []},
            send:{ingress,_ in if case .audio(let event)=ingress{try helper.send(event)}},onFailure:{},explicit:ports)
        for item in queue.take(){if case .audio(let event)=item{try pump.enqueue(event)}}
        for (text,reason) in [("What did you personally do on your Atlas project?","personal_context_missing"),
                             ("What is the difference between WHERE and HAVING?","reviewed_full_question"),
                             ("Explain event loops.","format_checked")] {
            let request=try native.issueUserQuestion(expectedLease:try XCTUnwrap(native.authority.snapshot()),intent:.ask,
                question:text,baseRequestID:nil,enqueue:{queue.append(.user($0))})
            for item in queue.take(){if case .user(let value)=item{try pump.enqueueUserQuestion(value)}}
            for _ in 0..<2000 where replies.terminal(request.requestID)==nil{try await Task.sleep(for:.milliseconds(1))}
            XCTAssertEqual(replies.terminal(request.requestID)?.reason,reason)
            XCTAssertEqual(request.anchorEventSequence,1)
        }
        let content=try String(contentsOf:log,encoding:.utf8)
        XCTAssertEqual(content.components(separatedBy:"\n").filter{$0.contains("text_question")}.count,1)
        XCTAssertFalse(content.contains("image_question"));XCTAssertFalse(content.contains("probe"))
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
        await helper.shutdownAndWait()
    }
    private func run(_ mode:Mode)async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:directory)}
        let log=directory.appendingPathComponent("requests.jsonl"),replies=ProofReplies(),queue=ProofQueue(),capture=ProofCapture()
        let transcript=SessionTranscriptStore()
        let python=try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])
        let helper=HelperTransport(root:root,python:URL(fileURLWithPath:python),pythonArguments:[
            root.appendingPathComponent("tests/support/visual_backend_helper.py").path,"--synthetic-visual-test","--log",log.path],
            mode:.oauth,onFrame:replies.append,onFailure:{})
        try helper.start();addTeardownBlock{await helper.shutdownAndWait()}
        let verified=try await helper.requestVisualInput(.verify,onUpdate:{_ in})
        XCTAssertEqual(verified.status,.verified)
        let native=NativeSessionController(onEvent:{queue.append(.audio($0))})
        try native.start(selectedBundleID:"com.example.fixture",microphoneEnabled:false,
            components:[2:SourceComponents(vad:ProofVAD(),recognizer:ProofRecognizer())])
        let clock=NativeClockCalibration.now()
        let offset=UInt64(2_000_000_000*Double(clock.nsDenom)/Double(clock.nsNumer))
        let origin=mach_absolute_time()-offset
        func packet(_ index:UInt64)->SessionAudioPacket {
            let delta=UInt64(Double(index-1)*32_000_000*Double(clock.nsDenom)/Double(clock.nsNumer))
            return SessionAudioPacket(source:.remoteAudio,streamGeneration:1,sequence:index,hostTime:origin+delta,samples:Array(repeating:0.2,count:512))
        }
        native.ingest(packet(1));native.ingest(packet(2))
        for _ in 0..<1000 where !queue.hasFinal{try await Task.sleep(for:.milliseconds(1))}
        XCTAssertTrue(queue.hasFinal)
        var sent:[String]=[]
        let ports=ExplicitContextForwardingPorts(shouldCapture:{_ in false},capture:{_ in []},retire:{target in
            sent.append("deny");try helper.sendJSON(target.retirementJSON())
            let retired:[String:WireValue]=["schemaVersion":.uint(1),"kind":.string("supplemental_context_retired"),
                "captureSessionID":.string(target.lease.captureSessionID.uuidString.lowercased()),"sessionEpoch":.uint(target.lease.sessionEpoch),
                "presentationGeneration":.uint(target.lease.presentationGeneration),"requestID":.string(target.requestID.uuidString.lowercased()),"reasonCode":.string("context_changed")]
            try helper.sendJSON(JSONEncoder().encode(WireValue.object(retired)))
        },sendQuestion:{request,_ in sent.append("typed");try helper.sendJSON(request.encodedJSON())},
        sendCancellation:{request in sent.append("cancel");try helper.sendJSON(request.encodedJSON())})
        let pump=OrderedContextForwarder(shouldCapture:{$0.binding != nil},capture:{ingress in
            guard let target=ingress.binding else{return []}
            try? self.stageSyntheticPNG(target,helper:helper)
            return await capture.hold(target)
        },send:{ingress,_ in
            guard case .audio(let event)=ingress else{return}
            sent.append(event.kind.rawValue);try helper.send(event)
            if event.kind == .eou{Thread.sleep(forTimeInterval:0.15)}
        },onFailure:{},explicit:ports)
        func forward(_ values:[ProofIngress])throws {
            for value in values {
                switch value {
                case .audio(let event):transcript.observe(event);try pump.enqueue(event)
                case .user(let request):try pump.enqueueUserQuestion(request,retiring:capture.target)
                case .cancel(let request):try pump.enqueueAnswerCancellation(request,retiring:try XCTUnwrap(capture.target))
                }
            }
        }
        try forward(queue.take())
        for _ in 0..<30 where !capture.entered{await Task.yield()}
        let target=try XCTUnwrap(capture.target)
        XCTAssertEqual(transcript.snapshot.rows.first?.text,"Explain event loops.")
        XCTAssertEqual(transcript.snapshot.rows.first?.source.label,"Selected app audio")
        if mode == .unchanged {capture.finish()}
        else if mode == .stop {
            let request=try native.issueAnswerCancellation(expectedLease:target.lease,targetRequestID:target.requestID,
                enqueue:{queue.append(.cancel($0))})
            let pending=try helper.registerAnswerCancellation(request)
            native.ingest(packet(3))
            for _ in 0..<1000 where !queue.hasOnset{try await Task.sleep(for:.milliseconds(1))}
            try forward(queue.take());let receipt=try await pending.value();XCTAssertTrue(receipt.quiesced)
            XCTAssertLessThan(try XCTUnwrap(sent.firstIndex(of:"deny")),try XCTUnwrap(sent.firstIndex(of:"eou")))
            XCTAssertLessThan(try XCTUnwrap(sent.firstIndex(of:"eou")),try XCTUnwrap(sent.firstIndex(of:"cancel")))
            XCTAssertEqual(sent.last,"speech_started");capture.finish()
        } else {
            _=try native.issueUserQuestion(expectedLease:target.lease,intent:.ask,question:"Explain a cache.",baseRequestID:nil,
                enqueue:{queue.append(.user($0))})
            try forward(queue.take());capture.finish()
        }
        if mode != .stop {
            for _ in 0..<2000 where replies.answers.isEmpty{try await Task.sleep(for:.milliseconds(1))}
            XCTAssertEqual(replies.answers.count,1)
        }
        let lines=try String(contentsOf:log,encoding:.utf8)
        let image=lines.components(separatedBy:"\n").filter{$0.contains("image_question")}.count
        let text=lines.components(separatedBy:"\n").filter{$0.contains("text_question")}.count
        XCTAssertEqual(image,mode == .unchanged ? 1:0)
        XCTAssertEqual(text,mode == .supersede ? 1:0)
        if mode == .unchanged{XCTAssertNotNil(replies.answers.first?.taskContext?.imageDigest)}
        native.beginStop();await native.waitForQuiescence();native.finishStop(quiesced:true)
        await helper.shutdownAndWait()
    }
    private func stageSyntheticPNG(_ target:PanelRequestBinding,helper:HelperTransport)throws {
        let url=root.appendingPathComponent("tests/fixtures/typed-synthetic-screen.json")
        let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [[String:Any]]
        let captured=DispatchTime.now().uptimeNanoseconds
        for var frame in fixture {
            frame["captureSessionID"]=target.lease.captureSessionID.uuidString.lowercased();frame["sessionEpoch"]=target.lease.sessionEpoch
            frame["presentationGeneration"]=target.lease.presentationGeneration;frame["requestID"]=target.requestID.uuidString.lowercased()
            frame["capturedUptimeNanoseconds"]=captured
            try helper.sendJSON(JSONSerialization.data(withJSONObject:frame))
        }
    }
}
