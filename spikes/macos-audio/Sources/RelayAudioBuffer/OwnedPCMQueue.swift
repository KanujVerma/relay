import CTPCircularBuffer
import Foundation

/// Bounded owned PCM packet handoff, backed by Michael Tyson's proven
/// TPCircularBuffer (zlib-style licensed, pinned in Package.swift).
///
/// EXACTLY one producer callback and one consumer worker per instance.
/// Audio callbacks call only enqueuePlanar, which copies into preallocated
/// virtual memory. No locks, disk I/O, new arrays, inference or waits occur
/// on the callback path. A new queue is used for each audio source.
///
/// On overflow the NEWEST packet is dropped. Each attempted packet receives
/// a sequence so the consumer can detect missing packets when capture resumes.
///
/// WARNING: stop the producer and consumer before releasing this object.
public final class OwnedPCMQueue: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<TPCircularBuffer>
    private let source: PCMSource
    public let maximumFrames: Int

    // Producer-only state. Never access this variable from the consumer.
    private var nextSequence: UInt64 = 0

    public init(source: PCMSource, capacityBytes: Int = 131_072,
                maximumFrames: Int = 2048) throws {
        guard capacityBytes >= 16_384, capacityBytes < Int(UInt32.max),
              maximumFrames > 0, maximumFrames <= 8192 else {
            throw PCMQueueError.invalidConfiguration
        }
        let pointer = UnsafeMutablePointer<TPCircularBuffer>.allocate(capacity: 1)
        pointer.initialize(to: TPCircularBuffer())
        guard _TPCircularBufferInit(
            pointer, UInt32(capacityBytes), MemoryLayout<TPCircularBuffer>.size
        ) else {
            pointer.deinitialize(count: 1)
            pointer.deallocate()
            throw PCMQueueError.allocationFailed
        }
        storage = pointer
        self.source = source
        self.maximumFrames = maximumFrames
    }

    deinit {
        // Caller MUST stop capture and consumer before releasing the ring.
        TPCircularBufferCleanup(storage)
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    /// Copy one or two non-interleaved Float32 source channels into an owned
    /// interleaved packet. Never stores pointers supplied by Core Audio.
    ///
    /// This method is producer-only and must not run concurrently for one queue.
    /// A rejected packet is dropped without blocking; sequence advances.
    @discardableResult
    public func enqueuePlanar(
        first: UnsafePointer<Float>,
        second: UnsafePointer<Float>? = nil,
        frames: Int,
        sampleRate: Double,
        hostTime: UInt64,
        streamGeneration: UInt64
    ) -> Bool {
        nextSequence &+= 1
        let count = second == nil ? 1 : 2
        guard frames > 0, frames <= maximumFrames,
              sampleRate.isFinite, sampleRate > 0 else {
            return false
        }

        let sampleCount = frames * count // bounded by maximumFrames and 2
        let occupied = PacketHeader.bytes + sampleCount * MemoryLayout<Float>.stride
        let aligned = (occupied + 7) & ~7
        guard aligned <= Int(UInt32.max) else { return false }

        var available: UInt32 = 0
        guard let head = TPCircularBufferHead(storage, &available),
              available >= UInt32(aligned) else {
            return false
        }

        var packet = PacketHeader(
            magic: PacketHeader.magicConstant,
            totalBytes: UInt32(aligned),
            sequence: nextSequence,
            hostTime: hostTime,
            generation: streamGeneration,
            sampleRate: sampleRate,
            sourceCode: source.rawValue,
            channelCount: UInt32(count),
            frameCount: UInt32(frames),
            reserved: 0
        )
        withUnsafeBytes(of: &packet) { bytes in
            head.copyMemory(from: bytes.baseAddress!, byteCount: PacketHeader.bytes)
        }

        let destination = head.advanced(by: PacketHeader.bytes)
                              .assumingMemoryBound(to: Float.self)
        if let second {
            for index in 0..<frames {
                destination[index * 2] = first[index]
                destination[index * 2 + 1] = second[index]
            }
        } else {
            destination.update(from: first, count: frames)
        }
        // Publish exactly once, after ALL samples are copied.
        TPCircularBufferProduce(storage, UInt32(aligned))
        return true
    }

    /// Consumer-only. The returned array owns its samples and remains valid
    /// after the circular buffer slot has been reused by future callbacks.
    /// Allocation is safe here because this MUST NOT run on the capture thread.
    public func dequeue() -> PCMFrame? {
        var available: UInt32 = 0
        guard let tail = TPCircularBufferTail(storage, &available),
              available >= UInt32(PacketHeader.bytes) else { return nil }

        let header = tail.load(as: PacketHeader.self)
        let frames = Int(header.frameCount)
        let channels = Int(header.channelCount)
        let occupied = PacketHeader.bytes +
                       frames * channels * MemoryLayout<Float>.stride
        let aligned = (occupied + 7) & ~7
        guard header.magic == PacketHeader.magicConstant,
              let tag = PCMSource(rawValue: header.sourceCode),
              tag == source,
              frames > 0, frames <= maximumFrames,
              (1...2).contains(channels),
              header.sampleRate.isFinite, header.sampleRate > 0,
              aligned <= Int(UInt32.max),
              header.totalBytes == UInt32(aligned) else {
            // A corrupt internal packet cannot be safely decoded.
            // Drop buffered content instead of exposing unrelated bytes.
            TPCircularBufferClear(storage)
            return nil
        }
        guard available >= header.totalBytes else { return nil }

        let start = tail.advanced(by: PacketHeader.bytes)
                        .assumingMemoryBound(to: Float.self)
        let detached = Array(UnsafeBufferPointer(
            start: start, count: frames * channels
        ))
        TPCircularBufferConsume(storage, header.totalBytes)
        return PCMFrame(
            source: tag,
            streamGeneration: header.generation,
            sequence: header.sequence,
            hostTime: header.hostTime,
            sampleRate: header.sampleRate,
            channelCount: channels,
            frameCount: frames,
            interleavedSamples: detached
        )
    }
}
