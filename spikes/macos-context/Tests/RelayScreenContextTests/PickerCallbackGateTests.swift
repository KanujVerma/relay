import XCTest
@testable import RelayScreenContext

final class PickerCallbackGateTests: XCTestCase {
    func testQueuedCallbackFromReplacedOrDisabledPickerCannotAuthorizeSource() {
        var gate = PickerCallbackGate()
        let first = gate.begin()
        XCTAssertTrue(gate.accepts(first))
        gate.retire()
        XCTAssertFalse(gate.accepts(first))
        let second = gate.begin()
        XCTAssertFalse(gate.accepts(first))
        XCTAssertTrue(gate.accepts(second))
    }
}
