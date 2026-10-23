import Darwin
import Dispatch
import Foundation
import RelayNativeSession
import RelaySessionCapture

private final class StopSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func stop() { lock.withLock { value = true } }
    var stopped: Bool { lock.withLock { value } }
}

@main struct SessionCommand {
    @MainActor static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard !arguments.isEmpty, !arguments.contains("--help") else { help(); return }
        do {
            let allowedFlags: Set<String> = ["--start", "--mic", "--authorized-conversation", "--acknowledge-local-model-licenses"]
            let allowedValues: Set<String> = ["--selected-app", "--asr-model-root", "--vad-model", "--event-fd"]
            var flags: Set<String> = [], values: [String: String] = [:]
            var index = 0
            while index < arguments.count {
                let key = arguments[index]
                if allowedFlags.contains(key), !flags.contains(key) { flags.insert(key); index += 1 }
                else if allowedValues.contains(key), values[key] == nil, index + 1 < arguments.count {
                    values[key] = arguments[index + 1]; index += 2
                } else { throw NativeSessionError.invalidConfiguration }
            }
            guard flags.contains("--start"), let asr = values["--asr-model-root"], let vad = values["--vad-model"],
                  let rawDescriptor = values["--event-fd"], let descriptor = Int32(rawDescriptor), descriptor >= 3 else {
                throw NativeSessionError.invalidConfiguration
            }
            let config = NativeCaptureConfiguration(microphoneEnabled: flags.contains("--mic"),
                selectedBundleID: values["--selected-app"], asrModelRoot: URL(fileURLWithPath: asr),
                vadCompiledModel: URL(fileURLWithPath: vad), authorizedConversation: flags.contains("--authorized-conversation"),
                localModelLicensesAcknowledged: flags.contains("--acknowledge-local-model-licenses"))
            try config.validateLocalModels()
            let authority = SessionPresentationAuthority()
            let writer = try BoundedSessionEventWriter(descriptor: descriptor, onFailure: { authority.stop() })
            let session = NativeCaptureSession(authority: authority, onEvent: writer.enqueue)
            let stop = StopSignal()
            // Dedicated terminal controls: Return/EOF or SIGINT requests actual
            // producer shutdown; stdout is never the protocol descriptor.
            signal(SIGINT, SIG_IGN)
            let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            interrupt.setEventHandler { stop.stop() }; interrupt.resume()
            let input = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .global())
            input.setEventHandler {
                var bytes = [UInt8](repeating: 0, count: 256)
                let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
                if count <= 0 || bytes.prefix(count).contains(10) { stop.stop() }
            }
            input.resume()
            defer { input.cancel(); interrupt.cancel(); writer.close() }
            let pendingStart = Task { try await session.start(configuration: config) }
            let stopDuringStart = Task { @MainActor in
                while !Task.isCancelled {
                    if stop.stopped { await session.stop(); return }
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
            defer { stopDuringStart.cancel() }
            try await pendingStart.value
            status("session_running_press_return_to_stop")
            while !stop.stopped, authority.snapshot() != nil, session.phase != .idle {
                try await Task.sleep(for: .milliseconds(20))
            }
            await session.stop()
            _ = await writer.flush(timeoutMilliseconds: 600)
            status(session.phase == .idle ? "session_stopped" : "session_stopping_producer_not_quiescent")
        } catch {
            // No arbitrary model, path, transcript or driver error enters logs.
            status("session_start_failed")
        }
    }
    private static func status(_ value: String) {
        FileHandle.standardError.write(Data((value + "\n").utf8))
    }
    private static func help() {
        print("""
        Relay native continuous session (no action on default launch).
        Start only for a conversation you are permitted to capture and assist.

          --start --authorized-conversation --acknowledge-local-model-licenses
          --mic and/or --selected-app com.example.meeting
          --asr-model-root /local/model-root
          --vad-model /local/silero_vad.mlmodelc --event-fd 3

        Supply a dedicated inherited writable pipe FD >=3. It receives bounded
        length-prefixed session JSON, never PCM. This command records no files
        and downloads no models. Press Return or Ctrl-C to stop actual capture.
        Build the native app bundle for the required macOS permission purposes.
        """)
    }
}
