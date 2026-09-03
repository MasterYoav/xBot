#!/usr/bin/env bash
# Sign and notarize a bundled XBot.app + DMG when CI secrets are present.
#
# Required environment (see docs/11-packaging-and-updates.md):
#   MACOS_SIGNING_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID                 Apple ID for notarytool
#   APPLE_TEAM_ID            Team ID
#   APPLE_APP_PASSWORD       App-specific password or notary key
#
# Usage:
#   scripts/bundle-mac-app.sh
#   scripts/create-dmg.sh
#   scripts/sign-mac-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${ROOT}/apps/mac/XBot.app"
DMG="${ROOT}/dist/xBot.dmg"

if [[ -z "${MACOS_SIGNING_IDENTITY:-}" ]]; then
  echo "MACOS_SIGNING_IDENTITY is not set — skipping codesign and notarization." >&2
  exit 0
fi

if [[ ! -d "${APP}" ]]; then
  echo "Bundle the app first: scripts/bundle-mac-app.sh" >&2
  exit 1
fi

sign_app() {
  # Sparkle and other embedded frameworks first, then the bundle.
  if [[ -d "${APP}/Contents/Frameworks" ]]; then
    find "${APP}/Contents/Frameworks" -depth -name '*.framework' -print0 \
      | while IFS= read -r -d '' framework; do
          codesign --force --options runtime --timestamp \
            --sign "${MACOS_SIGNING_IDENTITY}" "${framework}"
        done
  fi
  codesign --deep --force --options runtime --timestamp \
    --sign "${MACOS_SIGNING_IDENTITY}" "${APP}"
  codesign --verify --deep --strict --verbose=2 "${APP}"
}

sign_app

if [[ -f "${DMG}" ]]; then
  codesign --force --timestamp --sign "${MACOS_SIGNING_IDENTITY}" "${DMG}"
fi

if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" ]]; then
  echo "Notarization credentials not set — signed locally only." >&2
  exit 0
fi

if [[ -f "${DMG}" ]]; then
  xcrun notarytool submit "${DMG}" --wait \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_PASSWORD}"
  xcrun stapler staple "${DMG}"
fi

xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"

echo "Signed and notarized ${APP}"
