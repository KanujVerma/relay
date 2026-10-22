import Dispatch
import Foundation
import RelayAudioBuffer

/// Explicit, bounded mic or SINGLE selected-app capture. No recording to disk,
/// speech recognition or ChatGPT usage. A default invocation is a dry run.
@main
struct RelayAudioSpikeCLI {
    private struct Options {
        var microphone = false
        var systemApp: String?
        var listApps = false
        var expectAudible = false
        var duration = 5
    }

    private struct Statistics {
        var packets = 0
        var frames = 0
        var samples = 0
        var sumSquares = 0.0
        var sequenceGaps: UInt64 = 0
        var previousSequence: UInt64?

        mutating func record(_ packet: PCMFrame) {
            packets += 1
            frames += packet.frameCount
            samples += packet.interleavedSamples.count
            if let previousSequence, packet.sequence > previousSequence {
                sequenceGaps += packet.sequence - previousSequence - 1
            }
            previousSequence = packet.sequence
            for sample in packet.interleavedSamples {
                let x = Double(sample)
                sumSquares += x * x
            }
        }

        var rms: Double {
            samples > 0 ? (sumSquares / Double(samples)).squareRoot() : 0
        }

        func report(channel: String) {
            print("channel=\(channel) packets=\(packets) frames=\(frames) " +
                  "sequence_gaps_observed=\(sequenceGaps) rms=\(rms)")
            print("Gaps exclude undelivered first/last packets and are not a total loss count.")
        }
    }

    private static func help() {
        print("Usage: relay-audio-spike")
        print("  --list-audio-apps                  List Core Audio app bundle IDs, no capture")
        print("  --mic --seconds 5                 Explicit microphone-only smoke test")
        print("  --system-app BUNDLE_ID --seconds 5 [--expect-audible]")
        print("Without an explicit source, Relay is a zero-permission dry run.")
        print("To request system-audio capture, use the locally bundled .app executable.")
    }

    private static func options(_ args: [String]) -> Options? {
        var result = Options()
        var i = 0
        var sawDuration = false
        while i < args.count {
            switch args[i] {
            case "--mic":
                guard !result.microphone else { return nil }
                result.microphone = true
            case "--list-audio-apps":
                guard !result.listApps else { return nil }
                result.listApps = true
            case "--expect-audible":
                guard !result.expectAudible else { return nil }
                result.expectAudible = true
            case "--system-app":
                guard result.systemApp == nil, i + 1 < args.count,
                      SelectedAppProcesses.isValidBundleID(args[i + 1]) else {
                    return nil
                }
                i += 1
                result.systemApp = args[i]
            case "--seconds":
                guard !sawDuration, i + 1 < args.count,
                      let n = Int(args[i + 1]), (1...20).contains(n) else {
                    return nil
                }
                i += 1
                result.duration = n
                sawDuration = true
            default:
                return nil
            }
            i += 1
        }
        if result.microphone && result.systemApp != nil { return nil }
        if result.expectAudible && result.systemApp == nil { return nil }
        if result.listApps && (result.microphone || result.systemApp != nil
                               || result.expectAudible || sawDuration) { return nil }
        if sawDuration && !result.microphone && result.systemApp == nil {
            return nil
        }
        return result
    }

    /// Drain bounded batches up to a monotonic capture deadline, never allow
    /// an overflowing queue to prolong the requested capture window.
    private static func sample(_ queue: OwnedPCMQueue,
                               seconds: Int) async throws -> Statistics {
        var stats = Statistics()
        let deadline = DispatchTime.now().uptimeNanoseconds +
                       UInt64(seconds) * 1_000_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            try await Task.sleep(for: .milliseconds(20))
            for _ in 0..<64 {
                guard DispatchTime.now().uptimeNanoseconds < deadline,
                      let packet = queue.dequeue() else { break }
                stats.record(packet)
            }
        }
        return stats
    }

    private static func drainAfterStopping(
        _ queue: OwnedPCMQueue, into stats: inout Statistics
    ) {
        // Producer has stopped, so bounded storage contains finite packets.
        for _ in 0..<256 {
            guard let packet = queue.dequeue() else { break }
            stats.record(packet)
        }
    }

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--help"] || args == ["-h"] {
            help()
            return
        }
        guard let opt = options(args) else {
            print("Invalid flags or bundle ID.")
            help()
            return
        }
        if opt.listApps {
            let ids = SelectedAppProcesses.bundleIDs()
            print("Core Audio app bundle IDs (informational, capture NOT started):")
            if ids.isEmpty { print("No app audio process currently detected.") }
            for id in ids { print("  \(id)") }
            print("Browser selection may include other tabs, not only a call.")
            return
        }
        if let bundle = opt.systemApp {
            do {
                let ring = try OwnedPCMQueue(source: .remoteAudio)
                let tap = SelectedAppProcessTap(queue: ring)
                print("Requesting up to \(opt.duration)s of local output from ONLY \(bundle).")
                print("System Audio Recording permission may be requested by macOS.")
                print("No audio is recorded, transcribed or uploaded.")
                print("The tap status is NOT proof of permission; denial can be silent.")
                try tap.start(bundleID: bundle)
                defer { tap.stop() }
                var stats = try await sample(ring, seconds: opt.duration)
                let stateBeforeStop = tap.status
                tap.stop()
                drainAfterStopping(ring, into: &stats)
                stats.report(channel: "selected-app output")
                print("tap_state_at_stop=\(stateBeforeStop.rawValue)")
                if stats.packets == 0 || stats.rms <= 0.000001 {
                    print("signal=unverified_or_silent. This can mean permission denied, " +
                          "no playback, or another capture limitation.")
                } else {
                    print("signal=nonzero_samples_observed. " +
                          "This alone does not identify an interviewer or prove permission.")
                }
                if opt.expectAudible && stats.rms <= 0.000001 {
                    print("EXPECTED AUDIBLE TEST FAILED OR UNVERIFIED. Check macOS System " +
                          "Settings > Privacy & Security > Screen & System Audio Recording.")
                }
            } catch {
                print("Selected-app capture unavailable: \(error).")
                print("Start the app's audio output, verify bundle ID and OS permission.")
                print("No fallback to capture-all or Screen Recording is attempted.")
            }
            return
        }
        guard opt.microphone else {
            print("DRY RUN. No microphone or system-audio capture requested.")
            help()
            return
        }
        do {
            let ring = try OwnedPCMQueue(source: .microphone)
            let microphone = MicrophoneCapture(queue: ring)
            print("Requesting up to \(opt.duration)s of microphone-only capture.")
            print("No audio is recorded, transcribed or uploaded.")
            try await microphone.start()
            defer { microphone.stop() }
            var stats = try await sample(ring, seconds: opt.duration)
            microphone.stop()
            drainAfterStopping(ring, into: &stats)
            stats.report(channel: "microphone")
        } catch {
            print("Microphone capture unavailable: \(error).")
            print("Check microphone permission in System Settings.")
        }
    }
}
