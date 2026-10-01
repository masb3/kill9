#!/bin/bash
# Builds Kill9.app into ./build — requires macOS 13+ and Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="Kill9"
OUT="build/$APP.app"

echo "▸ Compiling (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP"

echo "▸ Assembling $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP"
cp Info.plist "$OUT/Contents/Info.plist"

echo "▸ Ad-hoc signing"
codesign --force --deep --sign - "$OUT"

echo "✓ Done: $OUT"
echo "  Run it:      open $OUT"
echo "  Install it:  cp -R $OUT /Applications/"
