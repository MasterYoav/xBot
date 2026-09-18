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
cp "${ROOT}/scripts/uninstall-xbot.command" "${STAGE}/Uninstall xBot.command"
chmod +x "${STAGE}/Uninstall xBot.command"

# Signed like anything else that ships, when there is an identity to sign with.
#
# A .command carries its signature in extended attributes rather than inside the file, and both `cp`
# and the disk image preserve those. Unsigned, it arrives quarantined from a download and macOS
# refuses it as coming from an unidentified developer — which, for the person who already trashed
# the app and wants their volumes back, is a dead end with no second path.
#
# Only when the identity is actually in a keychain, not merely named. In CI this script runs twice:
# once before the certificate is imported (an unsigned DMG, so a run with no secrets still produces
# one) and again from sign-mac-app.sh afterwards. Keyed on the name alone, the first pass failed the
# release with "no identity found".
if [[ -n "${MACOS_SIGNING_IDENTITY:-}" ]] \
  && security find-identity -v -p codesigning | grep -qF "${MACOS_SIGNING_IDENTITY}"; then
  codesign --force --timestamp --sign "${MACOS_SIGNING_IDENTITY}" \
    "${STAGE}/Uninstall xBot.command"
fi

hdiutil create -volname "${VOLUME}" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}"
rm -rf "${STAGE}"

echo "Created ${DMG}"
echo "Sign with: codesign --force --deep --options runtime --sign \"Developer ID Application: …\" \"${APP}\""
