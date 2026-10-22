# Relay audio spike 03A-1A/1B: owned PCM, microphone, selected-app output

**Status: experimental, permission tests pending on actual Mac.** The Swift package now has an in-memory, consent-driven microphone path and a Core Audio tap for an *explicitly selected app*'s output. No streaming transcription, Zoom integration, speaker identification, interview UI, or true end-to-end latency measurements exist yet. Neither a successful build nor a started system tap proves capture authorization.

## Why this design?
Relay's permitted live sessions need reliable local mic vs remote streams, low memory overhead on a 16 GB M2 Pro, and no default audio recording. The open-source [SystemAudioKit](https://github.com/pieralukasz/SystemAudioKit) has good capture/permission/device patterns, but its public recorder writes aligned WAV files rather than publishing owned live PCM chunks.

Instead of reinventing a lock-free queue, this slice reuses Michael Tyson's battle-tested single-producer/single-consumer [TPCircularBuffer](https://github.com/michaeltyson/TPCircularBuffer), pinned at commit `cc520397504bb72bc6df79ff03eb72988a6dc50d`. Its source carries a permissive zlib-style license and original copyright. We do not vendor or claim authorship of that code. Mic capture adapts the MIT-licensed SystemAudioKit microphone tap pattern from commit `ccc6ab1e53b27e16b2eb4c01890560568a73d38c`, replacing its file writer with an owned bounded queue. The upstream copyright and complete MIT notice are preserved in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Later, a separate PR will add selected-app Core Audio taps and FluidAudio local EOU.

## Build and offline tests (on macOS 14.2+)

Requires Apple Silicon or Intel Mac with Xcode command-line Swift 6 tools and Swift Package Manager, and network access once to fetch the pinned external package. Run from the repository root:

```bash
cd spikes/macos-audio
swift build
swift test
swift run relay-audio-spike
```

The last command is a **dry run**. It does not touch the microphone, open a network connection, or write audio.

## Explicit microphone smoke test: bundle required

Do **not** invoke an unbundled `swift run relay-audio-spike --mic` to request fresh microphone permission. macOS requires `NSMicrophoneUsageDescription` in the app's Info.plist. This spike deliberately refuses to request access if the usage description is missing.

Package the already-compiled CLI into a local, ad-hoc-signed `.app` containing the purpose string, then explicitly launch its executable:

```bash
bash scripts/build-mic-app.sh
BIN_DIR="$(swift build -c debug --show-bin-path)"
"$BIN_DIR/RelayAudioSpike.app/Contents/MacOS/relay-audio-spike" --mic --seconds 5
```

The CLI requests microphone permission through AVFoundation and captures for 1–20 seconds only with a valid app bundle. On a Mac, approve `RelayAudioSpike` in System Settings → Privacy & Security → Microphone if prompted. Rebuilding an ad-hoc-signed bundle can require regranting permission. If bundle identification fails, Relay prints a safe error without asking TCC for access. It prints only an aggregate packet count, sample frames, **observed** sequence gaps (not a total loss counter), and RMS amplitude. It does not print, store, transmit, or transcribe audio content.

Use headphones and no personal meeting audio for this test. Stop/revoke microphone consent at any time. The CLI is deliberately not a background app; it only listens with explicit `--mic`, and does not attempt screen-share evasion.

## Data/ownership contract

- One `OwnedPCMQueue` per source (mic or remote). **Single producer callback + single worker consumer only.**
- Source channel is *not* remote participant identification. A remote channel can contain several people.
- PCM is copied to a preallocated TPCircularBuffer packet **before** it is published; an `AVAudioPCMBuffer` or `AudioBufferList` pointer must never outlive its callback.
- Each packet has source, monotonic host time, sample rate, channel count, frame count, stream generation and monotonically advancing producer sequence.
- Audio callback: fixed-cost native memory copy into available ring space. No file writes, locks, resampling, Cloud API, allocations or AI inference. It drops the newest packet on overflow. Sequence gaps can later reveal intervening losses but do **not** account for losses before the first or after the last delivered packet.
- Consumer: detaches an owned `[Float]` and can perform downstream normalization to 16 kHz or ASR on a worker. Do not run the consumer from the audio callback.
- Stop capture and consumer before deinitializing queues. A later slice will add explicit device/restart and remote-process capture lifecycle.

