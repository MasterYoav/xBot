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

if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" ]]; then
  echo "Notarization credentials not set — the app is signed but not notarized." >&2
  # Still rebuild the DMG, so what ships contains the signed app rather than the unsigned one.
  "${ROOT}/scripts/create-dmg.sh" >/dev/null
  exit 0
fi

# Notarize the app itself, via a zip, so the ticket can be stapled to the bundle.
#
# Stapling the DMG alone is not enough: the person drags the app out of it, and an unstapled app
# fails to open on a machine that is offline at first launch — docs/11-packaging-and-updates.md.
# A ticket only exists once the thing has been notarized, so the app is notarized before the DMG
# is built rather than after.
ZIP="$(mktemp -d)/XBot.zip"
ditto -c -k --keepParent "${APP}" "${ZIP}"
xcrun notarytool submit "${ZIP}" --wait \
  --apple-id "${APPLE_ID}" \
  --team-id "${APPLE_TEAM_ID}" \
  --password "${APPLE_APP_PASSWORD}"
xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"

# Only now is the DMG built, so it carries a signed and stapled app.
#
# It used to be created before any of this and never rebuilt, so the shipped disk image contained an
# unsigned app while the signature went on the wrapper around it. Gatekeeper checks the app, so that
# ships the exact dialog docs/11 says stops a non-technical person permanently.
"${ROOT}/scripts/create-dmg.sh" >/dev/null

codesign --force --timestamp --sign "${MACOS_SIGNING_IDENTITY}" "${DMG}"
xcrun notarytool submit "${DMG}" --wait \
  --apple-id "${APPLE_ID}" \
  --team-id "${APPLE_TEAM_ID}" \
  --password "${APPLE_APP_PASSWORD}"
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}"

# What a clean machine will check. Failing here is the whole point of checking here.
spctl --assess --type execute --verbose "${APP}"

echo "Signed, notarized and stapled ${APP} and ${DMG}"
