#!/usr/bin/env bash
# Fetch the lucide 0.468.0 SVGs that scripts/gen-icons.py turns into
# Sources/MoonlightDesign/Icons.swift. The generated Swift is committed, so this
# only has to run when the icon set changes.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=0.468.0
DEST=vendor/lucide
mkdir -p "$DEST"

ICONS=$(python3 - <<'PY'
import re, pathlib
src = pathlib.Path("scripts/gen-icons.py").read_text()
block = re.search(r"NAMES = \{(.*?)\n\}", src, re.S).group(1)
print(" ".join(sorted(set(re.findall(r'"([a-z0-9-]+)":', block)))))
PY
)

for icon in $ICONS; do
  if [ ! -f "$DEST/$icon.svg" ]; then
    echo "  $icon"
    curl -fsSL "https://unpkg.com/lucide-static@$VERSION/icons/$icon.svg" -o "$DEST/$icon.svg"
  fi
done

echo "lucide $VERSION -> $DEST"
