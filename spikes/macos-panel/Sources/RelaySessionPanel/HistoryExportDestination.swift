import Foundation

/// A destination is created only after the user's explicit export action.
/// Once this synchronous write starts it must finish or fail before the owner
/// can close. Lock cannot retract a copy that the user already exported.
public protocol HistoryExportDestination:Sendable {
    func write(_ data:Data)throws
}
public struct HistoryFileExportDestination:HistoryExportDestination {
    private let url:URL
    public init(url:URL){self.url=url}
    public func write(_ data:Data)throws{
        guard url.isFileURL,data.count<=HistoryBounds.snapshot else{throw HistoryError.invalid}
        try data.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
}
