import XCTest
import CoreGraphics
@testable import RelayScreenContext

@MainActor final class ScreenContextCoordinatorTests: XCTestCase {
    func testSelectedCapturePreservesOriginalRequestAndOCRLines() async throws {
        let provider = FakeFrames()
        let coordinator = ScreenContextCoordinator(provider: provider, recognizer: FakeOCR(), now: { 100 })
        coordinator.enable()
        coordinator.select(sourceA)
        let request = requestA
        coordinator.supersede(with: request)
        let result = await coordinator.capture(for: request)
        guard case .captured(let snapshot) = result else { return XCTFail("selected request should capture") }
        XCTAssertEqual(snapshot.request, request)
        XCTAssertEqual(snapshot.source, sourceA)
        XCTAssertEqual(snapshot.capturedUptimeNanoseconds, 90)
        XCTAssertEqual(snapshot.text, "def solve(items):\n    return len(items)")
        XCTAssertEqual(snapshot.lines.count, 2)
        XCTAssertEqual(snapshot.contentDigest.count, 64)
    }
}

let sourceA = ScreenSource(windowID: 11, bundleID: "example.editor", processID: 123, label: "Editor window")
let sourceB = ScreenSource(windowID: 12, bundleID: "example.browser", processID: 124, label: "Problem window")
let requestA = ScreenRequest(sessionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, sessionEpoch: 1,
                             presentationGeneration: 1, requestID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)

@MainActor final class FakeFrames: ScreenFrameProvider {
    var captureCount = 0
    var error: ScreenFailure?
    var gate: CheckedContinuation<Void, Never>?
    var holds = false
    var color: CGFloat = 0
    func capture(source: ScreenSource) async throws -> ScreenFrame {
        captureCount += 1
        if holds { await withCheckedContinuation { gate = $0 } }
        if let error { throw error }
        return ScreenFrame(image: syntheticImage(color: color), capturedUptimeNanoseconds: 90)
    }
    func release() { holds = false; gate?.resume(); gate = nil }
}
struct FakeOCR: ScreenTextRecognizer {
    func recognize(_ image: CGImage) async throws -> [OCRLine] {
        [OCRLine(text: "def solve(items):", bounds: CGRect(x: 0.1, y: 0.8, width: 0.7, height: 0.1), confidence: 0.9),
         OCRLine(text: "    return len(items)", bounds: CGRect(x: 0.2, y: 0.6, width: 0.7, height: 0.1), confidence: 0.8)]
    }
}
func syntheticImage(color: CGFloat = 0) -> CGImage {
    let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: color, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    return context.makeImage()!
}

