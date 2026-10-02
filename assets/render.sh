#!/bin/bash
# Regenerates AppIcon.icns and the DMG background from the sources in this folder.
# Needs Google Chrome (for rendering) and macOS's sips, iconutil and tiffutil.
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
shot() { "$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 "$@" 2>/dev/null; }

echo "▸ App icon"
printf '<!doctype html><body style="margin:0">%s' "$(cat icon.svg)" > "$TMP/icon.html"
shot --window-size=1024,1024 --screenshot="$TMP/icon.png" "file://$TMP/icon.html"
ICONSET="$TMP/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$TMP/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$TMP/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o AppIcon.icns

echo "▸ DMG background"
shot --window-size=660,400 --screenshot="$TMP/bg.png" "file://$PWD/dmg-background.html"
shot --window-size=660,400 --force-device-scale-factor=2 --screenshot="$TMP/bg@2x.png" "file://$PWD/dmg-background.html"
tiffutil -cathidpicheck "$TMP/bg.png" "$TMP/bg@2x.png" -out dmg-background.tiff >/dev/null

echo "✓ Done: AppIcon.icns, dmg-background.tiff"
