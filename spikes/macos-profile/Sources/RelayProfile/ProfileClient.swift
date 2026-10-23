import CryptoKit
import Darwin
import Foundation

public protocol ProfilePort: Sendable {
    func request(_ data: Data) async throws -> Data
    func close() async
    /// Must independently retire helper/provider admission, fence pending
    /// requests and stop/reap the old helper. No default implementation.
    func emergencyShutdown() async
}

/// Final app injects its shared-helper transport through this port. The demo
/// uses PipeProfilePort; neither type creates a persistent plaintext store.
public struct ClosureProfilePort: ProfilePort {
    private let handler: @Sendable (Data) async throws -> Data
    private let closer: @Sendable () async -> Void
    private let emergency: @Sendable () async -> Void
    public init(request: @escaping @Sendable (Data) async throws -> Data,
                emergencyShutdown: @escaping @Sendable () async -> Void,
                close: @escaping @Sendable () async -> Void = {}) {
        handler = request; emergency = emergencyShutdown; closer = close
    }
    public func request(_ data: Data) async throws -> Data { try await handler(data) }
    public func close() async { await closer() }
    public func emergencyShutdown() async { await emergency() }
}

/// Lazy demo child. All IO is serialized, bounded and has a total per-frame
/// deadline. No helper is launched by construction or ordinary app startup.
public actor PipeProfilePort: ProfilePort {
    private let python: URL
    private let repository: URL
    private var process: Process?
    private var exitReceipt: ProfileProcessExitReceipt?
    private var shutdownTask: Task<Void, Never>?
    private var input: FileHandle?
    private var output: FileHandle?
    private var retired = false
    public var isRunning: Bool { process?.isRunning ?? false }
    public init(python: URL, repository: URL) { self.python = python; self.repository = repository }

    private func start() throws {
        guard process == nil else {
            if process?.isRunning != true { throw ProfileError.transport }
            return
        }
        let child = Process()
        let receipt = ProfileProcessExitReceipt()
        let toChild = Pipe(), fromChild = Pipe()
        child.executableURL = python
        child.arguments = ["-m", "relay_spike.profile_bridge"]
        child.currentDirectoryURL = repository
        child.environment = ["PATH": "/usr/bin:/bin:/opt/homebrew/bin", "PYTHONDONTWRITEBYTECODE": "1"]
        child.standardInput = toChild
        child.standardOutput = fromChild
        child.standardError = FileHandle.nullDevice
        // Launch can occur on a different cooperative thread from shutdown.
        // Default termination notifications and waitUntilExit use run loops;
        // the prelaunch callback supplies an executor-independent exit receipt.
        child.terminationHandler = { receipt.record($0.terminationStatus) }
        try child.run()
        toChild.fileHandleForReading.closeFile()
        fromChild.fileHandleForWriting.closeFile()
        input = toChild.fileHandleForWriting
        output = fromChild.fileHandleForReading
        process = child
        exitReceipt = receipt
    }

    private func wait(_ fd: Int32, event: Int16, until deadline: UInt64) throws {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw ProfileError.transport }
            let milliseconds = Int32(min((deadline - now) / 1_000_000 + 1, 1000))
            var descriptor = pollfd(fd: fd, events: event, revents: 0)
            let result = Darwin.poll(&descriptor, 1, milliseconds)
            if result < 0 && errno == EINTR { continue }
            guard result >= 0 else { throw ProfileError.transport }
            if result > 0 {
                guard descriptor.revents & event != 0 else { throw ProfileError.transport }
                return
            }
        }
    }

    private func writeAll(_ data: Data, fd: Int32, deadline: UInt64) throws {
        var offset = 0
        while offset < data.count {
            try wait(fd, event: Int16(POLLOUT), until: deadline)
            let count = data.withUnsafeBytes { pointer in
                Darwin.write(fd, pointer.baseAddress!.advanced(by: offset), min(4096, data.count - offset))
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw ProfileError.transport }
            offset += count
        }
    }

    private func readExact(_ count: Int, fd: Int32, deadline: UInt64) throws -> Data {
        var result = Data(count: count), offset = 0
        while offset < count {
            try wait(fd, event: Int16(POLLIN), until: deadline)
            let received = result.withUnsafeMutableBytes { pointer in
                Darwin.read(fd, pointer.baseAddress!.advanced(by: offset), count - offset)
            }
            if received < 0 && errno == EINTR { continue }
            guard received > 0 else { throw ProfileError.transport }
            offset += received
        }
        return result
    }

    public func request(_ data: Data) async throws -> Data {
        guard !retired, shutdownTask == nil else { throw ProfileError.unavailable }
        guard !data.isEmpty, data.count <= 16 * 1024 else { throw ProfileError.invalidPayload }
        do {
            try start()
            guard let input, let output else { throw ProfileError.transport }
            // Avoid SIGPIPE terminating the app if the child exits mid-write.
            guard fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { throw ProfileError.transport }
            let deadline = DispatchTime.now().uptimeNanoseconds + 15_000_000_000
            var length = UInt32(data.count).bigEndian
            let header = withUnsafeBytes(of: &length) { Data($0) }
            try writeAll(header + data, fd: input.fileDescriptor, deadline: deadline)
            let responseHeader = try readExact(4, fd: output.fileDescriptor, deadline: deadline)
            let size = responseHeader.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard size > 0, size <= 16 * 1024 else { throw ProfileError.transport }
            return try readExact(Int(size), fd: output.fileDescriptor, deadline: deadline)
        } catch {
            await shutdown()
            throw ProfileError.transport
        }
    }

    private func shutdown() async {
        if let shutdownTask { await shutdownTask.value; return }
        try? input?.close(); try? output?.close()
        input = nil; output = nil
        guard let child = process, let receipt = exitReceipt else { return }
        let task = Task {
            if !receipt.hasExited, child.isRunning { child.terminate() }
            let deadline = DispatchTime.now().uptimeNanoseconds + 500_000_000
            while !receipt.hasExited && DispatchTime.now().uptimeNanoseconds < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            if !receipt.hasExited, child.isRunning { kill(child.processIdentifier, SIGKILL) }
            // Grace expiration escalates the signal; it never proves quiescence.
            // Keep ownership/admission closed until Foundation confirms exit.
            _ = await receipt.wait()
        }
        shutdownTask = task
        await task.value
        process = nil
        exitReceipt = nil
        shutdownTask = nil
    }
    public func close() async { await shutdown() }
    public func emergencyShutdown() async {
        retired = true
        await shutdown()
    }
}