extension ScreenContextCoordinatorTests {
    func configured(_ frames: FakeFrames = FakeFrames(), recognizer: any ScreenTextRecognizer = FakeOCR()) -> ScreenContextCoordinator {
        let coordinator = ScreenContextCoordinator(provider: frames, recognizer: recognizer, now: { 100 })
        coordinator.enable(); coordinator.select(sourceA); coordinator.supersede(with: requestA)
        return coordinator
    }
    func waitForCapture(_ frames: FakeFrames) async {
        for _ in 0..<1000 { if frames.gate != nil { return }; await Task.yield() }
        XCTFail("capture did not reach provider")
    }
    func testDefaultLaunchDoesNotReadScreen() async {
        let frames = FakeFrames()
        let coordinator = ScreenContextCoordinator(provider: frames, recognizer: FakeOCR())
        let result = await coordinator.capture(for: requestA)
        XCTAssertEqual(result, .unavailable(.disabled))
        XCTAssertEqual(frames.captureCount, 0)
    }
    func testSelectionChangeRetiresInFlightAndDoesNotRestampIt() async {
        let frames = FakeFrames(); frames.holds = true
        let coordinator = configured(frames)
        let pending = Task { await coordinator.capture(for: requestA) }
        await waitForCapture(frames)
        coordinator.select(sourceB)
        frames.release()
        let result = await pending.value
        XCTAssertEqual(result, .unavailable(.retired))
        XCTAssertNil(coordinator.snapshot)
        XCTAssertNil(coordinator.preview)
    }
    func testSupersedingQuestionRetiresOldCompletion() async {
        let frames = FakeFrames(); frames.holds = true
        let coordinator = configured(frames)
        let pending = Task { await coordinator.capture(for: requestA) }
        await waitForCapture(frames)
        coordinator.supersede(with: ScreenRequest(sessionID: requestA.sessionID, sessionEpoch: 1,
                                                 presentationGeneration: 2, requestID: UUID()))
        frames.release()
        let result = await pending.value
        XCTAssertEqual(result, .unavailable(.retired))
        XCTAssertNil(coordinator.snapshot)
    }
    func testRevokeRetiresBeforeCallbackAndRejectsLateCompletion() async {
        let frames = FakeFrames()
        let coordinator = configured(frames)
        _ = await coordinator.capture(for: requestA)
        var callbackHadNoSnapshot = false
        coordinator.onInvalidation = { _ in callbackHadNoSnapshot = coordinator.snapshot == nil && coordinator.preview == nil }
        coordinator.revoke()
        XCTAssertTrue(callbackHadNoSnapshot)
        XCTAssertNil(coordinator.snapshot)
        let result = await coordinator.capture(for: requestA)
        XCTAssertEqual(result, .unavailable(.disabled))
    }
    func testDisableRetiresInFlight() async {
        let frames = FakeFrames(); frames.holds = true
        let coordinator = configured(frames)
        let pending = Task { await coordinator.capture(for: requestA) }
        await waitForCapture(frames)
        coordinator.disable(); frames.release()
        let result = await pending.value
        XCTAssertEqual(result, .unavailable(.retired))
        XCTAssertNil(coordinator.snapshot)
    }
    func testSecondCaptureIsBusyUntilFirstActuallyQuiesces() async {
        let frames = FakeFrames(); frames.holds = true
        let coordinator = configured(frames)
        let pending = Task { await coordinator.capture(for: requestA) }
        await waitForCapture(frames)
        frames.holds = false
        let second = await coordinator.capture(for: requestA)
        XCTAssertEqual(second, .unavailable(.busy))
        XCTAssertEqual(frames.captureCount, 1)
        frames.release(); _ = await pending.value
    }
    func testDeadlineReturnsBeforeUncooperativeCaptureAndKeepsBackpressure() async {
        let frames = FakeFrames(); frames.holds = true
        let coordinator = configured(frames)
        let pending = Task { await coordinator.capture(for: requestA, budgetNanoseconds: 5_000_000) }
        await waitForCapture(frames)
        let cleanup = Task { try? await Task.sleep(for: .milliseconds(150)); frames.release() }
        let result = await pending.value
        XCTAssertEqual(result, .unavailable(.timedOut))
        if frames.gate != nil {
            let blocked = await coordinator.capture(for: requestA)
            XCTAssertEqual(blocked, .unavailable(.busy))
        } else { XCTFail("deadline waited for uncooperative provider") }
        _ = await cleanup.value
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(coordinator.snapshot)
    }
    func testFinalValidationIgnoresPixelOnlyChangeAndPreservesCaptureIdentity() async throws {
        let frames = FakeFrames(); let coordinator = configured(frames)
        guard case .captured(let original) = await coordinator.capture(for: requestA) else { return XCTFail() }
        let unchanged = await coordinator.validateCurrent(original, for: requestA)
        XCTAssertTrue(unchanged)
        frames.color = 1
        let changed = await coordinator.validateCurrent(original, for: requestA)
        XCTAssertTrue(changed)
        XCTAssertEqual(coordinator.snapshot, original)
    }
    func testDeniedOrClosedSourceNeverFallsBack() async {
        for failure in [ScreenFailure.denied, .closed] {
            let frames = FakeFrames(); frames.error = failure
            let coordinator = configured(frames)
            let result = await coordinator.capture(for: requestA)
            XCTAssertEqual(result, .unavailable(failure))
            XCTAssertNil(coordinator.snapshot)
        }
    }
    func testOversizedOCRIsRejectedWithoutTruncation() async {
        let coordinator = configured(recognizer: LargeOCR())
        let result = await coordinator.capture(for: requestA)
        XCTAssertEqual(result, .unavailable(.oversized))
        XCTAssertNil(coordinator.snapshot)
    }
}
struct LargeOCR: ScreenTextRecognizer {
    func recognize(_ image: CGImage) async throws -> [OCRLine] {
        [OCRLine(text: String(repeating: "x", count: 8193), bounds: .zero, confidence: 1)]
    }
}


extension ScreenContextCoordinatorTests {
    func testFinalValidationRejectsChangedOCRWithinSameWindow() async {
        let recognizer = MutableOCR()
        let coordinator = configured(recognizer: recognizer)
        guard case .captured(let original) = await coordinator.capture(for: requestA) else { return XCTFail() }
        recognizer.change()
        let current = await coordinator.validateCurrent(original, for: requestA)
        XCTAssertFalse(current)
        XCTAssertNil(coordinator.snapshot)
    }
}
final class MutableOCR: ScreenTextRecognizer, @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    func change() { lock.withLock { changed = true } }
    func recognize(_ image: CGImage) async throws -> [OCRLine] {
        let text = lock.withLock { changed ? "return sorted(items)" : "return len(items)" }
        return [OCRLine(text: text, bounds: CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.1), confidence: 0.9)]
    }
}

extension ScreenContextCoordinatorTests {
    func testCallerCancellationRetiresAndKeepsFlightUntilQuiescent() async {
        let frames = FakeFrames(); frames.holds = true
        let coordinator = configured(frames)
        let pending = Task { await coordinator.capture(for: requestA) }
        await waitForCapture(frames)
        pending.cancel()
        let outcome = await pending.value
        XCTAssertEqual(outcome, .unavailable(.retired))
        XCTAssertTrue(coordinator.isBusy)
        frames.release()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(coordinator.isBusy)
        XCTAssertNil(coordinator.snapshot)
    }
    func testSourceClosureClearsExistingObservation() async {
        let coordinator = configured()
        _ = await coordinator.capture(for: requestA)
        coordinator.sourceUnavailable(.closed)
        XCTAssertNil(coordinator.snapshot)
        let outcome = await coordinator.capture(for: requestA)
        XCTAssertEqual(outcome, .unavailable(.noSelection))
    }
}
