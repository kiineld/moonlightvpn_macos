#!/usr/bin/env bash
# Render the design's logo tile into an .icns at every size macOS asks for.
#
# The source is assets/logo-tile.svg from the design project, inlined here so the
# build needs no SVG toolchain — sips and iconutil ship with macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-Resources/AppIcon.icns}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The tile is inset to Apple's 824-in-1024 grid for rounded-rect icons, so it
# sits at the same visual weight as every other app in the Dock. Drawn at the
# full canvas it looked a size larger than its neighbours.
cat > "$tmp/icon.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <g transform="translate(100 100) scale(18.727)">
    <rect width="44" height="44" rx="13" fill="#D2FF1F"/>
    <path d="M30 22a8.4 8.4 0 1 1-9.4-8.34A10 10 0 0 0 30 22Z" fill="#101828"/>
    <circle cx="30.5" cy="12.5" r="1.7" fill="#101828"/>
    <circle cx="25" cy="8" r="1.1" fill="#101828"/>
  </g>
</svg>
SVG

# sips reads SVG on macOS 13+; qlmanage is the fallback on anything older.
if ! sips -s format png "$tmp/icon.svg" --out "$tmp/1024.png" >/dev/null 2>&1; then
  qlmanage -t -s 1024 -o "$tmp" "$tmp/icon.svg" >/dev/null 2>&1
  mv "$tmp"/icon.svg.png "$tmp/1024.png"
fi

mkdir -p "$tmp/AppIcon.iconset"
for size in 16 32 64 128 256 512; do
  sips -z $size $size "$tmp/1024.png" --out "$tmp/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$tmp/1024.png" \
    --out "$tmp/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
cp "$tmp/1024.png" "$tmp/AppIcon.iconset/icon_512x512@2x.png"

mkdir -p "$(dirname "$OUT")"
iconutil -c icns "$tmp/AppIcon.iconset" -o "$OUT"
echo "▸ $OUT"
