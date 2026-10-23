import Darwin
import XCTest
@testable import RelayProfile

@MainActor final class ProfileProcessExitTests: XCTestCase {
    private func fixture(_ mode: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let module = root.appendingPathComponent("relay_spike")
        try FileManager.default.createDirectory(at: module, withIntermediateDirectories: true)
        let script = """
        import json, os, signal, struct, sys, time
        mode = "\(mode)"
        if mode == "ignore_term": signal.signal(signal.SIGTERM, signal.SIG_IGN)
        header = sys.stdin.buffer.read(4)
        if len(header) != 4: sys.exit(2)
        size, = struct.unpack(">I", header)
        sys.stdin.buffer.read(size)
        body = json.dumps({"ok": True, "pid": os.getpid()}).encode()
        sys.stdout.buffer.write(struct.pack(">I", len(body)) + body)
        sys.stdout.buffer.flush()
        if mode == "exited": sys.exit(0)
        if mode == "ignore_term":
            while True: time.sleep(60)
        sys.stdin.buffer.read()
        """
        try Data(script.utf8).write(to: module.appendingPathComponent("profile_bridge.py"))
        return root
    }

    func testMovableActorCloseWaitsForActualChildReapAcrossExitSchedules() async throws {
        let python = try ProfileTestEnvironment.python()
        for mode in ["eof", "exited", "ignore_term"] {
            let root = try fixture(mode)
            defer { try? FileManager.default.removeItem(at: root) }
            for _ in 0..<(mode == "ignore_term" ? 4 : 16) {
                let port = PipeProfilePort(python: python, repository: root)
                let response = try await port.request(Data("{\"command\":\"state\"}".utf8))
                let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: response) as? [String: Any])
                let pid = try XCTUnwrap(object["pid"] as? Int32)
                if mode == "exited" {
                    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                    while Darwin.kill(pid, 0) == 0 && ContinuousClock.now < deadline {
                        try await Task.sleep(for: .milliseconds(1))
                    }
                    XCTAssertEqual(Darwin.kill(pid, 0), -1, "Early-exit child did not terminate")
                    XCTAssertEqual(errno, ESRCH)
                }
                // Run shutdown from a separately scheduled task, with the port
                // actor free to move between cooperative executor threads.
                await Task.detached { await port.emergencyShutdown() }.value
                var status: Int32 = 0
                let result = Darwin.waitpid(pid, &status, WNOHANG)
                let observedError = errno
                XCTAssertEqual(result, -1, "Shutdown returned before Foundation reaped its child: " + mode)
                XCTAssertEqual(observedError, ECHILD, mode)
                let running = await port.isRunning
                XCTAssertFalse(running, mode)
                do {
                    _ = try await port.request(Data("{}".utf8))
                    XCTFail("Retired child owner restarted")
                } catch ProfileError.unavailable {}
            }
        }
    }
}
