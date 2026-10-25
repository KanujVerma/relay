import Darwin
import Foundation

/// Private browser effect. It is never retained in a public account snapshot.
public struct AccountAuthorization: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let requestID: UUID
    public let authorizationURL: URL
    public var description: String { "AccountAuthorization(redacted)" }
    public var debugDescription: String { description }
    init(data: Data) throws {
        let value = try AccountJSON.decode(data).object(["schemaVersion", "kind", "requestID", "authorizationURL"])
        guard try value["schemaVersion"]!.uint() == 1, try value["kind"]!.string() == "account_authorization" else { throw AccountError.malformed }
        requestID = try accountUUID(value["requestID"]!)
        let text = try value["authorizationURL"]!.string(12288)
        guard let parts = URLComponents(string: text), parts.scheme == "https", parts.host?.lowercased() == "auth.openai.com",
              parts.path == "/api/accounts/authorize", parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443, parts.fragment == nil, let url = parts.url else { throw AccountError.malformed }
        authorizationURL = url
    }
}

public protocol AccountPort: Sendable {
    func perform(_ request: AccountRequest, authorization: @escaping @Sendable (AccountAuthorization) async -> Bool) async throws -> AccountResponse
    /// Must join the actual owned process exit. Task cancellation is not a receipt.
    func close() async
}
public extension AccountPort {
    func perform(_ request: AccountRequest) async throws -> AccountResponse { try await perform(request, authorization: { _ in false }) }
}

// Reused ownership pattern from ProfileProcessExitReceipt at frozen666d104.
private final class AccountChildExit: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var hasExited: Bool { lock.withLock { finished } }
    func record() {
        let pending = lock.withLock { finished = true; let pending = waiters; waiters.removeAll(); return pending }
        pending.forEach { $0.resume() }
    }
    func wait() async {
        await withCheckedContinuation { continuation in
            let done = lock.withLock {
                if finished { return true }
                waiters.append(continuation); return false
            }
            if done { continuation.resume() }
        }
    }
}
private final class AccountReadStop: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var isStopped: Bool { lock.withLock { stopped } }
    func stop() { lock.withLock { stopped = true } }
}

