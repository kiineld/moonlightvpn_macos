#!/usr/bin/env bash
# Build Moonlight.app.
#
#   scripts/build-app.sh                 native architecture
#   ARCH=universal scripts/build-app.sh  x86_64 + arm64 in one bundle
#   ARCH=x86_64 scripts/build-app.sh     Intel only
#   ARCH=arm64 scripts/build-app.sh      Apple silicon only
#
# There is no Xcode project. SwiftPM builds the two executables, and this script
# assembles the bundle around them — which is why the whole thing builds with
# the Command Line Tools alone.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH="${ARCH:-native}"
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 1.0.0)}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP="build/Moonlight.app"
CONTENTS="$APP/Contents"

# Deployment endpoints. Overridden by the environment so a fork points these at
# its own bot and channel without touching source.
TELEGRAM_BOT_URL="${TELEGRAM_BOT_URL:-https://t.me/}"
TELEGRAM_CHANNEL_URL="${TELEGRAM_CHANNEL_URL:-https://t.me/}"
SUPPORT_URL="${SUPPORT_URL:-https://t.me/}"
RELEASES_URL="${RELEASES_URL:-https://github.com/kiineld/moonlightvpn_macos/releases/latest}"

scripts/fetch-mihomo.sh
scripts/fetch-fonts.sh

# A *multi*-arch build shells out to xcbuild, which lives inside Xcode.app —
# the Command Line Tools do not have it. Single-arch builds do not need it, so
# only the universal case is gated. Checking a fixed /Library path would be
# wrong: the framework sits next to whichever developer directory is selected.
if [ "$ARCH" = "universal" ] && \
   [ ! -d "$(xcode-select -p)/../SharedFrameworks/XCBuild.framework" ]; then
  echo "! ARCH=universal needs full Xcode (xcode-select -s /Applications/Xcode.app)." >&2
  echo "  Use ARCH=native, ARCH=arm64 or ARCH=x86_64 for a single-slice build." >&2
  exit 1
fi

case "$ARCH" in
  universal) ARCH_FLAGS=(--arch arm64 --arch x86_64) ;;
  native)    ARCH_FLAGS=() ;;
  *)         ARCH_FLAGS=(--arch "$ARCH") ;;
esac

echo "▸ swift build ($ARCH)"
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

echo "▸ assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/fonts"

cp "$BIN_DIR/Moonlight" "$CONTENTS/MacOS/Moonlight"
cp "$BIN_DIR/moonlight-helper" "$CONTENTS/Resources/moonlight-helper"
cp Resources/mihomo/mihomo "$CONTENTS/Resources/mihomo"
cp Resources/fonts/*.ttf "$CONTENTS/Resources/fonts/"
chmod +x "$CONTENTS/MacOS/Moonlight" "$CONTENTS/Resources/moonlight-helper" "$CONTENTS/Resources/mihomo"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Moonlight</string>
    <key>CFBundleDisplayName</key><string>Moonlight</string>
    <key>CFBundleIdentifier</key><string>vpn.moonlight.desktop</string>
    <key>CFBundleExecutable</key><string>Moonlight</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT licensed</string>
    <key>MLTelegramBotURL</key><string>$TELEGRAM_BOT_URL</string>
    <key>MLTelegramChannelURL</key><string>$TELEGRAM_CHANNEL_URL</string>
    <key>MLSupportURL</key><string>$SUPPORT_URL</string>
    <key>MLReleasesURL</key><string>$RELEASES_URL</string>
    <!-- A subscription URL points at whatever host the panel operator runs, and
         self-hosted panels are routinely reached by bare IP with a self-signed
         certificate, or over plain HTTP behind a tunnel. ATS would refuse both.
         SubscriptionClient upgrades a bare host to https://, so cleartext only
         happens when the user types http:// themselves. -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key><true/>
    </dict>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>Moonlight subscription</string>
            <key>CFBundleURLSchemes</key><array><string>moonlight</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
else
  scripts/make-icon.sh "$CONTENTS/Resources/AppIcon.icns"
fi

# An ad-hoc signature is not a Developer ID, but it is what lets the bundle keep
# a stable identity across launches — without it macOS treats every run as a new
# app and re-asks for every permission.
codesign --force --deep --sign - "$APP" 2>/dev/null || \
  echo "  (codesign unavailable — the bundle still runs)"

echo "▸ $APP"
lipo -info "$CONTENTS/MacOS/Moonlight" 2>/dev/null || true
du -sh "$APP"
