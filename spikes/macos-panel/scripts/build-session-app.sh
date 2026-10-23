#!/bin/bash
set -euo pipefail
relay_panel_dir="$(cd "$(dirname "$0")/.." && pwd)"
relay_build_configuration="${RELAY_BUILD_CONFIGURATION:-debug}"
swift build --package-path "$relay_panel_dir" --configuration "$relay_build_configuration" --product relay-panel-session
relay_bin_dir="$(swift build --package-path "$relay_panel_dir" --configuration "$relay_build_configuration" --show-bin-path)"
relay_app_dir="$relay_panel_dir/.build/Relay.app"
mkdir -p "$relay_app_dir/Contents/MacOS"
cp "$relay_bin_dir/relay-panel-session" "$relay_app_dir/Contents/MacOS/relay-panel-session"
cp "$relay_panel_dir/Packaging/Info.plist" "$relay_app_dir/Contents/Info.plist"
codesign --force --sign - "$relay_app_dir"
printf '%s\n' "$relay_app_dir"
