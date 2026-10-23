import XCTest
import AppKit
import CoreText
@testable import RelayScreenContext

final class VisionTextRecognizerTests: XCTestCase, @unchecked Sendable {
    func testRecognizesSyntheticCodingProblemWithSeparateLinesAndBounds() async throws {
        let lines = try await LocalVisionTextRecognizer().recognize(textImage([
            ("Implement solve(items) in Python", 40, 400),
            ("def solve(items):", 40, 300),
            ("return len(items)", 100, 200),
        ]))
        let text = lines.map(\.text).joined(separator: "\n")
        XCTAssertTrue(text.contains("Implement"))
        XCTAssertTrue(text.contains("solve"))
        XCTAssertTrue(text.contains("return"))
        XCTAssertGreaterThanOrEqual(lines.count, 3)
        XCTAssertTrue(lines.allSatisfy { $0.bounds.width > 0 && $0.bounds.height > 0 && $0.confidence > 0 })
    }
    func testDiagramLabelsAreOCRWithoutInventedRelationships() async throws {
        let lines = try await LocalVisionTextRecognizer().recognize(textImage([
            ("Gateway", 60, 350), ("Queue", 430, 350), ("Worker", 800, 350),
            ("Retry after failure", 380, 170),
        ], diagram: true))
        let text = lines.map(\.text).joined(separator: "\n")
        XCTAssertTrue(text.lowercased().contains("gateway"), text)
        XCTAssertTrue(text.contains("Queue"))
        XCTAssertTrue(text.lowercased().contains("worker"), text)
        XCTAssertFalse(text.contains("API calls Queue"))
        XCTAssertTrue(lines.allSatisfy { $0.confidence <= 1 })
    }
}

func textImage(_ rows: [(String, CGFloat, CGFloat)], diagram: Bool = false) -> CGImage {
    let c = CGContext(data: nil, width: 1280, height: 600, bitsPerComponent: 8, bytesPerRow: 5120,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 1280, height: 600))
    if diagram {
        c.setStrokeColor(CGColor(gray: 0, alpha: 1)); c.setLineWidth(3)
        for x in [30, 400, 770] { c.stroke(CGRect(x: x, y: 320, width: 260, height: 100)) }
        c.move(to: CGPoint(x: 290, y: 370)); c.addLine(to: CGPoint(x: 400, y: 370))
        c.move(to: CGPoint(x: 660, y: 370)); c.addLine(to: CGPoint(x: 770, y: 370)); c.strokePath()
    }
    for (text, x, y) in rows {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 40, weight: .regular), .foregroundColor: NSColor.black,
        ])
        c.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), c)
    }
    return c.makeImage()!
}
