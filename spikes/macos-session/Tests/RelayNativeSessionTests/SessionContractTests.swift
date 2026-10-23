import Foundation
import XCTest
@testable import RelayNativeSession

final class SessionContractTests: XCTestCase {
    func testInvalidationRejectsQueuedOldLeaseAndStopRetiresAllLeases() throws {
        let authority = SessionPresentationAuthority()
        let first = try authority.start()
        var committed = false
        XCTAssertTrue(authority.withCurrentLease(first) { committed = true })
        XCTAssertTrue(committed)
        let next = try XCTUnwrap(authority.invalidate())
        XCTAssertNotEqual(first, next)
        XCTAssertFalse(authority.withCurrentLease(first) { XCTFail("stale commit") })
        authority.stop()
        XCTAssertNil(authority.snapshot())
        XCTAssertFalse(authority.withCurrentLease(next) { XCTFail("stopped commit") })
        let fresh = try authority.start()
        XCTAssertNotEqual(first.captureSessionID, fresh.captureSessionID)
    }

    func testNonunitTimebaseAndCheckedOverflow() throws {
        let clock = NativeClockCalibration(hostTicksAtAnchor: 100, uptimeNsAtAnchor: 1_000, nsNumer: 125, nsDenom: 3)
        XCTAssertEqual(try clock.uptimeNanoseconds(forHostTicks: 103), 1_125)
        XCTAssertThrowsError(try clock.uptimeNanoseconds(forHostTicks: 99))
        let overflow = NativeClockCalibration(hostTicksAtAnchor: 0, uptimeNsAtAnchor: UInt64.max, nsNumer: 2, nsDenom: 1)
        XCTAssertThrowsError(try overflow.uptimeNanoseconds(forHostTicks: 1))
    }

    func testWireFramePreservesUInt64AndNulls() throws {
        let event = NativeSessionEvent(
            captureSessionID: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!,
            sessionEpoch: 1, eventSequence: UInt64.max, presentationGeneration: 2,
            kind: .stopped, sourceCode: nil, streamGeneration: nil,
            emittedUptimeNanoseconds: 9000,
            payload: ["reasonCode": .string("user_stop"), "quiesced": .bool(true)])
        let frame = try event.encodedFrame()
        let length = frame.prefix(4).reduce(0) { $0 << 8 | Int($1) }
        XCTAssertEqual(length, frame.count - 4)
        let json = try XCTUnwrap(String(data: frame.dropFirst(4), encoding: .utf8))
        XCTAssertTrue(json.contains("18446744073709551615"))
        XCTAssertTrue(json.contains("\"sourceCode\":null"))
        XCTAssertThrowsError(try event.encodedFrame(maximumBytes: 10))
    }
}
