import XCTest
import CoreGraphics
@testable import RelayScreenContext

@MainActor final class SystemSelectedWindowCaptureTests: XCTestCase {
    func testDimensionsBoundLongSideWithoutUpscaling() {
        XCTAssertEqual(ScreenCaptureDimensions.fit(CGSize(width: 3840, height: 2160), scale: 1), CGSize(width: 1920, height: 1080))
        XCTAssertEqual(ScreenCaptureDimensions.fit(CGSize(width: 800, height: 600), scale: 1), CGSize(width: 800, height: 600))
        XCTAssertNil(ScreenCaptureDimensions.fit(CGSize(width: CGFloat.nan, height: 600), scale: 1))
        XCTAssertNil(ScreenCaptureDimensions.fit(CGSize(width: 800, height: 0), scale: 1))
    }
    func testActualAdapterCannotCaptureWithoutPickerSelection() async {
        if #available(macOS 15.2, *) {
            let adapter = SystemSelectedWindowCapture()
            do { _ = try await adapter.capture(source: sourceA); XCTFail("capture without selection must fail") }
            catch { XCTAssertEqual(error as? ScreenFailure, .noSelection) }
        }
    }
}
