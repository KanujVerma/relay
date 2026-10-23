import Foundation
import Dispatch
import Darwin
import RelayNativeSession

private final class OwnedChildExit: @unchecked Sendable {
    private let lock=NSLock()
    private var finished=false
    private var waiters:[CheckedContinuation<Void,Never>]=[]
    var isFinished:Bool { lock.withLock { finished } }
    func record() {
        let pending=lock.withLock { finished=true;let values=waiters;waiters.removeAll();return values }
        pending.forEach { $0.resume() }
    }
    func wait() async {
        await withCheckedContinuation { continuation in
            let immediate=lock.withLock {
                if finished { return true }
                waiters.append(continuation);return false
            }
            if immediate { continuation.resume() }
        }
    }
}

public enum HelperMode: Sendable { case noInference, fixture, oauth }

/// One child and owned binary pipes. Writes are nonblocking with a deadline;
/// bounded queue overflow/EOF/malformed input retires native admission.
public final class HelperTransport: @unchecked Sendable {
    private let root:URL;private let python:URL;private let pythonArguments:[String];private let mode:HelperMode;private let role:String
    private let onFrame:@Sendable(Data)throws->Void;private let onFailure:@Sendable()->Void
    private let io=DispatchQueue(label:"relay.helper.read");private let writes=DispatchQueue(label:"relay.helper.write")
    private let lock=NSLock();private var process:Process?;private var input:FileHandle?;private var output:FileHandle?;private var errors:FileHandle?
    private var source:DispatchSourceRead?;private var stderrSource:DispatchSourceRead?;private var timer:DispatchSourceTimer?
    private var profileRequests:[UUID:CheckedContinuation<Data,any Error>]=[:]
    private var quiescenceRequests:[UUID:(UUID,UInt64,CheckedContinuation<Void,any Error>)]=[:]
    private var queuedFrames=0;private var queuedBytes=0;private var failed=false
    private let exitReceipt=OwnedChildExit()
    private let decoder=AnswerFrameDecoder();private var partialSince:UInt64?
    public init(root:URL,python:URL,pythonArguments:[String]=[],mode:HelperMode,role:String="analytics",
                onFrame:@escaping @Sendable(Data)throws->Void,onFailure:@escaping @Sendable()->Void) {
        self.root=root;self.python=python;self.pythonArguments=pythonArguments;self.mode=mode;self.role=role;self.onFrame=onFrame;self.onFailure=onFailure
    }
    public func start() throws {
        let child=Process();let stdin=Pipe(),stdout=Pipe(),stderr=Pipe()
        child.executableURL=python;child.currentDirectoryURL=root
        child.arguments=pythonArguments+["-m","relay_spike.session_host","--role",role]+(mode == .fixture ? ["--fixture-model"] : mode == .oauth ? ["--oauth"]:[])
        child.standardInput=stdin;child.standardOutput=stdout;child.standardError=stderr
        let receipt=exitReceipt
        child.terminationHandler={ [weak self,receipt] child in
            _=child.terminationStatus
            self?.fail();receipt.record()
        }
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
    public func requestProfile(_ command:Data) async throws -> Data {
        _=try StrictJSON.decode(command)
        let payload=try JSONSerialization.jsonObject(with:command)
        let id=UUID()
        let envelope=try JSONSerialization.data(withJSONObject:["schemaVersion":1,"kind":"profile_request","requestID":id.uuidString.lowercased(),"payload":payload])
        return try await withCheckedThrowingContinuation { continuation in
            let admitted=lock.withLock {
                guard !failed,profileRequests.count<4 else { return false }
                profileRequests[id]=continuation;return true
            }
            guard admitted else { continuation.resume(throwing:PanelBridgeError.closed);return }
            do { try sendJSON(envelope) } catch {
                let pending=lock.withLock { profileRequests.removeValue(forKey:id) }
                pending?.resume(throwing:PanelBridgeError.closed);return
            }
            io.asyncAfter(deadline:.now() + .seconds(15)) { [weak self] in
                guard let self else { return }
                let pending=self.lock.withLock { self.profileRequests.removeValue(forKey:id) }
                if let pending { pending.resume(throwing:PanelBridgeError.timedOut);self.fail() }
            }
        }
    }
    /// Resume needs actual old model ownership to return; a timeout retires the
    /// transport and cannot masquerade as an acknowledgment.
    public func requestSessionQuiescence(sessionID:UUID,epoch:UInt64) async throws {
        let id=UUID()
        let envelope=try JSONEncoder().encode(WireValue.object([
            "schemaVersion":.uint(1),"kind":.string("session_quiescence_request"),
            "requestID":.string(id.uuidString.lowercased()),"captureSessionID":.string(sessionID.uuidString.lowercased()),"sessionEpoch":.uint(epoch)]))
        try await withCheckedThrowingContinuation { continuation in
            let admitted=lock.withLock {
                guard !failed,quiescenceRequests.isEmpty else { return false }
                quiescenceRequests[id]=(sessionID,epoch,continuation);return true
            }
            guard admitted else { continuation.resume(throwing:PanelBridgeError.closed);return }
            do { try sendJSON(envelope) } catch {
                let pending=lock.withLock { quiescenceRequests.removeValue(forKey:id) }
                pending?.2.resume(throwing:PanelBridgeError.closed);return
            }
            io.asyncAfter(deadline:.now() + .seconds(15)) { [weak self] in
                guard let self else { return }
                let pending=self.lock.withLock { self.quiescenceRequests.removeValue(forKey:id) }
                if let pending { pending.2.resume(throwing:PanelBridgeError.timedOut);self.fail() }
            }
        }
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
                for frame in try decoder.feed(Data(bytes.prefix(count))) {
                    let node=try StrictJSON.decode(frame)
                    if case .object(let fields)=node,case .string("profile_response")?=fields["kind"] {
                        let fields=try node.object(["schemaVersion","kind","requestID","payload"])
                        guard try fields["schemaVersion"]!.uint()==1,let id=UUID(uuidString:try fields["requestID"]!.string()) else { throw PanelBridgeError.malformed }
                        let continuation=lock.withLock { profileRequests.removeValue(forKey:id) }
                        guard let continuation else { throw PanelBridgeError.malformed }
                        let decoded=try JSONSerialization.jsonObject(with:frame) as! [String:Any]
                        continuation.resume(returning:try JSONSerialization.data(withJSONObject:decoded["payload"]!))
                    } else if case .object(let fields)=node,case .string("session_quiescence_response")?=fields["kind"] {
                        let fields=try node.object(["schemaVersion","kind","requestID","captureSessionID","sessionEpoch","quiesced"])
                        guard try fields["schemaVersion"]!.uint()==1,try fields["quiesced"]!.boolean(),
                              let id=UUID(uuidString:try fields["requestID"]!.string()),let session=UUID(uuidString:try fields["captureSessionID"]!.string()) else { throw PanelBridgeError.malformed }
                        let epoch=try fields["sessionEpoch"]!.uint()
                        let pending=lock.withLock { quiescenceRequests.removeValue(forKey:id) }
                        guard let pending,pending.0==session,pending.1==epoch else { throw PanelBridgeError.malformed }
                        pending.2.resume()
                    } else { _=try SessionAnswerDecision(data:frame);try onFrame(frame) }
                }
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
    /// Permanently close admission, reject pending continuations and await the
    /// owned child's actual exit/reap. No replacement can be launched by this object.
    public func shutdownAndWait() async {
        stop()
        guard lock.withLock({ process != nil }) else { return }
        // The prelaunch termination handler records Foundation's actual child
        // termination/reap. No launch-thread runloop or blocking wait is needed.
        await exitReceipt.wait()
    }

    public func stop() {
        let (child,pending)=lock.withLock {
            failed=true;let pending=Array(profileRequests.values);profileRequests.removeAll()
            let sessions=Array(quiescenceRequests.values);quiescenceRequests.removeAll()
            sessions.forEach { $0.2.resume(throwing:PanelBridgeError.closed) }
            return (process,pending)
        }
        pending.forEach { $0.resume(throwing:PanelBridgeError.closed) }
        io.async { [weak self] in
            guard let self else { return };self.source?.cancel();self.stderrSource?.cancel();self.timer?.cancel()
        }
        // Do not recycle a descriptor while the writer may still hold it.
        writes.async { [weak self] in
            guard let self else { return }
            self.lock.withLock { try? self.input?.close();self.input=nil }
        }
        guard let child else { return }
        let receipt=exitReceipt
        io.asyncAfter(deadline:.now() + .seconds(2)) {
            if !receipt.isFinished,child.isRunning { child.terminate() }
        }
        io.asyncAfter(deadline:.now() + .seconds(4)) {
            if !receipt.isFinished,child.isRunning { _=Darwin.kill(child.processIdentifier,SIGKILL) }
        }
    }
}