public enum ProfileCloseOutcome: Sendable, Equatable {
    case locked
    case helperStopped
}

@MainActor
public final class ProfileClient {
    private let port: any ProfilePort
    private var transferring = false
    private var generation = UUID()
    private var requestsInFlight = 0
    private var retired = false
    private var closing: Task<ProfileCloseOutcome, Never>?
    public init(port: any ProfilePort) { self.port = port }
    private func exchange(_ message: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        guard data.count <= 16 * 1024 else { throw ProfileError.invalidPayload }
        let response = try await port.request(data)
        guard response.count <= 16 * 1024,
              let object = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              object["ok"] as? Bool == true else { throw ProfileError.rejected }
        return object
    }
    private func operationGeneration() throws -> UUID {
        guard !retired, closing == nil else { throw ProfileError.unavailable }
        return generation
    }
    private func send(_ message: [String: Any], generation expected: UUID) async throws -> [String: Any] {
        guard !retired, closing == nil, generation == expected else { throw ProfileError.unavailable }
        requestsInFlight += 1
        defer { requestsInFlight -= 1 }
        let response = try await exchange(message)
        guard !retired, closing == nil, generation == expected else { throw ProfileError.unavailable }
        return response
    }
    public func command(_ message: [String: Any]) async throws -> [String: Any] {
        guard !transferring else { throw ProfileError.transport }
        return try await send(message, generation: operationGeneration())
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private func transfer(_ data: Data, begin: [String: Any], commit: String) async throws -> [String: Any] {
        guard !transferring else { throw ProfileError.transport }
        let operation = try operationGeneration()
        transferring = true; defer { if operation == generation { transferring = false } }
        var manifest = begin
        manifest["size"] = data.count; manifest["sha256"] = digest(data)
        do {
            _ = try await send(manifest, generation: operation)
            for offset in stride(from: 0, to: data.count, by: 4096) {
                _ = try await send(["command": "transfer_chunk", "offset": offset,
                    "data": data.subdata(in: offset..<min(offset + 4096, data.count)).base64EncodedString()], generation: operation)
            }
            return try await send(["command": commit], generation: operation)
        } catch {
            _ = try? await send(["command": "transfer_abort"], generation: operation)
            throw error
        }
    }
    public func load(_ snapshot: Data) async throws -> [String: Any] {
        guard !snapshot.isEmpty, snapshot.count <= ProfileVault.maxPayloadBytes else { throw ProfileError.invalidPayload }
        return try await transfer(snapshot, begin: ["command": "load_begin"], commit: "load_commit")
    }
    public func select(_ data: Data, fileType: String, purpose: String, label: String,
                       role: String, project: String?) async throws -> [String: Any] {
        guard !data.isEmpty, data.count <= 2 * 1024 * 1024 else { throw ProfileError.invalidPayload }
        var fields: [String: Any] = ["command": "select_begin", "file_type": fileType,
                                   "purpose": purpose, "label": label, "role": role]
        if let project, !project.isEmpty { fields["project_hint"] = project }
        return try await transfer(data, begin: fields, commit: "select_commit")
    }
    public func snapshot() async throws -> Data {
        guard !transferring else { throw ProfileError.transport }
        let operation = try operationGeneration()
        transferring = true; defer { if operation == generation { transferring = false } }
        let manifest = try await send(["command": "snapshot_begin"], generation: operation)
        guard let size = manifest["size"] as? Int, size > 0, size <= ProfileVault.maxPayloadBytes,
              let expectedDigest = manifest["sha256"] as? String else { throw ProfileError.invalidPayload }
        var data = Data()
        for offset in stride(from: 0, to: size, by: 4096) {
            let part = try await send(["command": "snapshot_chunk", "offset": offset], generation: operation)
            guard part["offset"] as? Int == offset, let encoded = part["data"] as? String,
                  let bytes = Data(base64Encoded: encoded), bytes.count == min(4096, size-offset)
            else { throw ProfileError.invalidPayload }
            data.append(bytes)
        }
        _ = try await send(["command": "snapshot_end"], generation: operation)
        guard data.count == size, digest(data) == expectedDigest else { throw ProfileError.invalidPayload }
        return data
    }
    @discardableResult public func close() async -> ProfileCloseOutcome {
        if let closing { return await closing.value }
        if retired { return .helperStopped }
        let forceShutdown = requestsInFlight > 0 || transferring
        generation = UUID()
        transferring = false
        let task = Task { @MainActor in
            if !forceShutdown {
                do {
                    let response = try await self.exchange(["command": "lock"])
                    guard response["locked"] as? Bool == true, response["ready"] as? Bool == false
                    else { throw ProfileError.rejected }
                    await self.port.close()
                    return ProfileCloseOutcome.locked
                } catch { /* Missing lock acknowledgement requires independent retirement. */ }
            }
            self.retired = true
            await self.port.emergencyShutdown()
            return ProfileCloseOutcome.helperStopped
        }
        closing = task
        let outcome = await task.value
        closing = nil
        return outcome
    }
}
