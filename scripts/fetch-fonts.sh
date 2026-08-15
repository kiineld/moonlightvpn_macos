#!/usr/bin/env bash
# Fetch Onest and Unbounded as variable TTFs.
#
# The design ships woff2, which Core Text cannot register, so the TTFs come from
# Google Fonts — the same faces the design's @font-face rules point at.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST=Resources/fonts
mkdir -p "$DEST"

fetch() {
  local name="$1" url="$2"
  if [ -s "$DEST/$name" ] && [ "${FORCE:-0}" != "1" ]; then return; fi
  echo "  $name"
  curl -fsSL "$url" -o "$DEST/$name"
  # A 404 page is a valid file as far as curl is concerned; TTFs start with
  # 0x00010000 or "true"/"OTTO", so anything else is not a font.
  if [ "$(head -c 4 "$DEST/$name" | xxd -p)" != "00010000" ]; then
    rm -f "$DEST/$name"
    echo "  ! $name is not a TrueType file" >&2
    exit 1
  fi
}

base=https://raw.githubusercontent.com/google/fonts/main/ofl
fetch "Onest.ttf"     "$base/onest/Onest%5Bwght%5D.ttf"
fetch "Unbounded.ttf" "$base/unbounded/Unbounded%5Bwght%5D.ttf"

ls -la "$DEST"
