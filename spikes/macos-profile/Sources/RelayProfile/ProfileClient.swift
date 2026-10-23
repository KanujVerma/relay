import CryptoKit
import Darwin
import Foundation

public protocol ProfilePort: Sendable {
    func request(_ data: Data) async throws -> Data
    func close() async
}

/// Final app injects its shared-helper transport through this port. The demo
/// uses PipeProfilePort; neither type creates a persistent plaintext store.
public struct ClosureProfilePort: ProfilePort {
    private let handler: @Sendable (Data) async throws -> Data
    private let closer: @Sendable () async -> Void
    public init(request: @escaping @Sendable (Data) async throws -> Data,
                close: @escaping @Sendable () async -> Void = {}) {
        handler = request; closer = close
    }
    public func request(_ data: Data) async throws -> Data { try await handler(data) }
    public func close() async { await closer() }
}

/// Lazy demo child. All IO is serialized, bounded and has a total per-frame
/// deadline. No helper is launched by construction or ordinary app startup.
public actor PipeProfilePort: ProfilePort {
    private let python: URL
    private let repository: URL
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    public var isRunning: Bool { process?.isRunning ?? false }
    public init(python: URL, repository: URL) { self.python = python; self.repository = repository }

    private func start() throws {
        guard process == nil else {
            if process?.isRunning != true { throw ProfileError.transport }
            return
        }
        let child = Process()
        let toChild = Pipe(), fromChild = Pipe()
        child.executableURL = python
        child.arguments = ["-m", "relay_spike.profile_bridge"]
        child.currentDirectoryURL = repository
        child.environment = ["PATH": "/usr/bin:/bin:/opt/homebrew/bin", "PYTHONDONTWRITEBYTECODE": "1"]
        child.standardInput = toChild
        child.standardOutput = fromChild
        child.standardError = FileHandle.nullDevice
        try child.run()
        toChild.fileHandleForReading.closeFile()
        fromChild.fileHandleForWriting.closeFile()
        input = toChild.fileHandleForWriting
        output = fromChild.fileHandleForReading
        process = child
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
            shutdown()
            throw ProfileError.transport
        }
    }

    private func shutdown() {
        try? input?.close(); try? output?.close()
        input = nil; output = nil
        if let process, process.isRunning {
            process.terminate()
            let deadline = DispatchTime.now().uptimeNanoseconds + 500_000_000
            while process.isRunning && DispatchTime.now().uptimeNanoseconds < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        process = nil
    }
    public func close() async { shutdown() }
}

@MainActor
public final class ProfileClient {
    private let port: any ProfilePort
    private var transferring = false
    public init(port: any ProfilePort) { self.port = port }
    private func send(_ message: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        guard data.count <= 16 * 1024 else { throw ProfileError.invalidPayload }
        let response = try await port.request(data)
        guard response.count <= 16 * 1024,
              let object = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              object["ok"] as? Bool == true else { throw ProfileError.rejected }
        return object
    }
    public func command(_ message: [String: Any]) async throws -> [String: Any] {
        guard !transferring else { throw ProfileError.transport }
        return try await send(message)
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private func transfer(_ data: Data, begin: [String: Any], commit: String) async throws -> [String: Any] {
        guard !transferring else { throw ProfileError.transport }
        transferring = true; defer { transferring = false }
        var manifest = begin
        manifest["size"] = data.count; manifest["sha256"] = digest(data)
        do {
            _ = try await send(manifest)
            for offset in stride(from: 0, to: data.count, by: 4096) {
                _ = try await send(["command": "transfer_chunk", "offset": offset,
                    "data": data.subdata(in: offset..<min(offset + 4096, data.count)).base64EncodedString()])
            }
            return try await send(["command": commit])
        } catch {
            _ = try? await send(["command": "transfer_abort"])
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
        transferring = true; defer { transferring = false }
        let manifest = try await send(["command": "snapshot_begin"])
        guard let size = manifest["size"] as? Int, size > 0, size <= ProfileVault.maxPayloadBytes,
              let expectedDigest = manifest["sha256"] as? String else { throw ProfileError.invalidPayload }
        var data = Data()
        for offset in stride(from: 0, to: size, by: 4096) {
            let part = try await send(["command": "snapshot_chunk", "offset": offset])
            guard part["offset"] as? Int == offset, let encoded = part["data"] as? String,
                  let bytes = Data(base64Encoded: encoded), bytes.count == min(4096, size-offset)
            else { throw ProfileError.invalidPayload }
            data.append(bytes)
        }
        _ = try await send(["command": "snapshot_end"])
        guard data.count == size, digest(data) == expectedDigest else { throw ProfileError.invalidPayload }
        return data
    }
    public func close() async {
        // Retire the profile in the shared helper even if its transport stays
        // alive for the conversation engine. The demo port then reaps its child.
        _ = try? await send(["command": "lock"])
        await port.close()
    }
}
