#!/usr/bin/env bash
# Package build/Moonlight.app into a drag-to-install DMG.
#
#   ARCH=universal VERSION=1.0.0 scripts/make-dmg.sh
#
# Produces build/Moonlight-<arch>.dmg — no version in the name, so
# releases/latest/download/Moonlight-universal.dmg keeps working.
#
# The styled window — background, icon positions, no toolbar — lives in the
# volume's .DS_Store, and Finder is what writes that. So the image is built
# read-write, dressed through AppleScript, then flattened to a compressed
# read-only one. `appdmg` would do this without Finder, but its native
# dependency no longer builds on current Node.
#
# If Finder is unreachable (no GUI session) the image is still produced, plain
# but with the Applications symlink, so it installs by dragging either way.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Moonlight.app
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 1.0.0)}"
ARCH="${ARCH:-universal}"
DMG="build/Moonlight-$ARCH.dmg"
VOLUME="Moonlight $VERSION"

[ -d "$APP" ] || { echo "no $APP — run scripts/build-app.sh first" >&2; exit 1; }
rm -f "$DMG"

swift scripts/make-dmg-background.swift build/dmg-background.png >/dev/null

# dmgbuild writes the volume's .DS_Store directly, in pure Python. The usual
# alternative is driving Finder through AppleScript, which needs a GUI session —
# a CI runner has none, and every image it built came out unstyled. `appdmg`
# would also work headlessly, but its native dependency no longer builds on
# current Node.
if python3 -c "import dmgbuild" >/dev/null 2>&1; then
  python3 -m dmgbuild \
    -s scripts/dmg-settings.py \
    -D app="$(pwd)/$APP" \
    -D icon="$(pwd)/$APP/Contents/Resources/AppIcon.icns" \
    -D background="$(pwd)/build/dmg-background.png" \
    "$VOLUME" "$DMG" >/dev/null
  echo "▸ $DMG ($(du -h "$DMG" | cut -f1)) styled"
  shasum -a 256 "$DMG" | tee "$DMG.sha256"
  exit 0
fi

echo "  (dmgbuild unavailable — building a plain image)" >&2
staging=$(mktemp -d)
mount=""
cleanup() {
  [ -n "$mount" ] && hdiutil detach "$mount" -force >/dev/null 2>&1 || true
  rm -rf "$staging" build/rw.dmg
}
trap cleanup EXIT

swift scripts/make-dmg-background.swift build/dmg-background.png >/dev/null

cp -R "$APP" "$staging/Moonlight.app"
ln -s /Applications "$staging/Applications"
mkdir -p "$staging/.background"
cp build/dmg-background.png "$staging/.background/background.png"

# Room for the copy plus the .DS_Store Finder is about to write.
size=$(( $(du -sm "$staging" | cut -f1) + 60 ))
hdiutil create -volname "$VOLUME" -srcfolder "$staging" -ov \
  -format UDRW -fs HFS+ -size "${size}m" build/rw.dmg >/dev/null

mount=$(mktemp -d)
hdiutil attach build/rw.dmg -nobrowse -noautoopen -mountpoint "$mount" >/dev/null

sync
hdiutil detach "$mount" -force >/dev/null
mount=""

hdiutil convert build/rw.dmg -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null

echo "▸ $DMG ($(du -h "$DMG" | cut -f1)) plain"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
