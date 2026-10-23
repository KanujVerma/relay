#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Compile/package only. No capture, model load, download or permission prompt.
BUILD_ARGS=(--package-path "$SESSION_ROOT" -c debug)
if [[ -n "${RELAY_SWIFT_SCRATCH_PATH:-}" ]]; then BUILD_ARGS+=(--scratch-path "$RELAY_SWIFT_SCRATCH_PATH"); fi
swift build "${BUILD_ARGS[@]}" --product relay-native-session
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP="$BIN_DIR/RelayNativeSession.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/relay-native-session" "$APP/Contents/MacOS/relay-native-session"
cp "$SESSION_ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
# FluidAudio's package resources remain alongside the executable for local use.
for resource in "$BIN_DIR"/*.bundle; do
  if [[ -d "$resource" ]]; then cp -R "$resource" "$APP/Contents/MacOS/"; fi
done
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built local continuous-session bundle: $APP"
echo "No capture or models were started. Run its executable with --help."
