#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARENT="$ROOT/.."

# This builds/locally signs a one-shot CLI bundle, NOT a background agent.
# No microphone capture or model download occurs during packaging.
swift build --package-path "$ROOT" -c debug --product relay-asr-spike
BIN_DIR="$(swift build --package-path "$ROOT" -c debug --show-bin-path)"
APP="$BIN_DIR/RelayASRSpike.app"
mkdir -p "$APP/Contents/MacOS"

cp "$BIN_DIR/relay-asr-spike" "$APP/Contents/MacOS/relay-asr-spike"
cp "$PARENT/Packaging/Info.plist" "$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string relay-asr-spike "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string RelayASRSpike "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.relay.local-asr-spike "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Signed local ASR app: $APP"
echo "No microphone/system capture, model inference, or model download was started."
echo "Run the bundled executable with no arguments for the dry-run help."
