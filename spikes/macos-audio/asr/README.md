# Relay Slice 03A-1C: on-device final transcript spike

**Status: source implementation and synthetic validation only until a real M2 Pro on-device transcription run.** This is an experimental local English ASR worker feeding on the already-proven **owned** PCM queues. It is NOT a native interview panel, tutoring product, or authorized permission for recording live calls.

## Architecture and open-source reuse

- `../`: existing macOS microphone and selected-app Core Audio taps (PRs #27/#32) backed by the **same** pinned `TPCircularBuffer`. This ASR package adds no second capture system.
- `RelayLocalASR.PCMTranscriptWorker`: *one* actor consumes detached `PCMFrame` packets on a worker, preserves capture channel and generation, normalizes with **FluidAudio's AVAudioConverter-based `AudioConverter`**, and resets on gaps, rate changes, errors and cancellation. No inference/normalization on HAL callback.
- `FluidEouRecognizer`: thin adapter over pinned FluidAudio `StreamingEouAsrManager` (English Parakeet EOU 120M). Start with `.ms320` and 1280 ms silence debounce, which MUST be measured on the owner's M2 Pro. The 320ms variant uses ~630ms of input per encoder window internally, so **320ms is not the end-of-question latency**.
- `FinalTranscriptEvent`: `final`, `discontinuity`, or `unavailable`, source channel `microphone` or `remoteAudio`, stream generation, segment ID, revision, host timestamps where available, and finalization uptime. **No confidence is invented** and model-generated text is unverified. These are data for Issue #43's future turn adapter, not approved personal facts or speaker identity.
- **No partial text:** the pinned EOU `process(audioBuffer:)` method returns empty; only `finish()` produces the final text. Its upstream optional partial callback is not wired. The local status can only claim final.
- **Blank terminal is not silence:** a successful EOU whose `finish()` returns only whitespace emits `status=final` with `text=""` and `isBlankEOUTerminal=true`, rather than nil/no event. The CLI prints a nontext `terminal=blank_final` status, including when transcript display is opted in. This is the native source signal required by the already-merged synthetic [versioned wire contract](../../../docs/NATIVE_EOU_WIRE.md) and eventual Python blank-final tombstone. **No native serializer or direct active-turn cancellation is wired yet**; that remains part of issue #43. Silence without EOU is still ignored; discontinuity/unavailable remains a separate control event.
- PCM downmix/resampling happens on the worker using fixed ~320ms *input windows*. The current FluidAudio converter is stateless across windows; validate packet-boundary resampling quality and latency before promoting this to production. Model weights are NOT included and are under the separate NVIDIA Open Model License.

## 1. Build and offline tests, no model weights

From the Relay repo:

```bash
cd spikes/macos-audio/asr
swift test
swift run relay-asr-spike
```

The second command is a zero-network, zero-model, zero-capture dry run. CI uses **fake recognizers** only and must never download model weights, capture user audio or send any paid API requests.

Build a separate locally signed .app with microphone/system-audio usage descriptions:

```bash
bash scripts/build-asr-app.sh
BIN_DIR="$(swift build -c debug --show-bin-path)"
APP="$BIN_DIR/RelayASRSpike.app/Contents/MacOS/relay-asr-spike"
"$APP"
```

Do not use unbundled `swift run ... --mic` for actual TCC permission prompts.

## 2. Explicitly prepare your own model cache (network only here)

Review **[NVIDIA's Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/)** and the [model card](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml). If you accept its terms, explicitly download the 320ms variant into a local user directory **outside the repo**:

```bash
MODEL_ROOT="$HOME/Library/Application Support/Relay/Models"
"$APP" --prepare-model --model-root "$MODEL_ROOT" --accept-nvidia-license
```

The pinned FluidAudio SDK downloads and loads models only for `--prepare-model`. This requires internet access and can use substantial disk/RAM on first run. The expected model folder is `$MODEL_ROOT/parakeet-eou-streaming/320ms`. A normal capture command loads from that local folder **without downloading**; absent/broken model data fails closed. This demo doesn't commit/bundle model weights, record them in Git, or silently contact Hugging Face after a normal launch.

## 3. Manual private speech test, with permission

Use **your own synthetic statements** such as:

- "What is the difference between SQL WHERE and HAVING?"
- "Explain why binary search is logarithmic on a sorted array."
- "When could a left join duplicate rows?"

Run the signed app with a *deliberately* enabled mic. Display the local transcript only if you explicitly opt in:

```bash
"$APP" --mic --seconds 20 --model-root "$MODEL_ROOT" --show-transcript
```

To test system output from a specific consented app, first start that app playing **your own synthetic speech**, then choose its exact Core Audio bundle ID (the existing `../` capture demo supports `--list-audio-apps`):

```bash
"$APP" --system-app com.google.Chrome --seconds 20 \
  --model-root "$MODEL_ROOT" --show-transcript
```

Selecting Chrome may include other tabs. Never record meetings, private speech, interviews or another person's audio without appropriate consent and authorization. The event source channel is not a speaker ID. No raw audio file or transcript is persisted by the demo. When `--show-transcript` is omitted, it prints status and character count only.

### Measurements to report

Report sanitized results: macOS/Swift version, M2 Pro 16GB memory, cold/warm model preparation/load timings, `status=final` or `unavailable`, correctness of *synthetic* SQL/coding vocabulary against reference sentences, elapsed end-of-utterance to final transcript where instrumented, peak RSS/CPU and observed input sequence gaps. Be precise: **current code emits finalization uptime and captured host timestamps, not a independently validated end-of-speech-to-final latency**; additional instrumentation/human validation is required.

## Known boundaries

- Source `remoteAudio` is the output of the *selected app*, which may contain multiple participants. Not proof of interviewer identity.
- Short/unclear/low-volume speech, overlapping talk, Bluetooth switches, stopped permissions, model errors or missing PCM can cause unavailable/discontinuity. No speculative transcript repair.
- `--prepare-model` may download model weights under NVIDIA's license and SDK-native cache layout. Normal capture never downloads a model.
- No automatic second model, OAuth request, personalized response rendering, answer quality score, saved transcript, or learning-memory promotion.
- If the first real M2 Pro demo fails to build, load, recognize, or meet latency/CPU requirements, treat it as a **blocking observation**, not production success.

See [Issue #33](https://github.com/KanujVerma/relay/issues/33) and parent [Issue #22](https://github.com/KanujVerma/relay/issues/22). Issue #43's independent transcript-to-turn adapter must consume finalized events conservatively after this payload is verified on hardware.