/// Inert construction. One private bootstrap, bounded ordered writes and a
/// concurrent reader keep cancellation responsive during browser/network work.
public actor PipeAccountPort: AccountPort {
    private let python: URL, repository: URL
    private let pythonArguments: [String]
    private let bootstrap: AccountSecretBootstrap
    private let operationTimeout: TimeInterval
    private let writes = DispatchQueue(label: "relay.account.write")
    private let stop = AccountReadStop()
    private var process: Process?, receipt: AccountChildExit?
    private var input: FileHandle?, output: FileHandle?
    private var readerTask: Task<Void, Never>?, closingTask: Task<Void, Never>?
    private var retired = false, queuedBytes = 0, queuedCount = 0
    private struct Waiter {
        let request: AccountRequest
        let continuation: CheckedContinuation<AccountResponse, any Error>
        let authorization: @Sendable (AccountAuthorization) async -> Bool
        let timeout: Task<Void, Never>
        var pending: AccountResponse?
        var authorizationSeen = false
        var authorizationTask: Task<Bool, Never>?
        var terminal: AccountResponse?
    }
    private var waiters: [UUID: Waiter] = [:]
    private var seen: [UUID: AccountRequest] = [:]
    private var completed: [UUID: AccountResponse] = [:]
    private var completedOrder: [UUID] = []
    public private(set) var exitConfirmed = false
    public var isRunning: Bool { process?.isRunning == true }
    public init(python: URL, repository: URL, bootstrap: AccountSecretBootstrap,
                pythonArguments: [String] = [], operationTimeout: TimeInterval = 285) {
        self.python = python; self.repository = repository; self.bootstrap = bootstrap
        self.pythonArguments = pythonArguments; self.operationTimeout = operationTimeout
    }

    private func start() throws {
        guard !retired, bootstrap.purpose == .accountControl, operationTimeout > 0, operationTimeout <= 285 else { throw AccountError.closed }
        if process != nil { guard isRunning else { throw AccountError.closed }; return }
        let child = Process(), exit = AccountChildExit(), toChild = Pipe(), fromChild = Pipe()
        child.executableURL = python
        child.arguments = pythonArguments + ["-m", "relay_spike.account_bridge"]
        child.currentDirectoryURL = repository
        child.environment = ["PATH": "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1"]
        child.standardInput = toChild; child.standardOutput = fromChild; child.standardError = FileHandle.nullDevice
        child.terminationHandler = { _ in exit.record() }
        try child.run()
        toChild.fileHandleForReading.closeFile(); fromChild.fileHandleForWriting.closeFile()
        process = child; receipt = exit; input = toChild.fileHandleForWriting; output = fromChild.fileHandleForReading
        let writeFD = toChild.fileHandleForWriting.fileDescriptor, readFD = fromChild.fileHandleForReading.fileDescriptor
        guard fcntl(writeFD, F_SETNOSIGPIPE, 1) != -1,
              fcntl(writeFD, F_SETFL, fcntl(writeFD, F_GETFL) | O_NONBLOCK) != -1,
              fcntl(readFD, F_SETFL, fcntl(readFD, F_GETFL) | O_NONBLOCK) != -1 else { throw AccountError.closed }
        try enqueue(bootstrap.frame())
        let stop = self.stop
        readerTask = Task.detached { [weak self] in
            let decoder = AccountFrameDecoder(); var partialSince: UInt64?
            do {
                while !stop.isStopped {
                    if decoder.hasPartial {
                        if partialSince == nil { partialSince = DispatchTime.now().uptimeNanoseconds }
                        guard DispatchTime.now().uptimeNanoseconds - partialSince! < 3_000_000_000 else { throw AccountError.timedOut }
                    } else { partialSince = nil }
                    var descriptor = pollfd(fd: readFD, events: Int16(POLLIN), revents: 0)
                    let ready = Darwin.poll(&descriptor, 1, 100)
                    if ready < 0 && errno == EINTR { continue }
                    guard ready >= 0 else { throw AccountError.closed }
                    if ready == 0 { continue }
                    guard descriptor.revents & Int16(POLLIN | POLLHUP) != 0 else { throw AccountError.closed }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    let count = Darwin.read(readFD, &buffer, buffer.count)
                    if count < 0 && [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
                    guard count > 0 else { try decoder.finish(); throw AccountError.closed }
                    for frame in try decoder.feed(Data(buffer.prefix(count))) { await self?.receive(frame) }
                }
            } catch { await self?.failed() }
        }
    }
    private func enqueue(_ frame: Data) throws {
        guard !retired, let input, queuedCount < 32, queuedBytes + frame.count <= 262144 else { throw AccountError.overflow }
        queuedCount += 1; queuedBytes += frame.count
        let fd = input.fileDescriptor
        writes.async { [weak self] in
            var success = true
            do { try Self.write(frame, fd: fd) } catch { success = false }
            let result = success
            Task { await self?.writeFinished(frame.count, success: result) }
        }
    }
    private nonisolated static func write(_ bytes: Data, fd: Int32) throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
        var offset = 0
        while offset < bytes.count {
            guard DispatchTime.now().uptimeNanoseconds < deadline else { throw AccountError.timedOut }
            var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, 100)
            if ready < 0 && errno == EINTR { continue }
            guard ready >= 0 else { throw AccountError.closed }
            if ready == 0 { continue }
            guard descriptor.revents & Int16(POLLOUT) != 0 else { throw AccountError.closed }
            let count = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), min(4096, bytes.count - offset)) }
            if count < 0 && [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
            guard count > 0 else { throw AccountError.closed }; offset += count
        }
    }
    private func writeFinished(_ count: Int, success: Bool) {
        queuedCount -= 1; queuedBytes -= count
        if !success { failed() }
    }
    private func failed() {
        retired = true
        Task { await close() }
    }
    private func receive(_ frame: Data) {
        guard !retired else { return }
        do {
            let node = try AccountJSON.decode(frame)
            guard case .object(let value) = node else { throw AccountError.malformed }
            let kind = try value["kind"]?.string()
            if kind == "account_authorization" {
                let effect = try AccountAuthorization(data: frame)
                guard var waiter = waiters[effect.requestID], waiter.pending != nil, !waiter.authorizationSeen,
                      waiter.request.action == .connect || waiter.request.action == .enablePlan else { throw AccountError.malformed }
                let handler = waiter.authorization, authorizationTask = Task { await handler(effect) }
                waiter.authorizationSeen = true; waiter.authorizationTask = authorizationTask; waiters[effect.requestID] = waiter
                Task { if !(await authorizationTask.value) { await close() } }
            } else {
                let response = try AccountResponse(data: frame)
                guard var waiter = waiters[response.requestID], waiter.request.action == response.action else { throw AccountError.malformed }
                if response.revision == 1 {
                    if let old = waiter.pending { guard old == response else { throw AccountError.malformed } }
                    waiter.pending = response; waiters[response.requestID] = waiter
                } else {
                    if let held = waiter.terminal { guard held == response else { throw AccountError.malformed }; return }
                    if [.connected, .planPermissionMissing].contains(response.reason) {
                        guard waiter.authorizationSeen else { throw AccountError.malformed }
                    }
                    if let authorizationTask = waiter.authorizationTask {
                        waiter.terminal = response; waiters[response.requestID] = waiter
                        Task {
                            if await authorizationTask.value { finish(response) }
                            else { await close() }
                        }
                    } else { finish(response) }
                }
            }
        } catch { failed() }
    }
    private func finish(_ response: AccountResponse) {
        guard !retired, let waiter = waiters.removeValue(forKey: response.requestID) else { return }
        completed[response.requestID] = response; completedOrder.append(response.requestID)
        while completedOrder.count > 8 { completed.removeValue(forKey: completedOrder.removeFirst()) }
        waiter.timeout.cancel(); waiter.continuation.resume(returning: response)
    }
    public func perform(_ request: AccountRequest, authorization: @escaping @Sendable (AccountAuthorization) async -> Bool) async throws -> AccountResponse {
        guard !retired, waiters.count < 32, waiters[request.id] == nil else { throw AccountError.closed }
        do {
            if let original = seen[request.id] {
                guard original == request, let response = completed[request.id] else { throw AccountError.rejected }
                return response
            }
            guard seen.count < 512 else { throw AccountError.overflow }
            seen[request.id] = request
            try start(); let frame = try accountFrame(request.data())
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let limit = min(operationTimeout, [.connect, .enablePlan].contains(request.action) ? 285 : 20)
                    let timeout = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(limit)); await self?.close() } catch { }
                    }
                    waiters[request.id] = Waiter(request: request, continuation: continuation, authorization: authorization, timeout: timeout)
                    do { try enqueue(frame) } catch { failed() }
                }
            } onCancel: { Task { await self.close() } }
        } catch { await close(); throw AccountError.closed }
    }
    public func close() async {
        if let closingTask { await closingTask.value; return }
        retired = true; stop.stop()
        let child = process, receipt = self.receipt, reader = readerTask, input = self.input, output = self.output, writes = self.writes
        let task = Task {
            if let child, let receipt {
                if !receipt.hasExited, child.isRunning { child.terminate() }
                let deadline = DispatchTime.now().uptimeNanoseconds + 500_000_000
                while !receipt.hasExited && DispatchTime.now().uptimeNanoseconds < deadline { try? await Task.sleep(for: .milliseconds(10)) }
                if !receipt.hasExited, child.isRunning { kill(child.processIdentifier, SIGKILL) }
                await receipt.wait()
            }
            await reader?.value
            // Join IO before closing descriptors, preventing descriptor reuse
            // while a blocked writer or reader still owns its original FD.
            await withCheckedContinuation { continuation in writes.async { continuation.resume() } }
            try? input?.close(); try? output?.close()
        }
        closingTask = task; await task.value
        if process != nil { exitConfirmed = true }
        process = nil; self.receipt = nil; self.input = nil; self.output = nil; readerTask = nil
        let pending = waiters.values; waiters.removeAll()
        for waiter in pending { waiter.timeout.cancel(); waiter.continuation.resume(throwing: AccountError.closed) }
        // Keep the completed close task: this port is permanently retired.
    }
}
