import Foundation
import Dispatch
import Darwin
import RelayNativeSession

public enum HelperMode: Sendable { case noInference, fixture, oauth }

/// One child and owned binary pipes. Writes are nonblocking with a deadline;
/// bounded queue overflow/EOF/malformed input retires native admission.
public final class HelperTransport: @unchecked Sendable {
    private let root:URL;private let python:URL;private let pythonArguments:[String];private let mode:HelperMode
    private let onFrame:@Sendable(Data)->Void;private let onFailure:@Sendable()->Void
    private let io=DispatchQueue(label:"relay.helper.read");private let writes=DispatchQueue(label:"relay.helper.write")
    private let lock=NSLock();private var process:Process?;private var input:FileHandle?;private var output:FileHandle?;private var errors:FileHandle?
    private var source:DispatchSourceRead?;private var stderrSource:DispatchSourceRead?;private var timer:DispatchSourceTimer?
    private var queuedFrames=0;private var queuedBytes=0;private var failed=false
    private let decoder=AnswerFrameDecoder();private var partialSince:UInt64?
    public init(root:URL,python:URL,pythonArguments:[String]=[],mode:HelperMode,
                onFrame:@escaping @Sendable(Data)->Void,onFailure:@escaping @Sendable()->Void) {
        self.root=root;self.python=python;self.pythonArguments=pythonArguments;self.mode=mode;self.onFrame=onFrame;self.onFailure=onFailure
    }
    public func start() throws {
        let child=Process();let stdin=Pipe(),stdout=Pipe(),stderr=Pipe()
        child.executableURL=python;child.currentDirectoryURL=root
        child.arguments=pythonArguments+["-m","relay_spike.session_host"]+(mode == .fixture ? ["--fixture-model"] : mode == .oauth ? ["--oauth"]:[])
        child.standardInput=stdin;child.standardOutput=stdout;child.standardError=stderr
        child.terminationHandler={ [weak self] _ in self?.fail() }
        try lock.withLock {
            guard process==nil,!failed else { throw PanelBridgeError.closed }
            try child.run();process=child;input=stdin.fileHandleForWriting;output=stdout.fileHandleForReading;errors=stderr.fileHandleForReading
            if let fd=input?.fileDescriptor { _=fcntl(fd,F_SETNOSIGPIPE,1) }
            for handle in [input,output,errors] { if let fd=handle?.fileDescriptor { _=fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK) } }
        }
        let readSource=DispatchSource.makeReadSource(fileDescriptor:stdout.fileHandleForReading.fileDescriptor,queue:io)
        readSource.setEventHandler { [weak self] in self?.readAvailable() };source=readSource;readSource.resume()
        let errorSource=DispatchSource.makeReadSource(fileDescriptor:stderr.fileHandleForReading.fileDescriptor,queue:io)
        errorSource.setEventHandler { [weak self] in self?.discardErrors() };stderrSource=errorSource;errorSource.resume()
        let timer=DispatchSource.makeTimerSource(queue:io)
        timer.schedule(deadline:.now() + .milliseconds(250),repeating:.milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self,let since=self.partialSince,DispatchTime.now().uptimeNanoseconds-since>3_000_000_000 else { return };self.fail()
        };self.timer=timer;timer.resume()
    }
    public func send(_ event:NativeSessionEvent) throws { try enqueue(event.encodedFrame()) }
    public func sendJSON(_ data:Data) throws {
        _=try StrictJSON.decode(data);var n=UInt32(data.count).bigEndian
        var frame=withUnsafeBytes(of:&n) { Data($0) };frame.append(data);try enqueue(frame)
    }
    private func enqueue(_ frame:Data) throws {
        try lock.withLock {
            guard !failed,input != nil else { throw PanelBridgeError.closed }
            guard queuedFrames<32,queuedBytes+frame.count<=262144 else { throw PanelBridgeError.overflow }
            queuedFrames+=1;queuedBytes+=frame.count
        }
        writes.async { [weak self] in
            guard let self else { return }
            defer { self.lock.withLock { self.queuedFrames-=1;self.queuedBytes-=frame.count } }
            do { try self.write(frame) } catch { self.fail() }
        }
    }
    private func write(_ frame:Data) throws {
        guard let fd=lock.withLock({ !failed ? input?.fileDescriptor:nil }) else { throw PanelBridgeError.closed }
        let deadline=DispatchTime.now().uptimeNanoseconds+2_000_000_000
        try frame.withUnsafeBytes { raw in
            var offset=0
            while offset<raw.count {
                guard DispatchTime.now().uptimeNanoseconds<deadline,!lock.withLock({ failed }) else { throw PanelBridgeError.timedOut }
                let n=Darwin.write(fd,raw.baseAddress!.advanced(by:offset),raw.count-offset)
                if n>0 { offset+=n;continue }
                if errno==EINTR { continue }
                guard errno==EAGAIN || errno==EWOULDBLOCK else { throw PanelBridgeError.closed }
                var descriptor=pollfd(fd:fd,events:Int16(POLLOUT),revents:0);_=poll(&descriptor,1,50)
            }
        }
    }
    private func readAvailable() {
        guard let fd=lock.withLock({ !failed ? output?.fileDescriptor:nil }) else { return }
        var bytes=[UInt8](repeating:0,count:4096)
        while true {
            let count=Darwin.read(fd,&bytes,bytes.count)
            if count==0 { fail();return }
            if count<0 { if errno==EAGAIN || errno==EWOULDBLOCK { return };if errno==EINTR { continue };fail();return }
            do {
                for frame in try decoder.feed(Data(bytes.prefix(count))) { _=try SessionAnswerDecision(data:frame);onFrame(frame) }
                if decoder.hasPartial { if partialSince==nil { partialSince=DispatchTime.now().uptimeNanoseconds } } else { partialSince=nil }
            } catch { fail();return }
        }
    }
    private func discardErrors() {
        guard let fd=lock.withLock({ !failed ? errors?.fileDescriptor:nil }) else { return }
        var bytes=[UInt8](repeating:0,count:4096)
        let n=Darwin.read(fd,&bytes,bytes.count)
        if n==0 { stderrSource?.cancel() }
    }
    private func fail() {
        let first=lock.withLock { if failed { return false };failed=true;return true }
        guard first else { return };onFailure();stop()
    }
    public func stop() {
        let child:Process?=lock.withLock { failed=true;return process }
        io.async { [weak self] in
            guard let self else { return };self.source?.cancel();self.stderrSource?.cancel();self.timer?.cancel()
        }
        // Do not recycle a descriptor while the writer may still hold it.
        writes.async { [weak self] in
            guard let self else { return }
            self.lock.withLock { try? self.input?.close();self.input=nil }
        }
        guard let child else { return }
        io.asyncAfter(deadline:.now() + .seconds(2)) {
            if child.isRunning { child.terminate() }
        }
        io.asyncAfter(deadline:.now() + .seconds(4)) {
            if child.isRunning { _=Darwin.kill(child.processIdentifier,SIGKILL) }
        }
    }
}
