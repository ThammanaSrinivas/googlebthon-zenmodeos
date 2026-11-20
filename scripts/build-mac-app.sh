#!/usr/bin/env bash
# Builds "ZenMode OS.app" from the SwiftPM executable and, with --open, launches it.
#   scripts/build-mac-app.sh [--release] [--open]
# A real bundle (not `swift run`) so macOS gives it a stable identity for the Accessibility
# grant, a Dock icon, and App Nap settings from Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

config=debug
open_after=0
for arg in "$@"; do
  case "$arg" in
    --release) config=release ;;
    --open) open_after=1 ;;
  esac
done

swift build -c "$config" --product ZenModeMac
bin_dir="$(swift build -c "$config" --show-bin-path)"
bin="$bin_dir/ZenModeMac"

app="build/ZenMode OS.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/ZenModeMac"
cp scripts/Info.plist "$app/Contents/Info.plist"
# SwiftPM resource bundles (ZenVoice's voice assets, the SDKs'): Bundle.module looks in
# Contents/Resources first, and a bundle it can't find stops the app.
for b in "$bin_dir"/*.bundle; do
  [[ -d "$b" ]] && cp -R "$b" "$app/Contents/Resources/"
done
# TODO(imagery): app icon (AppIcon.icns from the mark, Albeit light) once the art is generated.
# Ad-hoc signature: enough for a local run and for TCC to remember the Accessibility grant.
codesign --force --sign - "$app" >/dev/null

echo "Built $app"
if [[ $open_after == 1 ]]; then
  pkill -x ZenModeMac 2>/dev/null || true
  open "$app"
fi
