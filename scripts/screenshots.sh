#!/usr/bin/env bash
# Capture one PNG per screen into docs/screenshots/.
#
# The app cannot be driven by clicks without accessibility permission, so each
# screen is opened directly with the ML_PAGE environment variable that RootView
# reads. Needs a built bundle: scripts/build-app.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Moonlight.app
OUT=docs/screenshots
[ -d "$APP" ] || { echo "run scripts/build-app.sh first" >&2; exit 1; }
mkdir -p "$OUT"

# screencapture needs a window id, and there is no shell tool that gives one.
cat > /tmp/moonlight-winid.swift <<'SWIFT'
import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
// The app also owns unnamed auxiliary windows — one of them is a 500×500 blank
// that is easy to capture by mistake. The document window is the one carrying
// the app's own title.
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Moonlight"
    && (w[kCGWindowName as String] as? String) == "Moonlight" {
    let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    if (bounds["Height"] as? Double ?? 0) > 200 {
        print(w[kCGWindowNumber as String] as? Int ?? -1)
        break
    }
}
SWIFT
swiftc -O /tmp/moonlight-winid.swift -o /tmp/moonlight-winid

for page in connect sub apps settings import; do
  pkill -f "Moonlight.app/Contents/MacOS/Moonlight" 2>/dev/null || true
  sleep 1
  ML_PAGE="$page" "$APP/Contents/MacOS/Moonlight" >/dev/null 2>&1 &
  sleep 9
  id=$(/tmp/moonlight-winid)
  [ -n "$id" ] || { echo "! no window for $page" >&2; continue; }
  screencapture -x -o -l "$id" "$OUT/$page.png"
  sips -Z 1400 "$OUT/$page.png" --out "$OUT/$page.png" >/dev/null
  echo "  $OUT/$page.png"
done
pkill -f "Moonlight.app/Contents/MacOS/Moonlight" 2>/dev/null || true
