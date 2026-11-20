#!/usr/bin/env bash
# Renders every onboarding step and Today to PNG (debug build), for review without Screen Recording.
#   scripts/snapshot-tour.sh <out-dir> [step ...]
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:?usage: snapshot-tour.sh <out-dir> [step ...]}"; shift || true
steps=("$@")
[[ ${#steps[@]} -eq 0 ]] && steps=(story0 story1 story2 seat campus uses quiet count bring handoff today)
mkdir -p "$out"
scripts/build-mac-app.sh >/dev/null
bin="build/ZenMode OS.app/Contents/MacOS/ZenModeMac"
pkill -x ZenModeMac 2>/dev/null || true
for s in "${steps[@]}"; do
  wait_for=3.4
  [[ $s == story2 ]] && wait_for=5.5
  "$bin" --step "$s" --shot "$out/$s" --wait "$wait_for" >/dev/null 2>&1 || true
  echo "$out/$s.png"
done
