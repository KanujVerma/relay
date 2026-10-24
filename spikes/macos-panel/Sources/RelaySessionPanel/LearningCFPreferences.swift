import CoreFoundation
import Foundation

public protocol LearningPreferenceBytes:Sendable {
    func load()throws->Data?
    func save(_ data:Data)throws
}
/// Content-free preference bytes only. Source history, quotations, indexes and
/// private keys never enter this store or the CF preference domain.
final class CoreFoundationLearningPreferenceBytes:LearningPreferenceBytes {
    private let domain:String
    private static let key="relay.learning.control-receipt.v1"
    init(domain:String){self.domain=domain}
    private func checkedDomain()throws->CFString{
        guard !domain.isEmpty,domain.utf8.count<=180,domain.utf8.allSatisfy({(48...57).contains($0)||(65...90).contains($0)||(97...122).contains($0)||[45,46,95].contains($0)}) else{throw HistoryError.invalid}
        return domain as CFString
    }
    func load()throws->Data?{
        let domain=try checkedDomain()
        guard let value=CFPreferencesCopyAppValue(Self.key as CFString,domain) else{return nil}
        guard let data=value as? Data,data.count<=2048 else{throw HistoryError.invalid};return data
    }
    func save(_ data:Data)throws{
        guard data.count<=2048 else{throw HistoryError.capacity}
        let domain=try checkedDomain()
        CFPreferencesSetAppValue(Self.key as CFString,data as CFData,domain)
        guard CFPreferencesAppSynchronize(domain),try load()==data else{throw HistoryError.unavailable}
    }
}
@MainActor public final class CFPreferencesLearningControls:LearningControlPreferences {
    private let bytes:any LearningPreferenceBytes
    public init(domain:String?=nil){bytes=CoreFoundationLearningPreferenceBytes(domain:domain ?? Bundle.main.bundleIdentifier ?? "com.relay")}
    public init(bytes:any LearningPreferenceBytes){self.bytes=bytes}
    public func read()async throws->LearningControlReceipt{
        try Task.checkCancellation();let storage=bytes
        let raw=try await Task.detached(priority:.utility){try storage.load()}.value
        guard let raw else{return LearningControlReceipt(revision:nil,enabled:false,pending:nil)}
        guard raw.count<=2048 else{throw HistoryError.capacity}
        let receipt=try HistoryJSON.decode(LearningControlReceipt.self,raw);try receipt.validate();return receipt
    }
    public func deny(_ pending:LearningPendingControl)async throws->LearningControlReceipt{
        try await persist(LearningControlReceipt(revision:pending.revision,enabled:false,pending:pending))
    }
    public func commit(_ control:LearningControlRecord)async throws->LearningControlReceipt{
        try control.validate();return try await persist(LearningControlReceipt(revision:control.revision,enabled:control.enabled,pending:nil))
    }
    private func persist(_ receipt:LearningControlReceipt)async throws->LearningControlReceipt{
        try Task.checkCancellation();try receipt.validate()
        let encoded=try HistoryJSON.encode(receipt),storage=bytes
        guard encoded.count<=2048 else{throw HistoryError.capacity}
        // Await the actual synchronous outcome even when the actor caller is
        // cancelled. A late result cannot adopt because its owner rechecks.
        let actual=try await Task.detached(priority:.utility){
            try storage.save(encoded)
            guard let raw=try storage.load(),raw==encoded else{throw HistoryError.unavailable};return raw
        }.value
        let result=try HistoryJSON.decode(LearningControlReceipt.self,actual);try result.validate()
        guard result==receipt else{throw HistoryError.unavailable};return result
    }
}
