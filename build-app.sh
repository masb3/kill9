#!/bin/bash
# Builds a universal (Apple Silicon + Intel) Kill9.app into ./build — requires macOS 13+ and Xcode Command Line Tools.
# ./build-app.sh --dmg also packages build/Kill9.dmg (needs uv: https://docs.astral.sh/uv/).
#
# Signing is ad-hoc unless SIGN_IDENTITY is set, e.g. "Developer ID Application: Name (TEAMID)".
# With --dmg, notarization runs when NOTARY_KEY (path to an App Store Connect .p8),
# NOTARY_KEY_ID and NOTARY_ISSUER are also set.
set -euo pipefail
cd "$(dirname "$0")"

APP="Kill9"
OUT="build/$APP.app"

# One build per arch, then lipo: multi-arch `swift build --arch a --arch b` needs full Xcode.
BINS=()
for ARCH in arm64 x86_64; do
  echo "▸ Compiling (release, $ARCH)…"
  swift build -c release --triple "$ARCH-apple-macosx13.0"
  BINS+=("$(swift build -c release --triple "$ARCH-apple-macosx13.0" --show-bin-path)/$APP")
done

echo "▸ Assembling $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
lipo -create "${BINS[@]}" -output "$OUT/Contents/MacOS/$APP"
cp Info.plist "$OUT/Contents/Info.plist"
cp assets/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "▸ Signing with $SIGN_IDENTITY (hardened runtime)"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$OUT"
else
  echo "▸ Ad-hoc signing"
  codesign --force --sign - "$OUT"
fi

if [[ "${1:-}" == "--dmg" ]]; then
  DMG="build/$APP.dmg"
  echo "▸ Creating $DMG"
  rm -f "$DMG"
  uvx dmgbuild -s assets/dmg-settings.py -D app="$OUT" -D assets="$PWD/assets" "$APP" "$DMG"

  if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    if [[ -n "${NOTARY_KEY:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
      echo "▸ Notarizing $DMG (this can take a few minutes)"
      xcrun notarytool submit "$DMG" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
      # The ticket covers the app inside the DMG too, so both can be stapled.
      xcrun stapler staple "$DMG"
      xcrun stapler staple "$OUT"
    fi
  fi
  echo "✓ Done: $DMG"
fi

echo "✓ Done: $OUT"
echo "  Run it:      open $OUT"
echo "  Install it:  cp -R $OUT /Applications/"
