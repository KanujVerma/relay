import Foundation

enum ProfileTestEnvironment {
    static func python() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let paths: [String]
        if let explicit = environment["RELAY_TEST_PYTHON"], !explicit.isEmpty {
            paths = [explicit]
        } else {
            paths = (environment["PATH"] ?? "").split(separator: ":")
                .map { URL(fileURLWithPath: String($0)).appendingPathComponent("python3").path }
        }
        guard let path = paths.first(where: { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) })
        else { throw NSError(domain: "RelayProfileTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Set RELAY_TEST_PYTHON or put Python 3.11+ on PATH."]) }
        let python = URL(fileURLWithPath: path)
        let check = Process()
        check.executableURL = python
        check.arguments = ["-c", "import sqlite3,sys; sys.exit(0 if sys.version_info >= (3,11) and hasattr(sqlite3.Connection,'serialize') and hasattr(sqlite3.Connection,'deserialize') else 1)"]
        check.standardOutput = FileHandle.nullDevice
        check.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        check.terminationHandler = { _ in exited.signal() }
        try check.run()
        guard exited.wait(timeout: .now() + 5) == .success else {
            if check.isRunning { check.terminate() }
            throw NSError(domain: "RelayProfileTests", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Python capability check exceeded its five-second deadline."])
        }
        guard check.terminationStatus == 0 else {
            throw NSError(domain: "RelayProfileTests", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Native child tests require Python 3.11+ with SQLite serialization."])
        }
        return python
    }
}
