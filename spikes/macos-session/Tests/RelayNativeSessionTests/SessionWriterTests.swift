import Darwin
import Foundation
import XCTest
@testable import RelayNativeSession

final class FailureProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func fail() { lock.withLock { value = true } }
    var failed: Bool { lock.withLock { value } }
}
final class SessionWriterTests: XCTestCase {
    private func event(text: String = "user_stop") -> NativeSessionEvent {
        NativeSessionEvent(captureSessionID: UUID(), sessionEpoch: 1, eventSequence: 1,
            presentationGeneration: 1, kind: .stopping, sourceCode: nil, streamGeneration: nil,
            emittedUptimeNanoseconds: 1, payload: ["reasonCode": .string(text)])
    }
    func testDedicatedWriterProducesExactFrameAndClosesOwnedDescriptor() async throws {
        var fds: [Int32] = [0, 0]; XCTAssertEqual(pipe(&fds), 0)
        defer { Darwin.close(fds[0]); Darwin.close(fds[1]) }
        let writer = try BoundedSessionEventWriter(descriptor: fds[1], onFailure: {})
        let expected = try event().encodedFrame()
        // Preserve the event identity used to obtain expected bytes.
        let sent = event(); try writer.enqueue(sent)
        let readDescriptor = fds[0]
        let data = try await Task.detached {
            var buffer = [UInt8](repeating: 0, count: 16_388)
            let count = Darwin.read(readDescriptor, &buffer, buffer.count)
            guard count > 0 else { throw NativeSessionError.transportClosed }
            return Data(buffer.prefix(count))
        }.value
        XCTAssertEqual(data, try sent.encodedFrame())
        XCTAssertGreaterThan(expected.count, 4)
        writer.close()
    }
    func testBlockedReaderIsBoundedAndRetiresInsteadOfDroppingControls() async throws {
        var fds: [Int32] = [0, 0]; XCTAssertEqual(pipe(&fds), 0)
        defer { Darwin.close(fds[0]); Darwin.close(fds[1]) }
        let failure = FailureProbe()
        let writer = try BoundedSessionEventWriter(descriptor: fds[1], maximumFrames: 2,
            maximumBytes: 32_768, writeDeadlineMilliseconds: 30, onFailure: failure.fail)
        var rejected = false
        for _ in 0..<100 {
            do { try writer.enqueue(event(text: String(repeating: "x", count: 15_000))) }
            catch { rejected = true; break }
        }
        XCTAssertTrue(rejected)
        for _ in 0..<500 {
            if failure.failed { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(failure.failed)
        XCTAssertThrowsError(try writer.enqueue(event()))
        writer.close()
    }
    func testClosedReaderReportsFailureWithoutSIGPIPE() async throws {
        var fds: [Int32] = [0, 0]; XCTAssertEqual(pipe(&fds), 0)
        Darwin.close(fds[0]); defer { Darwin.close(fds[1]) }
        let failure = FailureProbe()
        let writer = try BoundedSessionEventWriter(descriptor: fds[1], onFailure: failure.fail)
        try writer.enqueue(event())
        for _ in 0..<500 {
            if failure.failed { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(failure.failed)
        writer.close()
    }
}

extension SessionWriterTests {
    func testSingleStalledFrameHitsDeadlineEvenWithoutQueueOverflow() async throws {
        var fds: [Int32] = [0, 0]; XCTAssertEqual(pipe(&fds), 0)
        defer { Darwin.close(fds[0]); Darwin.close(fds[1]) }
        XCTAssertEqual(fcntl(fds[1], F_SETFL, fcntl(fds[1], F_GETFL) | O_NONBLOCK), 0)
        let filler = [UInt8](repeating: 1, count: 4096)
        while filler.withUnsafeBytes({ Darwin.write(fds[1], $0.baseAddress!, $0.count) }) > 0 {}
        let failure = FailureProbe()
        let writer = try BoundedSessionEventWriter(descriptor: fds[1], writeDeadlineMilliseconds: 20, onFailure: failure.fail)
        try writer.enqueue(event())
        for _ in 0..<500 { if failure.failed { break }; try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(failure.failed)
        let flushed = await writer.flush(timeoutMilliseconds: 50)
        XCTAssertFalse(flushed)
        writer.close()
    }
}
