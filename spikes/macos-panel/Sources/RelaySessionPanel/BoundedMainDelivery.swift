import Dispatch
import Foundation

/// The final decoded-to-MainActor hop has the same budgets as the pipes.
/// Reserving capacity is synchronous, before any asynchronous UI work exists.
public final class BoundedMainDelivery<Value:Sendable>: @unchecked Sendable {
    private let lock=NSLock();private var count=0;private var bytes=0
    public init() {}
    public func enqueue(_ value:Value,byteCount:Int,action:@escaping @MainActor @Sendable(Value)->Void) throws {
        try lock.withLock {
            guard byteCount>=0,byteCount<=16388,count<32,bytes+byteCount<=262144 else { throw PanelBridgeError.overflow }
            count+=1;bytes+=byteCount
        }
        DispatchQueue.main.async { [self] in
            defer { lock.withLock { count-=1;bytes-=byteCount } }
            action(value)
        }
    }
}
