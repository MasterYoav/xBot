#!/usr/bin/env bash
# Generate a Sparkle appcast from a signed release DMG.
#
# Requires one of:
#   SPARKLE_EDDSA_PRIVATE_KEY       EdDSA private key (written to a temp file)
#   SPARKLE_EDDSA_PRIVATE_KEY_FILE  Path to the private key file
#
# Optional:
#   XBOT_RELEASE_DOWNLOAD_PREFIX    Prefix for enclosure URLs in the appcast
#
# Usage:
#   scripts/bundle-mac-app.sh
#   scripts/create-dmg.sh
#   scripts/sign-mac-app.sh          # when credentials exist
#   scripts/generate-appcast.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAC="${ROOT}/apps/mac"
PLIST="${MAC}/XBot.app/Contents/Info.plist"
DMG="${ROOT}/dist/xBot.dmg"
RELEASES="${ROOT}/dist/releases"

if [[ ! -f "${DMG}" ]]; then
  echo "Create a DMG first: scripts/create-dmg.sh" >&2
  exit 1
fi

if [[ ! -f "${PLIST}" ]]; then
  echo "Bundle the app first: scripts/bundle-mac-app.sh" >&2
  exit 1
fi

if [[ -z "${SPARKLE_EDDSA_PRIVATE_KEY:-}" && -z "${SPARKLE_EDDSA_PRIVATE_KEY_FILE:-}" ]]; then
  echo "SPARKLE_EDDSA_PRIVATE_KEY not set — skipping appcast generation." >&2
  exit 0
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST}")"
ARCHIVE="${RELEASES}/xBot ${VERSION}.dmg"

mkdir -p "${RELEASES}"
cp "${DMG}" "${ARCHIVE}"

GENERATE_APPCAST="$(find "${MAC}/.build/artifacts/sparkle" -name generate_appcast -type f 2>/dev/null | head -1)"
if [[ -z "${GENERATE_APPCAST}" ]]; then
  echo "Sparkle generate_appcast not found — run: cd apps/mac && swift build -c release" >&2
  exit 1
fi

ARGS=()
if [[ -n "${SPARKLE_EDDSA_PRIVATE_KEY_FILE:-}" ]]; then
  ARGS+=(--ed-key-file "${SPARKLE_EDDSA_PRIVATE_KEY_FILE}")
else
  KEYFILE="$(mktemp)"
  trap 'rm -f "${KEYFILE}"' EXIT
  printf '%s' "${SPARKLE_EDDSA_PRIVATE_KEY}" > "${KEYFILE}"
  ARGS+=(--ed-key-file "${KEYFILE}")
fi

if [[ -n "${XBOT_RELEASE_DOWNLOAD_PREFIX:-}" ]]; then
  ARGS+=(--download-url-prefix "${XBOT_RELEASE_DOWNLOAD_PREFIX}")
fi

"${GENERATE_APPCAST}" "${ARGS[@]}" "${RELEASES}"

echo "Appcast at ${RELEASES}/appcast.xml"
echo "Release archive at ${ARCHIVE}"
