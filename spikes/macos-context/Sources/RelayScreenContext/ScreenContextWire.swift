import Foundation
import CoreGraphics
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Supplemental frames are separate message kinds, outside the exact native EOU event.
@MainActor public enum ScreenContextWire {
    static func identity(_ observed: ScreenSnapshot) -> [String: Any] {
        ["schemaVersion": 1,
         "captureSessionID": observed.request.sessionID.uuidString.lowercased(),
         "sessionEpoch": observed.request.sessionEpoch,
         "presentationGeneration": observed.request.presentationGeneration,
         "requestID": observed.request.requestID.uuidString.lowercased(),
         "source": ["windowID": observed.source.windowID, "bundleID": observed.source.bundleID,
                    "processID": observed.source.processID, "label": observed.source.label],
         "selectionRevision": observed.selectionRevision, "permissionRevision": observed.permissionRevision,
         "capturedUptimeNanoseconds": observed.capturedUptimeNanoseconds,
         "contentDigest": observed.contentDigest, "imageDigest": observed.imageDigest]
    }
    static func encode(_ value: [String: Any]) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 16384 else { throw ScreenFailure.oversized }
        return data
    }
    public static func retiredFrame(_ observed: ScreenSnapshot, reason: ScreenRetirementReason) throws -> Data {
        try encode(["schemaVersion": 1, "kind": "screen_context_retired",
                    "captureSessionID": observed.request.sessionID.uuidString.lowercased(),
                    "sessionEpoch": observed.request.sessionEpoch,
                    "presentationGeneration": observed.request.presentationGeneration,
                    "requestID": observed.request.requestID.uuidString.lowercased(),
                    "selectionRevision": observed.selectionRevision, "permissionRevision": observed.permissionRevision,
                    "reasonCode": reason.rawValue])
    }
    public static func textFrame(_ observed: ScreenSnapshot) throws -> Data {
        var frame = identity(observed)
        frame["kind"] = "screen_context"
        frame["text"] = observed.text
        frame["provenance"] = "local_ocr"
        return try encode(frame)
    }
}

/// One transient PNG transfer, enabled only after the host verifies model capability and user intent.
/// Pull frames lazily under transport backpressure. Do not enqueue the entire transfer at once.
@MainActor public final class ScreenImageTransfer {
    private var bytes: Data
    private let common: [String: Any]
    private let width: Int, height: Int
    private let digest: String
    private let current: @MainActor () -> Bool
    private let started = DispatchTime.now().uptimeNanoseconds
    private var index = -1
    private var retired = false
    public private(set) var isComplete = false
    public var retainedByteCount: Int { bytes.count }

    init(snapshot: ScreenSnapshot, image: CGImage, current: @escaping @MainActor () -> Bool) throws {
        guard image.width > 0, image.height > 0, image.width <= 1920, image.height <= 1920,
              try ScreenContextCoordinator.digest(image) == snapshot.imageDigest else { throw ScreenFailure.retired }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ScreenFailure.unavailable
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScreenFailure.unavailable }
        guard data.length > 0, data.length <= 2 * 1024 * 1024 else { throw ScreenFailure.oversized }
        self.bytes = data as Data
        self.width = image.width; self.height = image.height; self.current = current
        digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        var identity = ScreenContextWire.identity(snapshot)
        identity["transferID"] = UUID().uuidString.lowercased()
        common = identity
    }
    public func cancel() { retired = true; bytes = Data() }
    public func nextFrame() throws -> Data? {
        if isComplete { return nil }
        guard !retired, current() else { cancel(); throw ScreenFailure.retired }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= started, now - started <= 2_000_000_000 else { cancel(); throw ScreenFailure.timedOut }
        var frame = common
        let count = (bytes.count + 6143) / 6144
        if index == -1 {
            frame["kind"] = "screen_image_begin"
            frame["mimeType"] = "image/png"
            frame["width"] = width; frame["height"] = height
            frame["totalBytes"] = bytes.count; frame["chunkCount"] = count; frame["sha256"] = digest
        } else if index < count {
            frame["kind"] = "screen_image_chunk"
            frame["index"] = index
            let offset = index * 6144
            frame["data"] = bytes.subdata(in: offset..<min(offset + 6144, bytes.count)).base64EncodedString()
        } else {
            frame["kind"] = "screen_image_end"
            isComplete = true
            bytes = Data()
        }
        index += 1
        return try ScreenContextWire.encode(frame)
    }
}

public enum ScreenRetirementReason: String, Sendable {
    case selectionChanged = "selection_changed"
    case permissionRevoked = "permission_revoked"
    case sourceClosed = "source_closed"
    case contextChanged = "context_changed"
    case contextExpired = "context_expired"
    case requestSuperseded = "request_superseded"
    case userStop = "user_stop"
}
