import AVFoundation
import AudioToolbox
import XCTest
@testable import RelayAudioBuffer

/// All tests use fabricated PCM and process identifiers. Never request
/// TCC permission, open apps, start a process tap or store real audio in CI.
final class SelectedAppTapTests: XCTestCase {
    func testExplicitBundleIDSelectionAndNoGlobalFallback() {
        XCTAssertTrue(SelectedAppProcesses.isValidBundleID("us.zoom.xos"))
        XCTAssertTrue(SelectedAppProcesses.isValidBundleID("com.google.Chrome"))
        for bad in ["", "*", "everything", ".zoom", "com..zoom",
                    "com.zoom.*", "com.zoom/other", "com.zoom other"] {
            XCTAssertFalse(SelectedAppProcesses.isValidBundleID(bad), bad)
        }
        XCTAssertTrue(SelectedAppProcesses.isSelected(
            "com.google.Chrome",
            processBundleID: "com.google.Chrome.helper.renderer",
            owningBundleID: nil
        ))
        XCTAssertTrue(SelectedAppProcesses.isSelected(
            "us.zoom.xos", processBundleID: "us.zoom.xos",
            owningBundleID: nil
        ))
        XCTAssertFalse(SelectedAppProcesses.isSelected(
            "us.zoom.xos", processBundleID: "com.google.Chrome.helper",
            owningBundleID: "com.google.Chrome"
        ))
        XCTAssertFalse(SelectedAppProcesses.isSelected(
            "us.zoom.xos", processBundleID: nil, owningBundleID: nil
        ))
        XCTAssertEqual(SelectedAppProcesses.parentBundleID(
            "com.google.Chrome.helper.renderer"), "com.google.Chrome")
    }

    func testInterleavedSamplesAreOwnedAndBatched() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
            channels: 2, interleaved: true
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: 5000
        ))
        buffer.frameLength = 5000
        let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        XCTAssertEqual(list.count, 1)
        let floats = try XCTUnwrap(list[0].mData).assumingMemoryBound(to: Float.self)
        for i in 0..<(5000 * 2) { floats[i] = Float(i) / 100 }

        let pcmFormat = try ProcessTapPCMFormat(format.streamDescription.pointee)
        XCTAssertTrue(pcmFormat.isInterleaved)
        let queue = try OwnedPCMQueue(source: .remoteAudio, maximumFrames: 2048)
        let outcome = ProcessTapPCMBridge.publish(
            buffer.audioBufferList, format: pcmFormat, queue: queue,
            hostTime: 1_000_000, generation: 12
        )
        XCTAssertEqual(outcome.accepted, 3)
        XCTAssertEqual(outcome.dropped, 0)
        floats[0] = 99_999 // Mutate borrowed producer memory AFTER publication.

        let p1 = try XCTUnwrap(queue.dequeue())
        let p2 = try XCTUnwrap(queue.dequeue())
        let p3 = try XCTUnwrap(queue.dequeue())
        XCTAssertEqual([p1.frameCount, p2.frameCount, p3.frameCount],
                       [2048, 2048, 904])
        XCTAssertEqual(p1.interleavedSamples.prefix(4).map { $0 },
                       [0, 0.01, 0.02, 0.03])
        XCTAssertEqual(p1.channelCount, 2)
        XCTAssertEqual(p1.source, .remoteAudio)
        XCTAssertEqual(p1.streamGeneration, 12)
        XCTAssertEqual([p1.sequence, p2.sequence, p3.sequence], [1, 2, 3])
        XCTAssertGreaterThan(p2.hostTime, p1.hostTime)
        XCTAssertGreaterThan(p3.hostTime, p2.hostTime)
        XCTAssertNil(queue.dequeue())
    }

    func testPlanarStereoCopiesAndPreservesSource() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 44_100,
            channels: 2, interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: 6
        ))
        buffer.frameLength = 6
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for i in 0..<6 {
            channels[0][i] = Float(i)
            channels[1][i] = Float(i + 10)
        }
        let pcmFormat = try ProcessTapPCMFormat(format.streamDescription.pointee)
        XCTAssertFalse(pcmFormat.isInterleaved)
        let queue = try OwnedPCMQueue(source: .remoteAudio)
        let result = ProcessTapPCMBridge.publish(
            buffer.audioBufferList, format: pcmFormat, queue: queue,
            hostTime: 567, generation: 8
        )
        XCTAssertEqual(result.accepted, 1)
        let packet = try XCTUnwrap(queue.dequeue())
        XCTAssertEqual(packet.channelCount, 2)
        XCTAssertEqual(packet.hostTime, 567)
        XCTAssertEqual(packet.sampleRate, 44_100)
        XCTAssertEqual(packet.interleavedSamples, [
            0, 10, 1, 11, 2, 12, 3, 13, 4, 14, 5, 15
        ])
    }

    func testUnsupportedFormatsRejectBeforeStartingHAL() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
            channels: 1, interleaved: false
        ))
        var invalid = format.streamDescription.pointee
        invalid.mBitsPerChannel = 16
        XCTAssertThrowsError(try ProcessTapPCMFormat(invalid))
        invalid = format.streamDescription.pointee
        invalid.mChannelsPerFrame = 3
        XCTAssertThrowsError(try ProcessTapPCMFormat(invalid))
    }

    func testRingProducerDoesNotExposeOriginalInterleavedPointer() throws {
        let queue = try OwnedPCMQueue(source: .remoteAudio)
        var input: [Float] = [0.25, -0.25, 0.5, -0.5]
        let ok = input.withUnsafeBufferPointer {
            queue.enqueueInterleaved(
                samples: $0.baseAddress!, frames: 2, channels: 2,
                sampleRate: 48_000, hostTime: 42, streamGeneration: 1
            )
        }
        XCTAssertTrue(ok)
        input[0] = 100
        let frame = try XCTUnwrap(queue.dequeue())
        XCTAssertEqual(frame.interleavedSamples, [0.25, -0.25, 0.5, -0.5])
    }
}
