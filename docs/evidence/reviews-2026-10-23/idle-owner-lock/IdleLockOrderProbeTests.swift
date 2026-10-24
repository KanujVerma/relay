import Darwin
import Foundation
import XCTest
import RelayNativeSession
import RelaySessionPanel
import RelayContextComposition
@testable import RelayPanelSession

private final class LockProbeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func finish() { lock.withLock { value = true } }
    var finished: Bool { lock.withLock { value } }
}
@MainActor final class IdleLockOrderProbeTests: XCTestCase {
    func testActualPanelCommitAndHelperFailureLockOrder() async throws {
        let active = ProcessInfo.processInfo.environment["RELAY_OWNER_LOCK_PROBE"] == "active"
        let box = ConversationOwnerBox(), identity = UUID()
        let helper = HelperTransport(root: URL(fileURLWithPath: "/"), python: URL(fileURLWithPath: "/usr/bin/false"), mode: .noInference, onFrame: { _ in }, onFailure: {})
        box.activateHelper(identity)
        let owner = ConversationOwner(helper: helper, helperIdentity: identity, preparationIntent: UUID())
        XCTAssertTrue(box.install(owner))
        let native = try XCTUnwrap(owner.assistantController)
        let opening = try native.begin(enqueue: { owner.record($0.lease) })
        try native.completeOpen(opening)
        let question = try native.issueUserQuestion(expectedLease: opening.lease, intent: .ask, question: "Explain queues.", baseRequestID: nil, enqueue: { _ in })
        let binding = PanelRequestBinding(lease: question.lease, requestID: question.requestID, eventSequence: question.anchorEventSequence)
        let enterFailure = DispatchSemaphore(value: 0), failureStarted = DispatchSemaphore(value: 0), finished = LockProbeFlag()
        DispatchQueue.global().async {
            enterFailure.wait(); failureStarted.signal()
            _ = box.failHelper(active ? identity : UUID())
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if !finished.finished {
                FileHandle.standardError.write(Data("OWNER_LOCK_ORDER_DEADLOCK_PROBE active=\(active)\n".utf8))
                Darwin._exit(86)
            }
        }
        // Same current-owner read as the actual Model.configure onChange.
        // SessionPanelController invokes it under withCurrentLease's lock.
        owner.presentation.panel.onChange = {
            enterFailure.signal()
            XCTAssertEqual(failureStarted.wait(timeout: .now() + 1), .success)
            Thread.sleep(forTimeInterval: 0.1)
            XCTAssertTrue(box.current === owner)
        }
        owner.presentation.panel.bind(binding)
        finished.finish(); owner.presentation.panel.onChange = nil
        await helper.shutdownAndWait()
    }
}
