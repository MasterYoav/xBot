#!/usr/bin/env bash
# Wrap the SwiftPM-built XBot binary in a signed-ready .app bundle with the official icon.
#
# Usage:
#   scripts/generate-app-icon.sh
#   cd apps/mac && swift build -c release
#   scripts/bundle-mac-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAC="${ROOT}/apps/mac"
BUILD="${MAC}/.build/release/XBot"
RES="${MAC}/Sources/XBotApp/Resources"
APP="${MAC}/XBot.app"

if [[ ! -x "${BUILD}" ]]; then
  echo "Build the release binary first: cd apps/mac && swift build -c release" >&2
  exit 1
fi

if [[ ! -f "${RES}/Assets.car" || ! -f "${RES}/xBot.icns" ]]; then
  "${ROOT}/scripts/generate-app-icon.sh"
fi

rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${BUILD}" "${APP}/Contents/MacOS/XBot"
cp "${RES}/Assets.car" "${APP}/Contents/Resources/Assets.car"
cp "${RES}/xBot.icns" "${APP}/Contents/Resources/xBot.icns"
cp "${MAC}/Resources/Info.plist" "${APP}/Contents/Info.plist"
"${ROOT}/scripts/inject-sparkle-plist.sh" "${APP}/Contents/Info.plist"

chmod +x "${APP}/Contents/MacOS/XBot"

# Sparkle ships as an embedded framework when linked through SwiftPM.
SPARKLE_FW="$(find "${MAC}/.build" -path '*/Sparkle.framework' -type d 2>/dev/null | head -1)"
if [[ -n "${SPARKLE_FW}" ]]; then
  mkdir -p "${APP}/Contents/Frameworks"
  rsync -a "${SPARKLE_FW}" "${APP}/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "${APP}/Contents/MacOS/XBot" 2>/dev/null \
    || true
fi

echo "Bundled ${APP}"
echo "Open with: open ${APP}"
