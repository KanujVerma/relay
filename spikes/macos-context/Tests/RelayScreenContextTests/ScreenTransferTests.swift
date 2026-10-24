import XCTest
@testable import RelayScreenContext

@MainActor final class ScreenTransferTests: XCTestCase {
    func observed() async throws -> (ScreenContextCoordinator, ScreenSnapshot) {
        let coordinator = ScreenContextCoordinator(provider: FakeFrames(), recognizer: FakeOCR(), now: { 100 })
        coordinator.enable(); coordinator.select(sourceA); coordinator.supersede(with: requestA)
        guard case .captured(let snapshot) = await coordinator.capture(for: requestA) else { throw ScreenFailure.unavailable }
        return (coordinator,snapshot)
    }
    func testTextTransferContainsExactSupplementalFieldsWithoutImageBytes() async throws {
        let (_,snapshot) = try await observed()
        let data = try ScreenContextWire.textFrame(snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion","kind","captureSessionID","sessionEpoch","presentationGeneration","requestID","source","selectionRevision","permissionRevision","capturedUptimeNanoseconds","contentDigest","imageDigest","text","provenance"])
        XCTAssertEqual(object["kind"] as? String, "screen_context")
        XCTAssertEqual(object["text"] as? String, "def solve(items):\n    return len(items)")
        XCTAssertEqual(object["requestID"] as? String, "22222222-2222-2222-2222-222222222222")
        XCTAssertLessThanOrEqual(data.count, 16384)
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "screen_context_v1.synthetic", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? NSDictionary)
        XCTAssertEqual(object as NSDictionary, fixture)
    }
    func testRetirementFrameUsesOriginalRequestAndRevisionsOnly() async throws {
        let (coordinator,snapshot) = try await observed()
        coordinator.select(sourceB)
        let frame = try ScreenContextWire.retiredFrame(snapshot, reason: .selectionChanged)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: frame) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion","kind","captureSessionID","sessionEpoch","presentationGeneration","requestID","selectionRevision","permissionRevision","reasonCode"])
        XCTAssertEqual(object["selectionRevision"] as? Int,1)
        XCTAssertEqual(object["requestID"] as? String,"22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(object["reasonCode"] as? String,"selection_changed")
        let url = try XCTUnwrap(Bundle.module.url(forResource: "screen_context_retired_v1.synthetic", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary)
        XCTAssertEqual(object as NSDictionary,fixture)
    }
    func testImagePortDefaultsOffAndEnabledFramesAreBounded() async throws {
        let (coordinator,snapshot) = try await observed()
        XCTAssertThrowsError(try coordinator.makeImageTransfer(for: snapshot))
        let transfer = try coordinator.makeImageTransfer(for: snapshot, imageContextEnabled: true)
        var frames: [[String: Any]] = []
        var serialized = [try ScreenContextWire.textFrame(snapshot)]
        while let frame = try transfer.nextFrame() {
            serialized.append(frame)
            XCTAssertLessThanOrEqual(frame.count, 16384)
            frames.append(try XCTUnwrap(JSONSerialization.jsonObject(with: frame) as? [String: Any]))
        }
        XCTAssertEqual(frames.first?["kind"] as? String,"screen_image_begin")
        XCTAssertEqual(frames.last?["kind"] as? String,"screen_image_end")
        let chunks = frames.filter { $0["kind"] as? String == "screen_image_chunk" }
        XCTAssertFalse(chunks.isEmpty)
        var data = Data()
        for (index,chunk) in chunks.enumerated() {
            XCTAssertEqual(chunk["index"] as? Int,index)
            let encoded = try XCTUnwrap(chunk["data"] as? String)
            XCTAssertLessThanOrEqual(encoded.utf8.count,8192)
            let bytes = try XCTUnwrap(Data(base64Encoded: encoded))
            XCTAssertLessThanOrEqual(bytes.count,6144)
            data.append(bytes)
        }
        XCTAssertEqual(Array(data.prefix(8)), [137,80,78,71,13,10,26,10])
        XCTAssertEqual(frames.first?["totalBytes"] as? Int,data.count)
        if let destination = ProcessInfo.processInfo.environment["RELAY_SCREEN_SYNTHETIC_EXPORT"] {
            // Explicit test-only cross-language export of generated pixels, never a user screenshot.
            var output = Data()
            for frame in serialized { output.append(frame); output.append(10) }
            try output.write(to: URL(fileURLWithPath: destination), options: .atomic)
        }
    }
    func testSelectionChangeRetiresImageTransferAndReleasesBytes() async throws {
        let (coordinator,snapshot) = try await observed()
        let transfer = try coordinator.makeImageTransfer(for: snapshot, imageContextEnabled: true)
        _ = try transfer.nextFrame()
        coordinator.select(sourceB)
        XCTAssertThrowsError(try transfer.nextFrame())
        XCTAssertEqual(transfer.retainedByteCount,0)
    }
    func testValidationKeepsOriginalPreviewPixelIdentity() async throws {
        let frames = FakeFrames()
        let coordinator = ScreenContextCoordinator(provider: frames, recognizer: FakeOCR(), now: { 100 })
        coordinator.enable(); coordinator.select(sourceA); coordinator.supersede(with: requestA)
        guard case .captured(let snapshot) = await coordinator.capture(for: requestA) else { return XCTFail() }
        frames.color = 1
        let current = await coordinator.validateCurrent(snapshot, for: requestA)
        XCTAssertTrue(current)
        let preview = try XCTUnwrap(coordinator.preview)
        XCTAssertEqual(try ScreenContextCoordinator.digest(preview),snapshot.imageDigest)
    }
}
