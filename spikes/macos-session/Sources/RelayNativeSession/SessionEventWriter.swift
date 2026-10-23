import Darwin
import Dispatch
import Foundation

/// One owned dedicated pipe descriptor and one writer task. A blocked consumer
/// cannot grow an unbounded DispatchQueue or silently discard a stop control.
public final class BoundedSessionEventWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "Relay.NativeSession.eventWriter", qos: .userInitiated)
    private let descriptor: Int32
    private let maximumFrames: Int
    private let maximumBytes: Int
    private let writeDeadlineNanoseconds: UInt64
    private let onFailure: @Sendable () -> Void
    private var accepting = true
    private var closed = false
    private var failed = false
    private var draining = false
    private var frames: [Data] = []
    // Include the in-flight frame, not just waiting frames, in both limits.
    private var queuedFrames = 0
    private var queuedBytes = 0

    public init(descriptor: Int32, maximumFrames: Int = 32, maximumBytes: Int = 262_144,
                writeDeadlineMilliseconds: Int = 500, onFailure: @escaping @Sendable () -> Void) throws {
        guard descriptor >= 0, (1...32).contains(maximumFrames), (16_388...262_144).contains(maximumBytes),
              (1...1000).contains(writeDeadlineMilliseconds) else { throw NativeSessionError.invalidConfiguration }
        let owned = Darwin.dup(descriptor)
        guard owned >= 0 else { throw NativeSessionError.transportClosed }
        guard fcntl(owned, F_SETFL, fcntl(owned, F_GETFL) | O_NONBLOCK) == 0,
              fcntl(owned, F_SETNOSIGPIPE, 1) == 0 else {
            Darwin.close(owned); throw NativeSessionError.transportClosed
        }
        self.descriptor = owned; self.maximumFrames = maximumFrames; self.maximumBytes = maximumBytes
        self.writeDeadlineNanoseconds = UInt64(writeDeadlineMilliseconds) * 1_000_000
        self.onFailure = onFailure
    }
    public func enqueue(_ event: NativeSessionEvent) throws {
        let frame = try event.encodedFrame()
        var overflow = false
        let kick = lock.withLock { () -> Bool in
            guard accepting else { return false }
            guard queuedFrames < maximumFrames, frame.count <= maximumBytes - queuedBytes else {
                accepting = false; overflow = true; return false
            }
            frames.append(frame); queuedFrames += 1; queuedBytes += frame.count
            guard !draining else { return false }
            draining = true; return true
        }
        if overflow { fail(); throw NativeSessionError.transportClosed }
        guard kick || lock.withLock({ accepting }) else { throw NativeSessionError.transportClosed }
        if kick { queue.async { self.drain() } }
    }
    public func close() {
        let closeNow = lock.withLock { () -> Bool in
            accepting = false; frames.removeAll(); queuedFrames = 0; queuedBytes = 0
            guard !draining, !closed else { return false }
            closed = true; return true
        }
        if closeNow { Darwin.close(descriptor) }
    }
    deinit { if !closed { Darwin.close(descriptor) } }

    private func drain() {
        while true {
            let frame = lock.withLock { () -> Data? in
                guard accepting, !frames.isEmpty else { return nil }
                return frames.removeFirst()
            }
            guard let frame else { finishDrain(); return }
            guard write(frame) else { fail(); finishDrain(); return }
            lock.withLock { if accepting { queuedFrames -= 1; queuedBytes -= frame.count } }
            let done = lock.withLock { () -> Bool in
                if accepting, frames.isEmpty { draining = false; return true }
                return false
            }
            if done { return }
        }
    }
    private func finishDrain() {
        let closeNow = lock.withLock { () -> Bool in
            accepting = false; draining = false; frames.removeAll(); queuedFrames = 0; queuedBytes = 0
            guard !closed else { return false }; closed = true; return true
        }
        if closeNow { Darwin.close(descriptor) }
    }
    private func fail() {
        let notify = lock.withLock { () -> Bool in
            accepting = false
            guard !failed else { return false }; failed = true; return true
        }
        if notify { onFailure() }
    }
    private func write(_ frame: Data) -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        return frame.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            var offset = 0
            while offset < raw.count {
                guard lock.withLock({ accepting }) else { return false }
                let now = DispatchTime.now().uptimeNanoseconds
                guard now >= start, now - start < writeDeadlineNanoseconds else { return false }
                let count = Darwin.write(descriptor, base.advanced(by: offset), raw.count - offset)
                if count > 0 { offset += count; continue }
                if count < 0, errno == EINTR { continue }
                guard count < 0, errno == EAGAIN || errno == EWOULDBLOCK else { return false }
                var descriptorState = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                let result = Darwin.poll(&descriptorState, 1, 5)
                if result < 0, errno != EINTR { return false }
                if descriptorState.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 { return false }
            }
            return true
        }
    }
}
