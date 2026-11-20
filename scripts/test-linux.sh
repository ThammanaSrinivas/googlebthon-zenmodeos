#!/bin/sh
# Builds and tests the shared package (Packages/ZenShared: no SwiftUI, no AppKit needed): what CI
# runs on Linux. The root package is the SwiftUI Mac app and builds on macOS only.
#   scripts/test-linux.sh                          # every ZenShared test
#   scripts/test-linux.sh --filter ZenLogicTests   # one target or suite
set -eu
cd "$(dirname "$0")/../Packages/ZenShared"

# A toolchain unpacked in the home folder, if `swift` isn't on PATH already.
if ! command -v swift >/dev/null 2>&1 && [ -x "$HOME/.local/share/swift/6.4.1/usr/bin/swift" ]; then
    PATH="$HOME/.local/share/swift/6.4.1/usr/bin:$PATH"
    export PATH
fi

swift --version
swift build --build-tests
swift test --skip-build "$@"