## Evidence, limitations, next work

This PR adds isolated queue and oversized-callback tests, a non-interactive bundled-plist check on public macOS CI, but interactive microphone permission and actual device performance must be validated on the user's own Mac before declaring this functional for Relay. No private interviews or speech fixtures should ever go into the public repo or GitHub Actions.

Expected local test results to report (sanitized): macOS/Swift version, `swift test` outcome, whether explicit mic permission succeeded, 5-second packet count, any observed drops, and peak RSS/CPU if measured. No raw audio, transcripts, account credentials or callback URLs.

Next narrow slice of [Issue #22](https://github.com/KanujVerma/relay/issues/22): selected-app Core Audio process tap producing **its own** bounded ring, then optional FluidAudio Parakeet EOU on a worker with measured timing. Review [the audio research](../../docs/research/MAC_AUDIO_STACK.md) before changing that boundary. Stay separate from Issues #21 and #23.

## Selected-app output smoke test, 03A-1B (Mac only)

Build a local app bundle with **both** `NSMicrophoneUsageDescription` and `NSAudioCaptureUsageDescription`, no permission request during the build. **Only run the bundled executable** for system-audio consent:

```bash
cd spikes/macos-audio
swift test
bash scripts/build-mic-app.sh
BIN_DIR="$(swift build -c debug --show-bin-path)"
APP="$BIN_DIR/RelayAudioSpike.app/Contents/MacOS/relay-audio-spike"

# No recording, permission prompt, or inference:
"$APP"
"$APP" --list-audio-apps

# Start an app that is actually playing synthetic/consented audio.
# Pick its exact bundle ID from --list-audio-apps, then explicitly request
# ONLY that selected app for up to 5 seconds:
"$APP" --system-app us.zoom.xos --seconds 5 --expect-audible
```

The `us.zoom.xos` value is an **example**, not a promise that it matches every Zoom build. You must choose from available audio bundle IDs. A browser ID (e.g. `com.google.Chrome`) can capture audio from **all that browser's tabs**, not just a Google Meet call. This is a user-selected *application output channel*, not voice diarization.

**macOS permission and error behavior:** Apple's public Core Audio process tap can prompt for "System Audio Recording Only" when the aggregate device starts. The program never calls private TCC APIs and never falls back silently to all-system capture or broader Screen Recording. Taps denied permission may still start and deliver exactly zeroed buffers. `signal=unverified_or_silent` is **not** proof that the app is quiet or permission was granted. Try `--expect-audible` with a deliberately audible source, inspect System Settings → Privacy & Security → Screen & System Audio Recording, and record that result locally. `signal=nonzero_samples_observed` only reports real PCM amplitude, not permission metadata or interviewer identity.

**Lifecycle:** Core Audio process IDs for the selected app and its helper processes are resolved from the public process object list. On default output device changes or process-list changes, the tap is torn down and recreated **only for the same selected app**; if no matching process remains, capture reports unavailable. Actual Bluetooth switching, helper respawns, app quitting, denied consent, macOS TCC prompts, and concurrency need Mac smoke tests before this can be called reliable.

The process tap uses the **same pinned TPCircularBuffer** as the microphone. It accepts Float32 interleaved or planar mono/stereo, copies source bytes to owned packets inside the audio callback, and splits oversized buffers. It does not write WAV files or call transcription/ChatGPT models. Only the worker drains packets for aggregate amplitude and observed packet gaps; no raw audio reaches GitHub or app logs.

**Local validation gate:** Test `--system-app` with a known audible, consented source, denial/revocation, muted/quiet source, selected-app quit/relaunch, output switching including Bluetooth headphones, and simultaneous microphone if desired in a later slice. Report only the chosen bundle name, macOS/Swift version, capture status, counts, signal amplitude/nonzero status, drop indicators, and whether the separate test was consented. Do not share actual meeting content or transcripts.

**Next:** Local FluidAudio EOU transcription in a separate 03A-1C slice, after confirming that selected-app PCM capture works on the 16 GB M2 Pro. This is not a stealth recording tool; only use it where capture and AI assistance are permitted.
