#!/usr/bin/env bash
# Wrap the SwiftPM-built XBot binary in a signed-ready .app bundle with the official icon.
#
# Usage:
#   scripts/generate-app-icon.sh
#   cd apps/mac && swift build -c release --arch arm64
#   scripts/bundle-mac-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAC="${ROOT}/apps/mac"
BUILD="$(cd "${MAC}" && swift build -c release --arch arm64 --show-bin-path)/XBot"
RES="${MAC}/Sources/XBotApp/Resources"
APP="${MAC}/XBot.app"

if [[ ! -x "${BUILD}" ]]; then
  echo "Build the release binary first: cd apps/mac && swift build -c release --arch arm64" >&2
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

# The version always comes from here, never from the committed plist. XBOT_VERSION wins (the release
# workflow passes the one it is publishing; a local install can say 2.0.0-dev); otherwise the VERSION
# file at the repository root, which is what a release is cut from. Sparkle compares
# CFBundleVersion, so that has to rise with every release, and the committed plist's "1" never would.
VERSION="${XBOT_VERSION:-}"
if [[ -z "${VERSION}" && -f "${ROOT}/VERSION" ]]; then
  # tr, not just $(<…): a trailing newline or a stray space would end up in the plist.
  VERSION="$(tr -d '[:space:]' < "${ROOT}/VERSION")"
fi
VERSION="${VERSION:-2.0.0-dev}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP}/Contents/Info.plist"
if [[ -n "${XBOT_BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${XBOT_BUILD_NUMBER}" "${APP}/Contents/Info.plist"
fi

chmod +x "${APP}/Contents/MacOS/XBot"

# SwiftPM's per-target resource bundles. `Bundle.module` traps when its bundle is missing, so an app
# without them dies at launch on the first view that loads a resource.
for bundle in "$(dirname "${BUILD}")"/*.bundle; do
  [[ -d "${bundle}" ]] && rsync -a "${bundle}" "${APP}/Contents/Resources/"
done

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
