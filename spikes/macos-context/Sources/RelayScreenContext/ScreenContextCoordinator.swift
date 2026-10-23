import Foundation
import CoreGraphics
import CryptoKit

/// Owns one selected source and one capture/OCR or validation operation at a time.
/// No OS operation occurs in init, enable, or a default launch.
@MainActor public final class ScreenContextCoordinator {
    public private(set) var isEnabled = false
    public private(set) var selectedSource: ScreenSource?
    public private(set) var selectionRevision: UInt64 = 0
    public private(set) var permissionRevision: UInt64 = 0
    public private(set) var snapshot: ScreenSnapshot?
    public private(set) var preview: CGImage?
    /// Called synchronously AFTER retiring snapshots, BEFORE notifying a helper/UI.
    public var onInvalidation: (@MainActor (ScreenFailure) -> Void)?
    private let provider: any ScreenFrameProvider
    private let recognizer: any ScreenTextRecognizer
    private let now: @Sendable () -> UInt64
    private var currentRequest: ScreenRequest?

    public init(provider: any ScreenFrameProvider, recognizer: any ScreenTextRecognizer,
                now: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.provider = provider
        self.recognizer = recognizer
        self.now = now
    }
    private final class Flight {
        let id: UUID
        var waiter: CheckedContinuation<ScreenCaptureOutcome, Never>?
        var operation: Task<Void, Never>?
        var timer: Task<Void, Never>?
        init(id: UUID, waiter: CheckedContinuation<ScreenCaptureOutcome, Never>) {
            self.id = id; self.waiter = waiter
        }
    }
    private var flight: Flight?
    public var isBusy: Bool { flight != nil }

