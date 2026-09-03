#!/usr/bin/env bash
# Create a release .dmg from a bundled XBot.app (M7 stub).
#
# Usage:
#   scripts/generate-app-icon.sh
#   cd apps/mac && swift build -c release
#   scripts/bundle-mac-app.sh
#   scripts/create-dmg.sh
#
# Signing and notarization are manual until CI credentials exist — see docs/11-packaging-and-updates.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${ROOT}/apps/mac/XBot.app"
DMG="${ROOT}/dist/xBot.dmg"
VOLUME="xBot"
STAGE="${ROOT}/dist/dmg-stage"

if [[ ! -d "${APP}" ]]; then
  echo "Bundle the app first: scripts/bundle-mac-app.sh" >&2
  exit 1
fi

mkdir -p "${ROOT}/dist"
rm -rf "${STAGE}" "${DMG}"
mkdir -p "${STAGE}"

cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

hdiutil create -volname "${VOLUME}" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}"
rm -rf "${STAGE}"

echo "Created ${DMG}"
echo "Sign with: codesign --force --deep --options runtime --sign \"Developer ID Application: …\" \"${APP}\""
