#!/usr/bin/env bash
set -euo pipefail

# Run from anywhere. No actual mic authorization or audio capture occurs here.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

swift build -c debug --product relay-audio-spike
BIN_DIR="$(swift build -c debug --show-bin-path)"
APP="$BIN_DIR/RelayAudioSpike.app"

mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/relay-audio-spike" "$APP/Contents/MacOS/relay-audio-spike"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built a locally ad-hoc-signed CLI app bundle: $APP"
echo "No microphone has been opened."
echo "Explicit smoke test (1 to 20s):"
echo "  \"$APP/Contents/MacOS/relay-audio-spike\" --mic --seconds 5"
echo "Check macOS System Settings > Privacy & Security > Microphone if denied."
