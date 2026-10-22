import XCTest
@testable import RelayAudioBuffer

/// Mac-only tests: the ring uses Darwin VM mapping in the pinned C library.
/// No microphone permission or external API is required for these tests.
final class OwnedPCMQueueTests: XCTestCase {
    func testCopiedSamplesDoNotBorrowCallbackMemory() throws {
        let queue = try OwnedPCMQueue(source: .microphone)
        var source: [Float] = [0.125, -0.25, 0.75, 0.5]
        let accepted = source.withUnsafeBufferPointer { buffer in
            queue.enqueuePlanar(
                first: buffer.baseAddress!, frames: source.count,
                sampleRate: 48_000, hostTime: 1234, streamGeneration: 7
            )
        }
        XCTAssertTrue(accepted)
        source[0] = 99

        let result = try XCTUnwrap(queue.dequeue())
        XCTAssertEqual(result.interleavedSamples, [0.125, -0.25, 0.75, 0.5])
        XCTAssertEqual(result.source, .microphone)
        XCTAssertEqual(result.sequence, 1)
        XCTAssertEqual(result.hostTime, 1234)
        XCTAssertEqual(result.streamGeneration, 7)
        XCTAssertEqual(result.frameCount, 4)
        XCTAssertEqual(result.channelCount, 1)
        XCTAssertNil(queue.dequeue())
    }

    func testStereoChannelsInterleaveWithoutInputAllocation() throws {
        let queue = try OwnedPCMQueue(source: .remoteAudio)
        let left: [Float] = [1, 2, 3]
        let right: [Float] = [4, 5, 6]
        let inserted = left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                queue.enqueuePlanar(
                    first: l.baseAddress!, second: r.baseAddress!,
                    frames: 3, sampleRate: 44_100,
                    hostTime: 9876, streamGeneration: 3
                )
            }
        }
        XCTAssertTrue(inserted)
        let result = try XCTUnwrap(queue.dequeue())
        XCTAssertEqual(result.interleavedSamples, [1, 4, 2, 5, 3, 6])
        XCTAssertEqual(result.source, .remoteAudio)
        XCTAssertEqual(result.channelCount, 2)
        XCTAssertEqual(result.sampleRate, 44_100)
    }

    func testFullQueueDropsNewestAndSequenceShowsGapAfterResume() throws {
        let queue = try OwnedPCMQueue(source: .microphone,
                                      capacityBytes: 16_384,
                                      maximumFrames: 1024)
        let chunk = [Float](repeating: 0.5, count: 1024)
        var accepted = 0
        var dropped = 0
        chunk.withUnsafeBufferPointer { buffer in
            for _ in 0..<20 {
                if queue.enqueuePlanar(first: buffer.baseAddress!,
                                       frames: 1024, sampleRate: 16_000,
                                       hostTime: 44, streamGeneration: 1) {
                    accepted += 1
                } else {
                    dropped += 1
                }
            }
        }
        XCTAssertGreaterThan(accepted, 0)
        XCTAssertGreaterThan(dropped, 0)

        var delivered: [PCMFrame] = []
        while let result = queue.dequeue() { delivered.append(result) }
        XCTAssertEqual(delivered.count, accepted)
        XCTAssertEqual(delivered.map(\.sequence), Array(1...UInt64(accepted)))

        let resumed = chunk.withUnsafeBufferPointer { buffer in
            queue.enqueuePlanar(first: buffer.baseAddress!, frames: 1024,
                                sampleRate: 16_000, hostTime: 45,
                                streamGeneration: 2)
        }
        XCTAssertTrue(resumed)
        let last = try XCTUnwrap(queue.dequeue())
        XCTAssertEqual(last.sequence, UInt64(accepted + dropped + 1))
        XCTAssertEqual(last.streamGeneration, 2)
        XCTAssertNil(queue.dequeue())
    }

    func testRejectsInvalidFrameSizesAndRatesWithoutEnqueue() throws {
        XCTAssertThrowsError(try OwnedPCMQueue(source: .microphone,
                                                capacityBytes: 256))
        let queue = try OwnedPCMQueue(source: .microphone,
                                      maximumFrames: 10)
        let signal = [Float](repeating: 1, count: 20)
        signal.withUnsafeBufferPointer { buffer in
            XCTAssertFalse(queue.enqueuePlanar(first: buffer.baseAddress!,
                                                frames: 11, sampleRate: 16_000,
                                                hostTime: 0, streamGeneration: 1))
            XCTAssertFalse(queue.enqueuePlanar(first: buffer.baseAddress!,
                                                frames: 0, sampleRate: 16_000,
                                                hostTime: 0, streamGeneration: 1))
            XCTAssertFalse(queue.enqueuePlanar(first: buffer.baseAddress!,
                                                frames: 8, sampleRate: 0,
                                                hostTime: 0, streamGeneration: 1))
        }
        XCTAssertNil(queue.dequeue())
    }

    func testPacketOrderAndGenerationAfterConsumerReusesSlots() throws {
        let queue = try OwnedPCMQueue(source: .microphone)
        let first = [Float](repeating: 0.2, count: 32)
        for generation in 1...4 {
            let accepted = first.withUnsafeBufferPointer { buffer in
                queue.enqueuePlanar(first: buffer.baseAddress!, frames: 32,
                                    sampleRate: 24_000,
                                    hostTime: UInt64(generation * 100),
                                    streamGeneration: UInt64(generation))
            }
            XCTAssertTrue(accepted)
            let output = try XCTUnwrap(queue.dequeue())
            XCTAssertEqual(output.sequence, UInt64(generation))
            XCTAssertEqual(output.streamGeneration, UInt64(generation))
            XCTAssertEqual(output.hostTime, UInt64(generation * 100))
            XCTAssertEqual(output.interleavedSamples, first)
        }
    }
}
