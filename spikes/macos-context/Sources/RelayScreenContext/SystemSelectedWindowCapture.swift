import Foundation
import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

public enum ScreenCaptureDimensions {
    public static func fit(_ points: CGSize, scale: CGFloat) -> CGSize? {
        guard points.width.isFinite, points.height.isFinite, scale.isFinite,
              points.width > 0, points.height > 0, scale > 0 else { return nil }
        let width = points.width * scale, height = points.height * scale
        guard width.isFinite, height.isFinite else { return nil }
        let factor = min(1, 1920 / max(width, height))
        return CGSize(width: max(1, floor(width * factor)), height: max(1, floor(height * factor)))
    }
}

/// Explicit single-window picker only. No screen enumeration, permission prompt, or capture in init.
/// macOS 15.2 is needed to obtain selected window/app identity from the picker filter.
@available(macOS 15.2, *)
@MainActor public final class SystemSelectedWindowCapture: NSObject, ScreenFrameProvider {
    public var onSelection: (@MainActor (ScreenSource) -> Void)?
    /// Retire the consumer's snapshot/lease synchronously before a new filter is exposed.
    public var onInvalidation: (@MainActor (ScreenFailure) -> Void)?
    public private(set) var source: ScreenSource?
    private var filter: SCContentFilter?
    private var revision: UInt64 = 0
    private var registered = false
    private var callbackGate = PickerCallbackGate()
    private var observer: PickerObservation?
    private var selectionPending = false
    private var captureActive = false
    public override init() { super.init() }

    /// Call only from the user's Enable/select action, never automatically on app launch.
    public func presentSelection() {
        clearSelection(reason: .retired)
        selectionPending = true
        let picker = SCContentSharingPicker.shared
        if let observer { picker.remove(observer) }
        let observer = PickerObservation(owner: self, token: callbackGate.begin())
        self.observer = observer
        picker.add(observer); registered = true
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = .singleWindow
        configuration.allowsChangingSelectedContent = true
        picker.defaultConfiguration = configuration
        picker.isActive = true
        picker.present(using: .window)
    }
    public func disable() {
        selectionPending = false
        callbackGate.retire()
        clearSelection(reason: .disabled)
        if registered, let observer {
            SCContentSharingPicker.shared.remove(observer)
            SCContentSharingPicker.shared.isActive = false
            registered = false
        }
        observer = nil
    }
    private func clearSelection(reason: ScreenFailure) {
        filter = nil; source = nil; revision += 1
        onInvalidation?(reason)
    }
    public func capture(source expected: ScreenSource) async throws -> ScreenFrame {
        guard !captureActive else { throw ScreenFailure.busy }
        guard let filter, let selected = source else { throw ScreenFailure.noSelection }
        guard selected == expected else { throw ScreenFailure.retired }
        guard Self.windowStillExists(expected) else { clearSelection(reason: .closed); throw ScreenFailure.closed }
        let selectedRevision = revision
        guard let dimensions = ScreenCaptureDimensions.fit(filter.contentRect.size, scale: CGFloat(filter.pointPixelScale)) else {
            throw ScreenFailure.invalidSource
        }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(dimensions.width)
        configuration.height = Int(dimensions.height)
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        // Downscale only if the selected window shrinks after its dimensions were measured.
        configuration.scalesToFit = false
        captureActive = true
        defer { captureActive = false }
        let started = DispatchTime.now().uptimeNanoseconds
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            try Task.checkCancellation()
            guard selectedRevision == revision, source == expected else { throw ScreenFailure.retired }
            guard Self.windowStillExists(expected) else { clearSelection(reason: .closed); throw ScreenFailure.closed }
            return ScreenFrame(image: image, capturedUptimeNanoseconds: started)
        } catch {
            if let reason = error as? ScreenFailure { throw reason }
            if error is CancellationError { throw error }
            let ns = error as NSError
            let reason: ScreenFailure = ns.domain == SCStreamErrorDomain && [-3801, -3817].contains(ns.code) ? .denied : .unavailable
            clearSelection(reason: reason)
            throw reason
        }
    }
    private static func windowStillExists(_ source: ScreenSource) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: source.processID), !app.isTerminated,
              app.bundleIdentifier == source.bundleID,
              let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, source.windowID) as? [[String: Any]],
              let window = list.first,
              let windowID = window[kCGWindowNumber as String] as? NSNumber,
              let pid = window[kCGWindowOwnerPID as String] as? NSNumber else { return false }
        return windowID.uint32Value == source.windowID && pid.int32Value == source.processID
    }
    fileprivate func selected(_ selectedFilter: SCContentFilter, token: UUID) {
        guard callbackGate.accepts(token), registered, selectionPending || source != nil else { return }
        // Retire old authority before considering the new selected filter.
        clearSelection(reason: .retired)
        selectionPending = false
        guard selectedFilter.style == .window, selectedFilter.includedWindows.count == 1,
              let window = selectedFilter.includedWindows.first, let application = window.owningApplication,
              application.processID > 0, !application.bundleIdentifier.isEmpty else {
            onInvalidation?(.invalidSource); return
        }
        let label = "\(application.applicationName) window \(window.windowID)"
        // Avoid persisting or sending document titles. The app/window label remains bounded.
        guard label.utf8.count <= 160, application.bundleIdentifier.utf8.count <= 160 else {
            onInvalidation?(.invalidSource); return
        }
        let selectedSource = ScreenSource(windowID: window.windowID, bundleID: application.bundleIdentifier,
                                          processID: application.processID, label: label)
        filter = selectedFilter; source = selectedSource
        onSelection?(selectedSource)
    }
}

@available(macOS 15.2, *)
extension SystemSelectedWindowCapture {
    fileprivate func pickerStopped(token: UUID, failure: ScreenFailure) {
        guard callbackGate.accepts(token) else { return }
        selectionPending = false
        clearSelection(reason: failure)
    }
}

/// Immutable callback token plus an ARC-managed weak owner; callbacks hand state to MainActor.
@available(macOS 15.2, *)
private final class PickerObservation: NSObject, SCContentSharingPickerObserver, @unchecked Sendable {
    private weak var owner: SystemSelectedWindowCapture?
    private let token: UUID
    init(owner: SystemSelectedWindowCapture, token: UUID) { self.owner = owner; self.token = token }
    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        let transferred = PickerFilterTransfer(filter), token = token, owner = owner
        Task { @MainActor in owner?.selected(transferred.filter, token: token) }
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        let token = token, owner = owner
        Task { @MainActor in owner?.pickerStopped(token: token, failure: .retired) }
    }
    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        let token = token, owner = owner
        Task { @MainActor in owner?.pickerStopped(token: token, failure: .unavailable) }
    }
}
/// Read-only ownership transfer from an OS callback to the one UI actor; never mutate off that actor.
@available(macOS 15.2, *)
private final class PickerFilterTransfer: @unchecked Sendable {
    let filter: SCContentFilter
    init(_ filter: SCContentFilter) { self.filter = filter }
}
