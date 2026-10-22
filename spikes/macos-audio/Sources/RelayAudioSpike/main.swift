import Foundation
import RelayAudioBuffer

/// Explicit, bounded, microphone-only consent smoke test.
/// Default invocation is dry-run and neither opens a mic nor stores samples.
@main
struct RelayAudioSpikeCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--help") || args.contains("-h") {
            print("Usage: swift run relay-audio-spike [--mic --seconds 5]")
            print("Without --mic this is a zero-permission dry run.")
            return
        }
        guard args.contains("--mic") else {
            print("DRY RUN. No microphone or system-audio capture requested.")
            print("To explicitly test the microphone: --mic --seconds 5")
            return
        }

        var seconds = 5
        if let index = args.firstIndex(of: "--seconds") {
            guard index + 1 < args.count,
                  let parsed = Int(args[index + 1]),
                  (1...20).contains(parsed) else {
                print("Invalid duration. Use --seconds 1 through 20.")
                return
            }
            seconds = parsed
        }
        let accepted = Set(["--mic", "--seconds"])
        if args.enumerated().contains(where: { index, arg in
            if accepted.contains(arg) { return false }
            if index > 0 && args[index - 1] == "--seconds" { return false }
            return true
        }) {
            print("Unknown option. Use --help.")
            return
        }

        do {
            let queue = try OwnedPCMQueue(source: .microphone)
            let capture = await MicrophoneCapture(queue: queue)
            print("Requesting a microphone-only capture for \(seconds) seconds.")
            print("No audio is recorded to disk, transcribed, or sent to a network.")
            try await capture.start()

            var packets = 0
            var capturedFrames = 0
            var capturedSamples = 0
            var observedGaps: UInt64 = 0
            var lastSequence: UInt64?
            var sumSquares = 0.0

            for _ in 0..<(seconds * 20) {
                try await Task.sleep(for: .milliseconds(50))
                while let packet = queue.dequeue() {
                    packets += 1
                    capturedFrames += packet.frameCount
                capturedSamples += packet.interleavedSamples.count
                    if let lastSequence, packet.sequence > lastSequence {
                        observedGaps += packet.sequence - lastSequence - 1
                    }
                    lastSequence = packet.sequence
                    // Consumer-only level measurement. No raw audio output.
                    for sample in packet.interleavedSamples {
                        sumSquares += Double(sample * sample)
                    }
                }
            }
            await capture.stop()
            while let packet = queue.dequeue() {
                packets += 1
                capturedFrames += packet.frameCount
                capturedSamples += packet.interleavedSamples.count
                if let lastSequence, packet.sequence > lastSequence {
                    observedGaps += packet.sequence - lastSequence - 1
                }
                lastSequence = packet.sequence
                for sample in packet.interleavedSamples {
                    sumSquares += Double(sample * sample)
                }
            }
            let rms = capturedSamples > 0
                ? (sumSquares / Double(capturedSamples)).squareRoot() : 0
            print("Stopped. packets=\(packets) frames=\(capturedFrames) " +
                  "sequence_gaps_observed=\(observedGaps) rms=\(rms)")
            print("Sequence gaps do not count losses before the first frame " +
                  "or after the final delivered frame.")
        } catch {
            print("Microphone spike unavailable: \(error).")
            print("Check Terminal microphone permission in System Settings.")
        }
    }
}
