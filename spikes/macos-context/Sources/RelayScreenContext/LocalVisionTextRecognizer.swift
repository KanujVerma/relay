import Foundation
import CoreGraphics
import Vision

/// Local OCR only. Recognition confidence does not establish exact code or diagram semantics.
public struct LocalVisionTextRecognizer: ScreenTextRecognizer {
    private static let queue = DispatchQueue(label: "relay.screen.vision", qos: .userInitiated)
    public init() {}
    public func recognize(_ image: CGImage) async throws -> [OCRLine] {
        guard image.width > 0, image.height > 0, image.width <= 1920, image.height <= 1920 else {
            throw ScreenFailure.oversized
        }
        let work = VisionWork()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                Self.queue.async {
                    autoreleasepool {
                        do {
                            let request = VNRecognizeTextRequest()
                            request.recognitionLevel = .accurate
                            request.usesLanguageCorrection = false
                            request.recognitionLanguages = ["en-US"]
                            request.minimumTextHeight = 0.005
                            guard work.install(request) else { throw CancellationError() }
                            defer { work.clear() }
                            let handler = VNImageRequestHandler(cgImage: image, options: [:])
                            try handler.perform([request])
                            guard !work.isCancelled else { throw CancellationError() }
                            let observations = request.results ?? []
                            guard observations.count <= 256 else { throw ScreenFailure.oversized }
                            var lines: [OCRLine] = []
                            var bytes = 0
                            for observation in observations {
                                guard let top = observation.topCandidates(1).first, !top.string.isEmpty else { continue }
                                bytes += top.string.utf8.count + (lines.isEmpty ? 0 : 1)
                                guard bytes <= 8192 else { throw ScreenFailure.oversized }
                                lines.append(OCRLine(text: top.string, bounds: observation.boundingBox, confidence: top.confidence))
                            }
                            // Preserve Vision's recognized line boundaries and source boxes. Do not reconstruct code indentation.
                            continuation.resume(returning: lines)
                        } catch { continuation.resume(throwing: error) }
                    }
                }
            }
        } onCancel: { work.cancel() }
    }
}

/// The synchronous Vision call stays on its queue until quiescent; cancel() asks Vision to stop.
private final class VisionWork: @unchecked Sendable {
    private let lock = NSLock()
    private var request: VNRequest?
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func install(_ request: VNRequest) -> Bool {
        lock.withLock {
            guard !cancelled else { return false }
            self.request = request
            return true
        }
    }
    func clear() { lock.withLock { request = nil } }
    func cancel() {
        lock.withLock { cancelled = true; request?.cancel() }
    }
}
