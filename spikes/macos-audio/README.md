# Relay audio spike 03A-1A: owned PCM bridge + microphone

**Status: experimental.** This is only the microphone half of the proposed macOS audio pipeline. It is NOT a finished interview application and cannot capture Zoom remote audio or transcribe speech yet.

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

## Explicit microphone smoke test

When you can safely test with your own synthetic spoken phrases and have permission to record them:

```bash
swift run relay-audio-spike --mic --seconds 5
```

The CLI requests microphone permission through AVFoundation and captures for 1–20 seconds. On a Mac, Terminal or the host app may need microphone access in System Settings → Privacy & Security → Microphone. It prints only an aggregate packet count, sample frames, **observed** sequence gaps (not a total loss counter), and RMS amplitude. It does not print, store, transmit, or transcribe audio content.

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

This PR adds isolated queue tests and a non-interactive build check on public macOS CI, but interactive microphone permission and actual device performance must be validated on the user's own Mac before declaring this functional for Relay. No private interviews or speech fixtures should ever go into the public repo or GitHub Actions.

Expected local test results to report (sanitized): macOS/Swift version, `swift test` outcome, whether explicit mic permission succeeded, 5-second packet count, any observed drops, and peak RSS/CPU if measured. No raw audio, transcripts, account credentials or callback URLs.

Next narrow slice of [Issue #22](https://github.com/KanujVerma/relay/issues/22): selected-app Core Audio process tap producing **its own** bounded ring, then optional FluidAudio Parakeet EOU on a worker with measured timing. Review [the audio research](../../docs/research/MAC_AUDIO_STACK.md) before changing that boundary. Stay separate from Issues #21 and #23.
