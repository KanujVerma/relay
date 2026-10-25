import AppKit

public struct ApplicationIdentity: Equatable, Hashable, Sendable {
    public let bundleID: String
    public let processID: Int32
    public let launchDate: Date
    public init(bundleID: String, processID: Int32, launchDate: Date) {
        self.bundleID = bundleID
        self.processID = processID
        self.launchDate = launchDate
    }
}

public enum WorkspaceFrontmostApplication {
    /// Public NSWorkspace metadata only. Does not need Accessibility access.
    @MainActor public static func current() -> ApplicationIdentity? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier, let launchDate = app.launchDate,
              !app.isTerminated else { return nil }
        return .init(bundleID: bundleID, processID: app.processIdentifier, launchDate: launchDate)
    }
}
