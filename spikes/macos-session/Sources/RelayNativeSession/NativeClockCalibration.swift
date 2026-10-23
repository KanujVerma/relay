import Darwin
import Dispatch
import Foundation

public struct NativeClockCalibration: Sendable, Equatable, Codable {
    public let hostTicksAtAnchor: UInt64
    public let uptimeNsAtAnchor: UInt64
    public let nsNumer: UInt64
    public let nsDenom: UInt64

    public init(hostTicksAtAnchor: UInt64, uptimeNsAtAnchor: UInt64, nsNumer: UInt64, nsDenom: UInt64) {
        self.hostTicksAtAnchor = hostTicksAtAnchor
        self.uptimeNsAtAnchor = uptimeNsAtAnchor
        self.nsNumer = nsNumer
        self.nsDenom = nsDenom
    }
    public static func now() -> Self {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let ticks = mach_absolute_time()
        // Dispatch uptime and mach_absolute_time use the same sleep-excluding
        // host clock. Anchor conversion avoids a Date/wall-clock dependency.
        return Self(hostTicksAtAnchor: ticks, uptimeNsAtAnchor: DispatchTime.now().uptimeNanoseconds,
                    nsNumer: UInt64(info.numer), nsDenom: UInt64(info.denom))
    }
    public func uptimeNanoseconds(forHostTicks ticks: UInt64) throws -> UInt64 {
        guard nsNumer > 0, nsDenom > 0, nsNumer <= 1_000_000_000, nsDenom <= 1_000_000_000,
              ticks >= hostTicksAtAnchor else { throw NativeSessionError.invalidClock }
        let delta = ticks - hostTicksAtAnchor
        // Full-width multiplication preserves valid large timebase products.
        let product = delta.multipliedFullWidth(by: nsNumer)
        guard product.high < nsDenom else { throw NativeSessionError.invalidClock }
        let converted = nsDenom.dividingFullWidth(product).quotient
        let (value, overflow) = uptimeNsAtAnchor.addingReportingOverflow(converted)
        guard !overflow else { throw NativeSessionError.invalidClock }
        return value
    }
    public func hostTicks(after ticks: UInt64, sampleOffset: Int, rate: Double) throws -> UInt64 {
        guard sampleOffset >= 0, rate.isFinite, rate > 0, nsNumer > 0, nsDenom > 0 else {
            throw NativeSessionError.invalidClock
        }
        let delta = Double(sampleOffset) / rate * 1_000_000_000 * Double(nsDenom) / Double(nsNumer)
        guard delta.isFinite, delta >= 0, delta < Double(UInt64.max) else { throw NativeSessionError.invalidClock }
        let (end, overflow) = ticks.addingReportingOverflow(UInt64(delta.rounded(.down)))
        guard !overflow else { throw NativeSessionError.invalidClock }
        return end
    }
    public var wire: WireValue {
        .object(["hostTicksAtAnchor": .uint(hostTicksAtAnchor), "uptimeNsAtAnchor": .uint(uptimeNsAtAnchor),
                 "nsNumer": .uint(nsNumer), "nsDenom": .uint(nsDenom)])
    }
}
