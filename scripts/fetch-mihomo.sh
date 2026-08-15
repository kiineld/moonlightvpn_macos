#!/usr/bin/env bash
# Download the mihomo core for both macOS architectures and lipo them into the
# single universal binary the app bundles.
#
# The core is large and is not committed; CI and a fresh clone both run this.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${MIHOMO_VERSION:-v1.19.29}"
DEST=Resources/mihomo
mkdir -p "$DEST"

if [ -f "$DEST/mihomo" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "mihomo already present — FORCE=1 to refetch"
  "$DEST/mihomo" -v | head -1 || true
  exit 0
fi

base="https://github.com/MetaCubeX/mihomo/releases/download/$VERSION"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for arch in amd64 arm64; do
  echo "  mihomo-darwin-$arch-$VERSION"
  curl -fsSL "$base/mihomo-darwin-$arch-$VERSION.gz" -o "$tmp/$arch.gz"
  gunzip -c "$tmp/$arch.gz" > "$tmp/mihomo-$arch"
  chmod +x "$tmp/mihomo-$arch"
done

# One universal binary rather than two bundles: the app itself is universal, and
# a per-arch core would mean the Intel build shipping an unusable arm64 core.
lipo -create -output "$DEST/mihomo" "$tmp/mihomo-amd64" "$tmp/mihomo-arm64"
chmod +x "$DEST/mihomo"

echo "$VERSION" > "$DEST/VERSION"
lipo -info "$DEST/mihomo"
