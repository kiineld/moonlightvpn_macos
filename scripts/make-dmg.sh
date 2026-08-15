#!/usr/bin/env bash
# Package build/Moonlight.app into a drag-to-install DMG.
#
#   ARCH=universal VERSION=1.0.0 scripts/make-dmg.sh
#
# Produces build/Moonlight-<version>-<arch>.dmg.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Moonlight.app
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 1.0.0)}"
ARCH="${ARCH:-universal}"
# No version in the filename, so `releases/latest/download/Moonlight-<arch>.dmg`
# keeps working across releases. The version is in the release title and in the
# bundle's Info.plist.
NAME="Moonlight-$ARCH"
DMG="build/$NAME.dmg"

[ -d "$APP" ] || { echo "no $APP — run scripts/build-app.sh first" >&2; exit 1; }

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

cp -R "$APP" "$staging/Moonlight.app"
# The Applications symlink is what makes the window a drag-to-install target.
ln -s /Applications "$staging/Applications"

rm -f "$DMG"
hdiutil create \
  -volname "Moonlight" \
  -srcfolder "$staging" \
  -ov -format UDZO \
  -fs HFS+ \
  "$DMG" >/dev/null

echo "▸ $DMG ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
