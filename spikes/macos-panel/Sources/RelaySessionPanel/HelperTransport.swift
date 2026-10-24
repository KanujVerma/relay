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

/// Owned response for an already registered/enqueued visual control. Issuance
/// is synchronous; waiting for the actual helper terminal remains asynchronous.
public final class PendingVisualInputResponse:@unchecked Sendable {
    private let lock=NSLock()
    private var result:Result<VisualInputResponse,any Error>?
    private var waiter:CheckedContinuation<VisualInputResponse,any Error>?
    fileprivate init(){}
    public func value()async throws->VisualInputResponse {
        try await withCheckedThrowingContinuation{continuation in
            let ready:Result<VisualInputResponse,any Error>?=lock.withLock{
                if let result{return result}
                guard waiter==nil else{return .failure(PanelBridgeError.malformed)}
                waiter=continuation;return nil
            }
            if let ready{continuation.resume(with:ready)}
        }
    }
    fileprivate func finish(_ value:Result<VisualInputResponse,any Error>) {
        let pending=lock.withLock{
            guard result==nil else{return Optional<CheckedContinuation<VisualInputResponse,any Error>>.none}
            result=value;let pending=waiter;waiter=nil;return pending
        }
        pending?.resume(with:value)
    }
}

/// A queued image can retire without waiting behind an unrelated blocked write.
/// Once its first byte is written, only full completion or transport failure ends it.
private final class ImageWriteReservation:@unchecked Sendable {
    let id=UUID()
    let byteCount:Int
    private let lock=NSLock()
    private var bytes:Data?
    private var started=false
    private var result:Result<Void,any Error>?
    private var waiter:CheckedContinuation<Void,any Error>?
    init(_ bytes:Data){self.bytes=bytes;byteCount=bytes.count}
    var isFinished:Bool{lock.withLock{result != nil}}
    var hasStarted:Bool{lock.withLock{started}}
    func wait()async throws {
        try await withCheckedThrowingContinuation{continuation in
            let ready:Result<Void,any Error>?=lock.withLock{if let result{return result};waiter=continuation;return nil}
            if let ready{continuation.resume(with:ready)}
        }
    }
    func retire(_ error:any Error) {
        let pending=lock.withLock{
            guard !started,result==nil else{return Optional<CheckedContinuation<Void,any Error>>.none}
            result = .failure(error);bytes=nil;let pending=waiter;waiter=nil;return pending
        }
        pending?.resume(throwing:error)
    }
    func finish(_ outcome:Result<Void,any Error>) {
        let pending=lock.withLock{
            guard result==nil else{return Optional<CheckedContinuation<Void,any Error>>.none}
            result=outcome;bytes=nil;let pending=waiter;waiter=nil;return pending
        }
        pending?.resume(with:outcome)
    }
    /// Runs on MainActor so source retirement cannot interleave between its
    /// currentness check and the first nonblocking write. Cancellation shares
    /// this lock; an EAGAIN has not started a frame and stays retireable.
    @MainActor func start(fd:Int32,deadline:UInt64,isCurrent:()->Bool)throws ->(Data,Int)? {
        try lock.withLock{
            guard result==nil,!started,let bytes else{return nil}
            guard isCurrent() else{throw CancellationError()}
            guard DispatchTime.now().uptimeNanoseconds<deadline else{throw PanelBridgeError.timedOut}
            let count=bytes.withUnsafeBytes{raw in
                var count=Darwin.write(fd,raw.baseAddress!,raw.count)
                while count<0,errno==EINTR{count=Darwin.write(fd,raw.baseAddress!,raw.count)}
                return count
            }
            if count>0{started=true;self.bytes=nil;return(bytes,count)}
            if count<0,(errno==EAGAIN || errno==EWOULDBLOCK){return nil}
            throw PanelBridgeError.closed
        }
    }
}

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
    private struct VisualWaiter {
        let action:VisualInputAction
        let response:PendingVisualInputResponse
        let progress:@Sendable(VisualInputResponse)->Void
        var last:VisualInputResponse?
    }
    private var visualRequests:[UUID:VisualWaiter]=[:]
    private var answerCancellations:[UUID:(NativeAnswerCancelRequest,PendingAnswerCancellation)]=[:]
    private var cancellationReplies:[UUID:(NativeAnswerCancelRequest,AnswerCancellationResponse)]=[:]
    private var cancellationReplyOrder:[UUID]=[]
    private var cancellationCount=0
    private var visualReplies:[UUID:VisualInputResponse]=[:]
    private var visualReplyOrder:[UUID]=[]
    private var visualRequestCount=0
    private var imageWrites:[UUID:ImageWriteReservation]=[:]
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
    /// One producer-owned JSON frame, with bounded asynchronous backpressure.
    /// Once admitted, its full frame must finish or fail the whole transport;
    /// source cancellation never inserts an EOU into a partially written frame.
    @MainActor public func sendJSONAwaitingWrite(_ data:Data,deadline:UInt64,isCurrent:@escaping @MainActor ()->Bool) async throws {
        _=try StrictJSON.decode(data);var length=UInt32(data.count).bigEndian
        var frame=withUnsafeBytes(of:&length){Data($0)};frame.append(data)
        while true {
            try Task.checkCancellation()
            guard isCurrent() else{throw CancellationError()}
            guard DispatchTime.now().uptimeNanoseconds<deadline else{throw PanelBridgeError.timedOut}
            do {
                let reservation=ImageWriteReservation(frame)
                try enqueueImage(reservation,deadline:deadline,isCurrent:isCurrent)
                let monitor=Task{@MainActor in
                    while !reservation.isFinished {
                        if !isCurrent(){reservation.retire(CancellationError());return}
                        if DispatchTime.now().uptimeNanoseconds>=deadline{reservation.retire(PanelBridgeError.timedOut);return}
                        do{try await Task.sleep(for:.milliseconds(1))}catch{return}
                    }
                }
                defer{monitor.cancel()}
                try await withTaskCancellationHandler{try await reservation.wait()}onCancel:{reservation.retire(CancellationError())}
                try Task.checkCancellation()
                guard isCurrent() else{throw CancellationError()}
                guard DispatchTime.now().uptimeNanoseconds<deadline else{throw PanelBridgeError.timedOut}
                return
            } catch PanelBridgeError.overflow {
                try await Task.sleep(for:.milliseconds(1))
            }
        }
    }
    /// Register before enqueueing on the native ordered ingress. This does not
    /// send the action directly or pretend its target has stopped.
    public func registerAnswerCancellation(_ request:NativeAnswerCancelRequest)throws->PendingAnswerCancellation {
        let response=try lock.withLock{()->PendingAnswerCancellation in
            guard !failed,input != nil else{throw PanelBridgeError.closed}
            if let pending=answerCancellations[request.requestID]{
                guard pending.0==request else{throw PanelBridgeError.malformed};return pending.1
            }
            if let previous=cancellationReplies[request.requestID]{
                guard previous.0==request else{throw PanelBridgeError.malformed}
                let response=PendingAnswerCancellation();response.finish(.success(previous.1));return response
            }
            guard answerCancellations.count<8,cancellationCount<512 else{throw PanelBridgeError.overflow}
            cancellationCount+=1
            let response=PendingAnswerCancellation();answerCancellations[request.requestID]=(request,response);return response
        }
        io.asyncAfter(deadline:.now() + .seconds(15)){[weak self] in
            guard let self else{return}
            let pending=self.lock.withLock{self.answerCancellations[request.requestID]}
            if let pending{pending.1.finish(.failure(PanelBridgeError.timedOut));self.fail()}
        }
        return response
    }
    private func acceptAnswerCancellation(_ reply:AnswerCancellationResponse)throws {
        let response=try lock.withLock{()->PendingAnswerCancellation? in
            guard let pending=answerCancellations[reply.requestID] else{
                if cancellationReplies[reply.requestID]?.1==reply{return nil}
                throw PanelBridgeError.malformed
            }
            guard reply.captureSessionID==pending.0.lease.captureSessionID,reply.sessionEpoch==pending.0.lease.sessionEpoch,
                  reply.presentationGeneration==pending.0.lease.presentationGeneration,reply.targetRequestID==pending.0.targetRequestID else{throw PanelBridgeError.malformed}
            // Fallible validation precedes removal so failure still resolves it.
            answerCancellations.removeValue(forKey:reply.requestID)
            cancellationReplies[reply.requestID]=(pending.0,reply);cancellationReplyOrder.append(reply.requestID)
            while cancellationReplyOrder.count>8{cancellationReplies.removeValue(forKey:cancellationReplyOrder.removeFirst())}
            return pending.1
        }
        response?.finish(.success(reply))
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
    /// The UI explicitly requests verify/disable/status. Status alone grants
    /// no native image authority, and cancellation completion comes from the
    /// original verify terminal reply rather than a local timer/Task flag.
    public func requestVisualInput(_ action:VisualInputAction,onUpdate:@escaping @Sendable(VisualInputResponse)->Void) async throws -> VisualInputResponse {
        let response=try issueVisualInput(action,onUpdate:onUpdate)
        return try await response.value()
    }
    /// Register and enqueue before the caller can release a staged EOU. No
    /// helper IO or await occurs here; the existing bounded writer owns order.
    public func issueVisualInput(_ action:VisualInputAction,onUpdate:@escaping @Sendable(VisualInputResponse)->Void) throws -> PendingVisualInputResponse {
        let id=UUID()
        let envelope=try JSONEncoder().encode(WireValue.object(["schemaVersion":.uint(1),"kind":.string("visual_input_request"),"requestID":.string(id.uuidString.lowercased()),"action":.string(action.rawValue)]))
        let response=PendingVisualInputResponse()
        try lock.withLock {
            guard !failed,visualRequests.count<4,visualRequestCount<512 else{throw PanelBridgeError.closed}
            visualRequestCount+=1
            visualRequests[id]=VisualWaiter(action:action,response:response,progress:onUpdate,last:nil)
        }
        do{try sendJSON(envelope)}catch{
            let waiter=lock.withLock{visualRequests.removeValue(forKey:id)}
            waiter?.response.finish(.failure(PanelBridgeError.closed));fail();throw error
        }
        io.asyncAfter(deadline:.now() + .seconds(35)){[weak self] in
            guard let self else{return}
            let waiter=self.lock.withLock{self.visualRequests.removeValue(forKey:id)}
            if let waiter{waiter.response.finish(.failure(PanelBridgeError.timedOut));self.fail()}
        }
        return response
    }
    private enum VisualDelivery {
        case ignored
        case progress(@Sendable(VisualInputResponse)->Void)
        case terminal(PendingVisualInputResponse)
    }
    private func acceptVisual(_ reply:VisualInputResponse)throws {
        let delivery:VisualDelivery=try lock.withLock {
            guard !failed else{throw PanelBridgeError.closed}
            guard var waiter=visualRequests[reply.requestID] else{
                guard visualReplies[reply.requestID]==reply else{throw PanelBridgeError.malformed}
                return .ignored
            }
            guard waiter.action==reply.action else{throw PanelBridgeError.malformed}
            if waiter.last==reply{return .ignored}
            if !reply.isTerminal {
                guard waiter.last==nil else{throw PanelBridgeError.malformed}
                waiter.last=reply;visualRequests[reply.requestID]=waiter
                return .progress(waiter.progress)
            }
            // All fallible validation precedes removal of continuation ownership.
            visualRequests.removeValue(forKey:reply.requestID)
            visualReplies[reply.requestID]=reply;visualReplyOrder.append(reply.requestID)
            while visualReplyOrder.count>8{visualReplies.removeValue(forKey:visualReplyOrder.removeFirst())}
            return .terminal(waiter.response)
        }
        switch delivery {
        case .ignored:break
        case .progress(let callback):callback(reply)
        case .terminal(let response):response.finish(.success(reply))
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
    private func enqueueImage(_ reservation:ImageWriteReservation,deadline:UInt64,isCurrent:@escaping @MainActor ()->Bool)throws {
        try lock.withLock{
            guard !failed,input != nil else{throw PanelBridgeError.closed}
            guard queuedFrames<32,queuedBytes+reservation.byteCount<=262144 else{throw PanelBridgeError.overflow}
            queuedFrames+=1;queuedBytes+=reservation.byteCount;imageWrites[reservation.id]=reservation
        }
        writes.async{[weak self] in
            guard let self else{reservation.finish(.failure(PanelBridgeError.closed));return}
            // Keep the bounded queue slot until it drains, even if its bytes
            // and waiter retire earlier. No unbounded cancelled work queue.
            defer{self.lock.withLock{self.queuedFrames-=1;self.queuedBytes-=reservation.byteCount;self.imageWrites.removeValue(forKey:reservation.id)}}
            do {
                guard let fd=self.lock.withLock({!self.failed ? self.input?.fileDescriptor:nil}) else{throw PanelBridgeError.closed}
                while !reservation.isFinished {
                    let first=try DispatchQueue.main.sync{
                        try MainActor.assumeIsolated{try reservation.start(fd:fd,deadline:deadline,isCurrent:isCurrent)}
                    }
                    if let (frame,offset)=first {
                        try self.write(frame,startingAt:offset);reservation.finish(.success(()));return
                    }
                    if !reservation.isFinished{var descriptor=pollfd(fd:fd,events:Int16(POLLOUT),revents:0);_=poll(&descriptor,1,50)}
                }
            }catch{
                if reservation.hasStarted{self.fail()}
                else if case PanelBridgeError.closed=error{self.fail()}
                reservation.finish(.failure(error))
            }
        }
    }
    private func write(_ frame:Data,startingAt:Int=0) throws {
        guard let fd=lock.withLock({ !failed ? input?.fileDescriptor:nil }) else { throw PanelBridgeError.closed }
        let deadline=DispatchTime.now().uptimeNanoseconds+2_000_000_000
        try frame.withUnsafeBytes { raw in
            var offset=startingAt
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
                        // Keep the waiter registered until every fallible payload
                        // check/encoding completes, so fail()/stop() can reject it.
                        guard case .object?=fields["payload"],
                              let decoded=try JSONSerialization.jsonObject(with:frame) as? [String:Any],
                              let payload=decoded["payload"] as? [String:Any] else { throw PanelBridgeError.malformed }
                        let response=try JSONSerialization.data(withJSONObject:payload)
                        let continuation=lock.withLock { profileRequests.removeValue(forKey:id) }
                        guard let continuation else { throw PanelBridgeError.malformed }
                        continuation.resume(returning:response)
                    } else if case .object(let fields)=node,case .string("session_quiescence_response")?=fields["kind"] {
                        let fields=try node.object(["schemaVersion","kind","requestID","captureSessionID","sessionEpoch","quiesced"])
                        guard try fields["schemaVersion"]!.uint()==1,try fields["quiesced"]!.boolean(),
                              let id=UUID(uuidString:try fields["requestID"]!.string()),let session=UUID(uuidString:try fields["captureSessionID"]!.string()) else { throw PanelBridgeError.malformed }
                        let epoch=try fields["sessionEpoch"]!.uint()
                        let continuation=try lock.withLock {
                            guard let pending=quiescenceRequests[id],pending.0==session,pending.1==epoch else { throw PanelBridgeError.malformed }
                            quiescenceRequests.removeValue(forKey:id)
                            return pending.2
                        }
                        continuation.resume()
                    } else if case .object(let fields)=node,case .string("visual_input_response")?=fields["kind"] {
                        try acceptVisual(VisualInputResponse(data:frame))
                    } else if case .object(let fields)=node,case .string("answer_cancel_response")?=fields["kind"] {
                        try acceptAnswerCancellation(AnswerCancellationResponse(data:frame))
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
        let (child,pending,images)=lock.withLock {
            failed=true;let pending=Array(profileRequests.values);profileRequests.removeAll()
            let sessions=Array(quiescenceRequests.values);quiescenceRequests.removeAll()
            sessions.forEach { $0.2.resume(throwing:PanelBridgeError.closed) }
            let cancellations=Array(answerCancellations.values);answerCancellations.removeAll()
            cancellations.forEach{$0.1.finish(.failure(PanelBridgeError.closed))}
            let visual=Array(visualRequests.values);visualRequests.removeAll()
            visual.forEach{$0.response.finish(.failure(PanelBridgeError.closed))}
            return (process,pending,Array(imageWrites.values))
        }
        pending.forEach { $0.resume(throwing:PanelBridgeError.closed) }
        images.forEach{$0.retire(PanelBridgeError.closed)}
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
