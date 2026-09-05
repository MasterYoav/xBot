#!/usr/bin/env bash
# Inject Sparkle Info.plist keys from environment (CI release builds).
#
# Both must be set to activate in-app update checks:
#   XBOT_APPCAST_URL          HTTPS appcast feed URL
#   XBOT_SPARKLE_PUBLIC_KEY   EdDSA public key (base64)
#
# Usage:
#   scripts/inject-sparkle-plist.sh path/to/Info.plist
set -euo pipefail

PLIST="${1:?Usage: inject-sparkle-plist.sh <Info.plist>}"

if [[ -z "${XBOT_APPCAST_URL:-}" || -z "${XBOT_SPARKLE_PUBLIC_KEY:-}" ]]; then
  echo "Sparkle plist keys not set — Sparkle stays inert." >&2
  exit 0
fi

set_plist() {
  local key="$1"
  local type="$2"
  local value="$3"
  if /usr/libexec/PlistBuddy -c "Print :${key}" "${PLIST}" &>/dev/null; then
    /usr/libexec/PlistBuddy -c "Set :${key} ${type} ${value}" "${PLIST}"
  else
    /usr/libexec/PlistBuddy -c "Add :${key} ${type} ${value}" "${PLIST}"
  fi
}

set_plist SUFeedURL string "${XBOT_APPCAST_URL}"
set_plist SUPublicEDKey string "${XBOT_SPARKLE_PUBLIC_KEY}"
set_plist SUEnableAutomaticChecks bool true
set_plist SUAutomaticallyUpdate bool false

echo "Injected Sparkle keys into ${PLIST}"
