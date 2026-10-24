#!/bin/bash
set -euo pipefail
KEYNAP_ROOT="$(cd "$(dirname "$0")" && pwd)"
KEYNAP_BUILD="${KEYNAP_BUILD_DIR:-$KEYNAP_ROOT/.build.noindex}"
KEYNAP_APP="$KEYNAP_BUILD/output.noindex/KeyNap.app"
: "${KEYNAP_SIGNING_IDENTITY:?Set KEYNAP_SIGNING_IDENTITY to your local Apple signing certificate name or SHA-1.}"
KEYNAP_SIGNING="$KEYNAP_SIGNING_IDENTITY"
if [[ "$KEYNAP_SIGNING" == "-" ]]; then
  printf 'The app build requires an Apple signing identity; use ./test.sh for unsigned offline tests.\n' >&2
  exit 1
fi
mkdir -p "$KEYNAP_APP/Contents/MacOS" "$KEYNAP_APP/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx26.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -framework AppKit -framework SwiftUI -framework ApplicationServices -framework Carbon \
  "$KEYNAP_ROOT"/Sources/*.swift -o "$KEYNAP_APP/Contents/MacOS/KeyNap"
cp "$KEYNAP_ROOT/Resources/Info.plist" "$KEYNAP_APP/Contents/Info.plist"
if [ -f "$KEYNAP_ROOT/Resources/KeyNap.icns" ]; then
  cp "$KEYNAP_ROOT/Resources/KeyNap.icns" "$KEYNAP_APP/Contents/Resources/"
fi
codesign --force --sign "$KEYNAP_SIGNING" --options runtime --timestamp=none "$KEYNAP_APP"
codesign --verify --deep --strict --verbose=2 "$KEYNAP_APP"
codesign --verify --strict '-R=anchor apple generic and identifier "org.keynap.app"' "$KEYNAP_APP"
printf 'Built %s\n' "$KEYNAP_APP"
