import Foundation

/// Denial-only notification from this workspace's admitted mutation. It never
/// supplies read, capture, inference or personal-fact authority. nil means all
/// records in the retired epoch; an empty set is never published.
public struct HistoryRecordsUnavailable:Sendable{
    public let retiredEpoch:UUID
    public let recordIDs:Set<UUID>?
    init(retiredEpoch:UUID,recordIDs:Set<UUID>?){self.retiredEpoch=retiredEpoch;self.recordIDs=recordIDs}
}
/// Issued only after the actual matching manual-note CAS and publication fences.
/// Not Codable: status/JSON and a mutable UI snapshot cannot manufacture one.
public struct HistoryNoteSaveReceipt:Sendable{
    public let epoch:UUID,recordID:UUID
    public let revision:Int64
    public let title:String,note:String
    init(epoch:UUID,record:HistoryRecord){self.epoch=epoch;recordID=record.id;revision=record.revision;title=record.title;note=record.note}
}