    public func enable() {
        guard !isEnabled else { return }
        isEnabled = true; permissionRevision += 1
    }
    public func select(_ source: ScreenSource) {
        retire(.retired)
        selectionRevision += 1
        selectedSource = source
    }
    public func disable() {
        isEnabled = false; permissionRevision += 1; selectionRevision += 1
        selectedSource = nil; currentRequest = nil
        retire(.retired)
    }
    public func revoke() { disable() }
    /// A closed window or denied provider retires selected authority, with no fallback.
    public func sourceUnavailable(_ reason: ScreenFailure = .closed) {
        selectedSource = nil; selectionRevision += 1; permissionRevision += 1
        retire(reason)
    }
    public func supersede(with request: ScreenRequest) {
        guard currentRequest != request else { return }
        retire(.retired)
        currentRequest = request
    }
    /// Local identity check only. Use validateCurrent for actual native publication.
    public func owns(_ candidate: ScreenSnapshot, for request: ScreenRequest) -> Bool {
        isEnabled && snapshot == candidate && currentRequest == request && candidate.request == request
            && selectedSource == candidate.source && selectionRevision == candidate.selectionRevision
            && permissionRevision == candidate.permissionRevision && fresh(candidate.capturedUptimeNanoseconds)
    }
    public func validateCurrent(_ candidate: ScreenSnapshot, for request: ScreenRequest,
                                budgetNanoseconds: UInt64 = 500_000_000) async -> Bool {
        guard owns(candidate, for: request) else { return false }
        let result = await run(for: request, budgetNanoseconds: budgetNanoseconds, validating: candidate)
        guard case .captured(let checked) = result else { return false }
        return owns(checked, for: request)
    }
    public func capture(for request: ScreenRequest,
                        budgetNanoseconds: UInt64 = 1_500_000_000) async -> ScreenCaptureOutcome {
        await run(for: request, budgetNanoseconds: budgetNanoseconds, validating: nil)
    }
    private func fresh(_ captured: UInt64) -> Bool {
        let current = now()
        return captured > 0 && current >= captured && current - captured <= 10_000_000_000
    }
    private func run(for request: ScreenRequest, budgetNanoseconds: UInt64,
                     validating original: ScreenSnapshot?) async -> ScreenCaptureOutcome {
        guard !Task.isCancelled else { return .unavailable(.retired) }
        guard isEnabled else { return .unavailable(.disabled) }
        guard let source = selectedSource else { return .unavailable(.noSelection) }
        guard source.windowID > 0, source.processID > 0, !source.bundleID.isEmpty,
              source.bundleID.utf8.count <= 160, source.label.utf8.count <= 160,
              request.sessionEpoch > 0, request.presentationGeneration > 0 else { return .unavailable(.invalidSource) }
        guard request == currentRequest else { return .unavailable(.retired) }
        guard flight == nil else { return .unavailable(.busy) }
        guard budgetNanoseconds > 0 else { return .unavailable(.timedOut) }
        let selection = selectionRevision, permission = permissionRevision, id = UUID()
        if original == nil { snapshot = nil; preview = nil }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let active = Flight(id: id, waiter: continuation)
                flight = active
                active.timer = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: min(budgetNanoseconds, 2_000_000_000)) }
                    catch { return }
                    self?.retireFlight(id, reason: .timedOut)
                }
                active.operation = Task { [weak self, provider, recognizer] in
                    var outcome: ScreenCaptureOutcome
                    var image: CGImage?
                    do {
                        let frame = try await provider.capture(source: source)
                        try Task.checkCancellation()
                        guard let self, self.fresh(frame.capturedUptimeNanoseconds) else { throw ScreenFailure.retired }
                        let imageDigest = try Self.digest(frame.image)
                        let lines = try await recognizer.recognize(frame.image)
                        try Task.checkCancellation()
                        try Self.validate(lines)
                        let digest = Self.contentDigest(lines)
                        let result: ScreenSnapshot
                        if let original {
                            guard digest == original.contentDigest else { throw ScreenFailure.retired }
                            result = original
                        } else {
                            result = ScreenSnapshot(id: UUID(), request: request, source: source,
                                                    selectionRevision: selection, permissionRevision: permission,
                                                    capturedUptimeNanoseconds: frame.capturedUptimeNanoseconds,
                                                    contentDigest: digest, imageDigest: imageDigest, lines: lines)
                        }
                        image = frame.image
                        outcome = .captured(result)
                    } catch { outcome = .unavailable(error as? ScreenFailure ?? (error is CancellationError ? .retired : .unavailable)) }
                    self?.finish(id, outcome: outcome, image: image)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.retireFlight(id, reason: .retired) }
        }
    }
    private func finish(_ id: UUID, outcome: ScreenCaptureOutcome, image: CGImage?) {
        guard let active = flight, active.id == id else { return }
        active.timer?.cancel()
        flight = nil
        guard let waiter = active.waiter else { return } // Retired OS completion cannot reauthorize itself.
        active.waiter = nil
        var admitted = outcome
        if case .captured(let candidate) = outcome {
            guard isEnabled, currentRequest == candidate.request, selectedSource == candidate.source,
                  selectionRevision == candidate.selectionRevision, permissionRevision == candidate.permissionRevision,
                  fresh(candidate.capturedUptimeNanoseconds) else {
                waiter.resume(returning: .unavailable(.retired)); return
            }
            snapshot = candidate; preview = image
        } else if case .unavailable(let reason) = outcome {
            if reason == .closed || reason == .denied { sourceUnavailable(reason) }
            else { snapshot = nil; preview = nil; onInvalidation?(reason) }
            admitted = .unavailable(reason)
        }
        waiter.resume(returning: admitted)
    }
    private func retireFlight(_ id: UUID, reason: ScreenFailure) {
        guard let active = flight, active.id == id else { return }
        let waiter = active.waiter
        active.waiter = nil
        active.operation?.cancel(); active.timer?.cancel()
        snapshot = nil; preview = nil
        onInvalidation?(reason)
        waiter?.resume(returning: .unavailable(reason))
        // Keep flight until the OS/recognizer actually quiesces, even if cancellation is ignored.
    }
    private func retire(_ reason: ScreenFailure) {
        snapshot = nil; preview = nil
        if let active = flight { retireFlight(active.id, reason: reason) }
        else { onInvalidation?(reason) }
    }
    static func validate(_ lines: [OCRLine]) throws {
        guard !lines.isEmpty else { throw ScreenFailure.empty }
        guard lines.count <= 256 else { throw ScreenFailure.oversized }
        var bytes = 0
        for line in lines {
            guard !line.text.isEmpty, line.confidence.isFinite, (0...1).contains(line.confidence),
                  line.bounds.origin.x.isFinite, line.bounds.origin.y.isFinite,
                  line.bounds.width.isFinite, line.bounds.height.isFinite,
                  line.bounds.minX >= 0, line.bounds.minY >= 0, line.bounds.maxX <= 1, line.bounds.maxY <= 1,
                  !line.text.unicodeScalars.contains(where: { $0.value < 32 && $0.value != 9 && $0.value != 10 }) else {
                throw ScreenFailure.unavailable
            }
            bytes += line.text.utf8.count + (bytes == 0 ? 0 : 1)
            guard bytes <= 8192 else { throw ScreenFailure.oversized }
        }
    }

    static func contentDigest(_ lines: [OCRLine]) -> String {
        // Confidence changes do not change the observation. Quantize normalized bounds to 1/1000.
        var hash = SHA256()
        hash.update(data: Data("relay-ocr-v1\n".utf8))
        for line in lines {
            let box = [line.bounds.minX, line.bounds.minY, line.bounds.width, line.bounds.height]
                .map { String(Int(($0 * 1000).rounded())) }.joined(separator: ",")
            hash.update(data: Data("\(line.text.utf8.count):\(line.text):\(box)\n".utf8))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func digest(_ image: CGImage) throws -> String {
        guard image.width > 0, image.height > 0, image.width <= 1920, image.height <= 1920 else {
            throw ScreenFailure.oversized
        }
        // Canonical RGBA pixels, excluding arbitrary provider padding and metadata.
        let row = image.width * 4
        var pixels = [UInt8](repeating: 0, count: row * image.height)
        let valid = pixels.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: row,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard valid else { throw ScreenFailure.unavailable }
        var hash = SHA256()
        hash.update(data: Data("\(image.width)x\(image.height):rgba8:".utf8))
        hash.update(data: Data(pixels))
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
