# Relay native continuous session

Real explicit-start microphone and selected-app capture, separate local FluidAudio VAD/ASR state, bounded owned PCM and versioned session events. Default launch starts no capture or model work.

See [native session implementation and acceptance](../../docs/NATIVE_SESSION.md), [shared contract](../../docs/BUILD_CONTRACT.md), and [licenses/source pins](THIRD_PARTY_NOTICES.md).

Offline tests: `swift test --package-path spikes/macos-session` from repository root. Tests use synthetic injected models/producers, never weights or permissions. Build the local command bundle with `spikes/macos-session/scripts/build-session-app.sh`; default launch prints safe help. The final ordinary answer window lives in `spikes/macos-panel`.
