#!/bin/bash
# Builds Kill9.app into ./build — requires macOS 13+ and Xcode Command Line Tools.
# ./build-app.sh --dmg also packages build/Kill9.dmg (needs uv: https://docs.astral.sh/uv/).
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
cp assets/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"

echo "▸ Ad-hoc signing"
codesign --force --deep --sign - "$OUT"

if [[ "${1:-}" == "--dmg" ]]; then
  DMG="build/$APP.dmg"
  echo "▸ Creating $DMG"
  rm -f "$DMG"
  uvx dmgbuild -s assets/dmg-settings.py -D app="$OUT" -D assets="$PWD/assets" "$APP" "$DMG"
  echo "✓ Done: $DMG"
fi

echo "✓ Done: $OUT"
echo "  Run it:      open $OUT"
echo "  Install it:  cp -R $OUT /Applications/"
