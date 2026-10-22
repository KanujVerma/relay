import Dispatch
import Foundation
import RelayAudioBuffer
import RelayLocalASR

/// Optional on-device ASR spike, entirely separate from the basic mic/capture
/// CLI. Default command is a DRY RUN: no model load, capture, or network.
@main
struct RelayLocalASRCLI {
    private struct Options {
        var microphone = false
        var systemApp: String?
        var seconds = 15
        var modelRoot: String?
        var prepareModel = false
        var licenseAcknowledged = false
        var showTranscript = false
    }

    private static func help() {
        print("Usage:")
        print("  relay-asr-spike (dry run, zero model loading)")
        print("  relay-asr-spike --prepare-model --model-root /PATH " +
              "--accept-nvidia-license")
        print("  relay-asr-spike --mic --seconds 15 --model-root /PATH " +
              "[--show-transcript]")
        print("  relay-asr-spike --system-app BUNDLE --seconds 15 " +
              "--model-root /PATH [--show-transcript]")
        print("Only --prepare-model with explicit license acknowledgment " +
              "is allowed to download model weights.")
    }

    private static func options(_ args: [String]) -> Options? {
        var opt = Options()
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--mic":
                guard !opt.microphone else { return nil }
                opt.microphone = true
            case "--system-app":
                guard opt.systemApp == nil, i + 1 < args.count else { return nil }
                i += 1
                guard SelectedAppProcesses.isValidBundleID(args[i]) else { return nil }
                opt.systemApp = args[i]
            case "--model-root":
                guard opt.modelRoot == nil, i + 1 < args.count else { return nil }
                i += 1
                guard args[i].hasPrefix("/") else { return nil }
                opt.modelRoot = args[i]
            case "--seconds":
                guard i + 1 < args.count, let n = Int(args[i + 1]),
                      (3...20).contains(n) else { return nil }
                opt.seconds = n
                i += 1
            case "--prepare-model":
                guard !opt.prepareModel else { return nil }
                opt.prepareModel = true
            case "--accept-nvidia-license":
                opt.licenseAcknowledged = true
            case "--show-transcript":
                opt.showTranscript = true
            default:
                return nil
            }
            i += 1
        }
        if opt.microphone && opt.systemApp != nil { return nil }
        if opt.prepareModel {
            return opt.modelRoot != nil && opt.licenseAcknowledged
                && !opt.microphone && opt.systemApp == nil
                && !opt.showTranscript
                ? opt : nil
        }
        if opt.microphone || opt.systemApp != nil {
            return opt.modelRoot != nil ? opt : nil
        }
        if opt.modelRoot != nil || opt.licenseAcknowledged
            || opt.showTranscript || opt.seconds != 15 {
            return nil
        }
        return opt
    }

    private static func show(
        _ event: FinalTranscriptEvent, textOptIn: Bool
    ) {
        print("status=\(event.status.rawValue) source=\(event.source) " +
              "generation=\(event.streamGeneration) " +
              "segment_id=\(event.segmentID) " +
              "finalized_uptime_ns=\(event.finalizedUptimeNanoseconds)")
        if event.status == .final, let text = event.text {
            print("final_text_length=\(text.count) confidence=unavailable")
            if textOptIn {
                print("LOCAL UNVERIFIED TRANSCRIPT: \(text)")
            } else {
                print("Transcript redacted. Use --show-transcript to display " +
                      "your own consented synthetic speech locally.")
            }
        }
    }

    private static func drain(
        queue: OwnedPCMQueue, worker: PCMTranscriptWorker,
        showTranscript: Bool, maximum: Int = 64
    ) async {
        for _ in 0..<maximum {
            guard let frame = queue.dequeue() else { break }
            let events = await worker.ingest(frame)
            for event in events { show(event, textOptIn: showTranscript) }
        }
    }

    private static func run(
        queue: OwnedPCMQueue, worker: PCMTranscriptWorker,
        seconds: Int, showTranscript: Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds +
            UInt64(seconds) * 1_000_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            try await Task.sleep(for: .milliseconds(20))
            await drain(
                queue: queue, worker: worker,
                showTranscript: showTranscript
            )
        }
    }

    private static func finish(
        queue: OwnedPCMQueue, worker: PCMTranscriptWorker,
        showTranscript: Bool
    ) async {
        // Caller MUST stop the Core Audio producer before invoking finish.
        for _ in 0..<256 {
            guard let frame = queue.dequeue() else { break }
            let events = await worker.ingest(frame)
            for event in events { show(event, textOptIn: showTranscript) }
        }
        if let event = await worker.finishAtStop() {
            show(event, textOptIn: showTranscript)
        }
    }

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--help"] || args == ["-h"] {
            help()
            return
        }
        guard let opt = options(args) else {
            print("Invalid options. No capture or model request attempted.")
            help()
            return
        }
        guard let root = opt.modelRoot else {
            print("DRY RUN. No capture, models, download, transcript, or network.")
            help()
            return
        }
        do {
            let backend = FluidEouRecognizer()
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            print("Loading local English Parakeet EOU 320ms model.")
            print("Model weights are licensed under NVIDIA Open Model License.")
            print("No uploaded audio, external inference API or paid service.")
            try await backend.load(
                root: rootURL,
                allowDownload: opt.prepareModel,
                nvidiaModelLicenseAccepted: opt.licenseAcknowledged
            )
            if opt.prepareModel {
                print("Local model prepared; no audio capture attempted.")
                return
            }

            let source: PCMSource = opt.microphone ? .microphone : .remoteAudio
            let queue = try OwnedPCMQueue(source: source)
            let worker = PCMTranscriptWorker(
                source: source, authorizedCapture: true,
                backend: backend
            )
            if opt.microphone {
                let mic = MicrophoneCapture(queue: queue)
                print("Requesting explicit microphone capture for \(opt.seconds)s.")
                try await mic.start()
                defer { mic.stop() }
                try await run(
                    queue: queue, worker: worker,
                    seconds: opt.seconds,
                    showTranscript: opt.showTranscript
                )
                mic.stop()
            } else if let app = opt.systemApp {
                let tap = SelectedAppProcessTap(queue: queue)
                print("Requesting output from explicitly selected app \(app) " +
                      "for \(opt.seconds)s.")
                print("Permission may prompt; silent HAL buffers are not proof " +
                      "that access is granted.")
                try tap.start(bundleID: app)
                defer { tap.stop() }
                try await run(
                    queue: queue, worker: worker,
                    seconds: opt.seconds,
                    showTranscript: opt.showTranscript
                )
                tap.stop()
            }
            await finish(
                queue: queue, worker: worker,
                showTranscript: opt.showTranscript
            )
            print("Capture finished; local ASR session stopped.")
        } catch {
            print("ASR unavailable: \(error).")
            print("No raw audio or transcripts were saved or uploaded.")
        }
    }
}
