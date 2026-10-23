@preconcurrency import ApplicationServices
import Foundation

/// Narrow read-only AX adapter. No tree walking, value reads, clipboard fallback,
/// clicks or typing. Incomplete AX text support makes the capability unavailable.
@MainActor public final class AccessibilitySelectedTextProvider: SelectedTextProviding {
    public init() {}
    public func isTrusted(prompt: Bool) -> Bool {
        if !prompt { return AXIsProcessTrusted() }
        return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    public func selectedText(from application: ApplicationIdentity) async throws -> SelectedTextObservation {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) {
            try Self.read(application)
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    nonisolated private static func read(_ application: ApplicationIdentity) throws -> SelectedTextObservation {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw SelectionError.permissionRequired }
        let app = AXUIElementCreateApplication(application.processID)
        guard AXUIElementSetMessagingTimeout(app, 0.05) == .success else { throw SelectionError.unsupportedSelection }
        let focusedValue = try attribute(app, kAXFocusedUIElementAttribute)
        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { throw SelectionError.unsupportedSelection }
        let focused = unsafeDowncast(focusedValue, to: AXUIElement.self)
        guard AXUIElementSetMessagingTimeout(focused, 0.05) == .success else { throw SelectionError.unsupportedSelection }
        var processID: pid_t = 0
        guard AXUIElementGetPid(focused, &processID) == .success, processID == application.processID else { throw SelectionError.stale }
        guard let role = try attribute(focused, kAXRoleAttribute) as? String else { throw SelectionError.unsupportedSelection }
        let subrole: String?
        do { subrole = try attribute(focused, kAXSubroleAttribute) as? String }
        catch SelectionError.unsupportedSelection { subrole = nil }
        let identifiers = role.lowercased() + " " + (subrole ?? "").lowercased()
        guard !identifiers.contains("secure"), !identifiers.contains("password") else { throw SelectionError.secureField }
        guard ["AXTextArea", "AXTextField", "AXStaticText"].contains(role) else { throw SelectionError.unsupportedSelection }
        let selectedRange = try range(focused)
        guard selectedRange.location >= 0, selectedRange.length > 0 else { throw SelectionError.emptySelection }
        guard selectedRange.length <= 8192, selectedRange.location <= Int.max - selectedRange.length else { throw SelectionError.tooLarge }
        var requestedRange = selectedRange
        guard let rangeValue = AXValueCreate(.cfRange, &requestedRange) else { throw SelectionError.unsupportedSelection }
        var value: CFTypeRef?
        try Task.checkCancellation()
        try check(AXUIElementCopyParameterizedAttributeValue(focused, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &value))
        guard let value, let text = value as? String else { throw SelectionError.unsupportedSelection }
        guard text.utf8.count <= 8192 else { throw SelectionError.tooLarge }
        // A changed range or focused object means this observation was torn.
        let rangeAfter = try range(focused)
        let focusAfter = try attribute(app, kAXFocusedUIElementAttribute)
        guard selectedRange.location == rangeAfter.location, selectedRange.length == rangeAfter.length,
              CFEqual(focused, focusAfter), AXIsProcessTrusted() else { throw SelectionError.stale }
        return .init(application: application, role: role, subrole: subrole, text: text)
    }

    nonisolated private static func range(_ element: AXUIElement) throws -> CFRange {
        let value = try attribute(element, kAXSelectedTextRangeAttribute)
        guard CFGetTypeID(value) == AXValueGetTypeID() else { throw SelectionError.unsupportedSelection }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) else { throw SelectionError.unsupportedSelection }
        return range
    }

    nonisolated private static func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef {
        try Task.checkCancellation()
        var value: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(element, name as CFString, &value))
        guard let value else { throw SelectionError.unsupportedSelection }
        return value
    }

    nonisolated private static func check(_ result: AXError) throws {
        if result == .cannotComplete { throw SelectionError.timedOut }
        if result == .apiDisabled { throw SelectionError.permissionRequired }
        guard result == .success else { throw SelectionError.unsupportedSelection }
    }
}
