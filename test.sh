#!/bin/bash
set -euo pipefail
KEYNAP_ROOT="$(cd "$(dirname "$0")" && pwd)"
KEYNAP_BUILD="${KEYNAP_BUILD_DIR:-$KEYNAP_ROOT/.build.noindex}"
mkdir -p "$KEYNAP_BUILD/tests"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx26.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -framework AppKit -framework SwiftUI -framework ApplicationServices -framework Carbon \
  "$KEYNAP_ROOT"/Sources/*.swift -o "$KEYNAP_BUILD/tests/KeyNapTests"
# This mode constructs synthetic events without posting them or installing a tap.
"$KEYNAP_BUILD/tests/KeyNapTests" --self-test
