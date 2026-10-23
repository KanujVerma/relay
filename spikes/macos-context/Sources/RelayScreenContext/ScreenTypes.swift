import Foundation
import CoreGraphics

public struct ScreenRequest: Sendable, Equatable, Codable {
    public let sessionID: UUID
    public let sessionEpoch: UInt64
    public let presentationGeneration: UInt64
    public let requestID: UUID
    public init(sessionID: UUID, sessionEpoch: UInt64, presentationGeneration: UInt64, requestID: UUID) {
        self.sessionID = sessionID
        self.sessionEpoch = sessionEpoch
        self.presentationGeneration = presentationGeneration
        self.requestID = requestID
    }
}

public struct ScreenSource: Sendable, Equatable, Codable {
    public let windowID: UInt32
    public let bundleID: String
    public let processID: Int32
    public let label: String
    public init(windowID: UInt32, bundleID: String, processID: Int32, label: String) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.processID = processID
        self.label = label
    }
}

public struct OCRLine: Sendable, Equatable, Codable {
    public let text: String
    /// Vision normalized bounds, bottom-left origin. Evidence of OCR placement only.
    public let bounds: CGRect
    public let confidence: Float
    public init(text: String, bounds: CGRect, confidence: Float) {
        self.text = text
        self.bounds = bounds
        self.confidence = confidence
    }
}

public struct ScreenFrame: @unchecked Sendable {
    public let image: CGImage
    /// Taken at capture start, never at OCR completion or subsequent question delivery.
    public let capturedUptimeNanoseconds: UInt64
    public init(image: CGImage, capturedUptimeNanoseconds: UInt64) {
        self.image = image
        self.capturedUptimeNanoseconds = capturedUptimeNanoseconds
    }
}

public struct ScreenSnapshot: Sendable, Equatable {
    public let id: UUID
    public let request: ScreenRequest
    public let source: ScreenSource
    public let selectionRevision: UInt64
    public let permissionRevision: UInt64
    public let capturedUptimeNanoseconds: UInt64
    /// Canonical recognized text and quantized line placement, not visual semantics.
    public let contentDigest: String
    /// Original pixel artifact identity. Never replaces content/source authority.
    public let imageDigest: String
    public let lines: [OCRLine]
    public var text: String { lines.map(\.text).joined(separator: "\n") }
}

public enum ScreenFailure: String, Error, Sendable {
    case disabled, noSelection, invalidSource, denied, closed, busy, timedOut, retired, oversized, empty, unavailable
}
public enum ScreenCaptureOutcome: Sendable, Equatable {
    case captured(ScreenSnapshot)
    case unavailable(ScreenFailure)
}

@MainActor public protocol ScreenFrameProvider: AnyObject {
    func capture(source: ScreenSource) async throws -> ScreenFrame
}
public protocol ScreenTextRecognizer: Sendable {
    func recognize(_ image: CGImage) async throws -> [OCRLine]
}
