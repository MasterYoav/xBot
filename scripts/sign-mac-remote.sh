#!/usr/bin/env bash
# Signs a locally built XBot.app so it can use iCloud (the iPhone/iPad remote's away lane).
#
# iCloud and push are restricted entitlements: they need a provisioning profile for dev.xbot.app.
# Xcode's automatic signing makes one through the XBotMacSigning helper target in
# apps/ios/project.yml; this script builds that target, embeds its profile, and signs XBot.app
# with the same identity and entitlements. Development signing: the app runs on this team's Macs.
# (A Developer ID release needs a Developer ID profile with iCloud; see docs.)
#
#   scripts/sign-mac-remote.sh [path/to/XBot.app]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-${ROOT}/apps/mac/XBot.app}"
DD="${XBOT_SIGN_DERIVED_DATA:-${HOME}/.hermes/cache/scratch/dd-sign}"

[[ -d "${APP}" ]] || { echo "Bundle the app first: scripts/bundle-mac-app.sh" >&2; exit 1; }

( cd "${ROOT}/apps/ios" && xcodegen generate >/dev/null )
xcodebuild -project "${ROOT}/apps/ios/XBotMobile.xcodeproj" -scheme XBotMacSigning -destination 'platform=macOS' \
  -derivedDataPath "${DD}" -allowProvisioningUpdates build >/dev/null
HELPER="${DD}/Build/Products/Debug/XBotMacSigning.app"
PROFILE="${HELPER}/Contents/embedded.provisionprofile"
[[ -f "${PROFILE}" ]] || { echo "No provisioning profile came out of the helper build." >&2; exit 1; }

# The identity the helper was signed with.
IDENTITY="$(codesign -dvv "${HELPER}" 2>&1 | sed -n 's/^Authority=\(Apple Development.*\)$/\1/p' | head -1)"
[[ -n "${IDENTITY}" ]] || { echo "Couldn't tell which identity signed the helper." >&2; exit 1; }

ENTITLEMENTS="$(mktemp -t xbot-entitlements).plist"
codesign -d --entitlements :- "${HELPER}" 2>/dev/null > "${ENTITLEMENTS}"
/usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "${ENTITLEMENTS}" 2>/dev/null || true

cp "${PROFILE}" "${APP}/Contents/embedded.provisionprofile"
if [[ -d "${APP}/Contents/Frameworks" ]]; then
  find "${APP}/Contents/Frameworks" -depth \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' \) -print0 \
    | while IFS= read -r -d '' nested; do
        codesign --force --options runtime --timestamp=none --sign "${IDENTITY}" "${nested}"
      done
fi
codesign --force --options runtime --timestamp=none --entitlements "${ENTITLEMENTS}" --sign "${IDENTITY}" "${APP}"
codesign --verify --strict "${APP}"
rm -f "${ENTITLEMENTS}"
echo "Signed ${APP} for iCloud with ${IDENTITY}"
