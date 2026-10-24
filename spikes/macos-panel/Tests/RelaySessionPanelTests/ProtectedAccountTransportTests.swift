import Foundation
import RelayAccount
import RelayProfile
import XCTest
@testable import RelaySessionPanel

private struct SyntheticTransportKey: ProfileKeyProvider {
    func key(createIfMissing: Bool) throws -> Data { Data(repeating: 43, count: 32) }
}
@MainActor final class ProtectedAccountTransportTests: XCTestCase {
    private var root: URL { var value = URL(fileURLWithPath: #filePath); for _ in 0..<5 { value.deleteLastPathComponent() }; return value }
    private func temporary() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: false); return value
    }
    func testProtectedTransportRefusesMissingOrWrongPurposeSecretBeforeLaunchingAnything() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let control = try AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: SyntheticTransportKey()).controlBootstrap(generation: UUID(), createKey: true)
        for bootstrap in [nil, control] {
            let helper = HelperTransport(root: root, python: URL(fileURLWithPath: "/nonexistent-must-not-launch"), mode: .protectedOAuth,
                accountBootstrap: bootstrap, model: "gpt-synthetic-first", onFrame: { _ in }, onFailure: {})
            do { try helper.start(); XCTFail("Protected transport accepted missing/wrong-purpose authority") }
            catch { guard case PanelBridgeError.malformed = error else { return XCTFail("Validation did not precede process launch") } }
            await helper.shutdownAndWait()
        }
        let fixture = HelperTransport(root: root, python: URL(fileURLWithPath: "/nonexistent-must-not-launch"), mode: .fixture,
            accountBootstrap: control, onFrame: { _ in }, onFailure: {})
        XCTAssertThrowsError(try fixture.start())
    }
    func testActualWriterPlacesIssuedPrivateBootstrapBeforeNormalFramesAndArgumentsContainNoSecret() async throws {
        let directory = try temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let interpreter = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"]))
        let log = directory.appendingPathComponent("account-metadata.jsonl"), record = directory.appendingPathComponent("frame-kinds.json")
        let storage = AccountStorage(sharedDirectory: directory.appendingPathComponent("Relay"), keys: SyntheticTransportKey())
        let repository = root
        let account = AccountController(storage: storage, portFactory: { bootstrap in
            PipeAccountPort(python: interpreter, repository: repository, bootstrap: bootstrap,
                pythonArguments: [repository.appendingPathComponent("tests/support/account_backend_helper.py").path, "--synthetic-account-test", "--log", log.path])
        }, retireInference: {}, openBrowser: { _ in true })
        await account.connect()
        let bootstrap = try XCTUnwrap(account.sessionBootstrap()), selection = try XCTUnwrap(account.inferenceSelection)
        let script = """
        import json,struct,sys
        def exact(n):
            value=b''
            while len(value)<n:
                part=sys.stdin.buffer.read(n-len(value))
                if not part: raise EOFError()
                value+=part
            return value
        kinds=[]
        for _ in range(2):
            item=json.loads(exact(struct.unpack('>I',exact(4))[0]))
            kinds.append({'kind':item['kind'],'purpose':item.get('purpose')})
        with open(sys.argv[1],'x') as output: json.dump({'frames':kinds,'arguments':sys.argv[2:]},output)
        """
        let helper = HelperTransport(root: root, python: interpreter, pythonArguments: ["-u", "-c", script, record.path], mode: .protectedOAuth,
            accountBootstrap: bootstrap, model: selection.model, role: "developer", onFrame: { _ in }, onFailure: {})
        try helper.start(); try helper.sendJSON(Data("{\"kind\":\"synthetic_normal\"}".utf8))
        for _ in 0..<2000 {
            if FileManager.default.fileExists(atPath: record.path) { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        await helper.shutdownAndWait(); await account.close()
        let data = try Data(contentsOf: record), value = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let frames = value["frames"] as! [[String: Any]]
        XCTAssertEqual(frames.map { $0["kind"] as! String }, ["account_secret_bootstrap", "synthetic_normal"])
        XCTAssertEqual(frames[0]["purpose"] as? String, "oauth_session")
        XCTAssertEqual(value["arguments"] as? [String], ["-m", "relay_spike.session_host", "--role", "developer", "--oauth", "--protected-account", "--model", "gpt-synthetic-first"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(Data(repeating: 43, count: 32).base64EncodedString()))
    }
}
