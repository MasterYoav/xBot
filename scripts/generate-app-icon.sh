#!/usr/bin/env bash
# Compile the official xBot.icon (Icon Composer) into Assets.car + xBot.icns via actool.
#
# Do not rasterise the embedded PNG — actool renders the layered icon correctly for
# macOS 26 Liquid Glass (Assets.car) and older releases (xBot.icns).
#
# Usage: scripts/generate-app-icon.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON="${ROOT}/xBot.icon"
OUT_APP="${ROOT}/apps/mac/Sources/XBotApp/Resources"
OUT_UI="${ROOT}/apps/mac/Sources/XBotUI/Resources"
STAGING="$(mktemp -d)"

cleanup() { rm -rf "${STAGING}"; }
trap cleanup EXIT

if [[ ! -d "${ICON}" ]]; then
  echo "Missing ${ICON} — add the official Icon Composer bundle at the repo root." >&2
  exit 1
fi

mkdir -p "${OUT_APP}" "${OUT_UI}"

actool "${ICON}" \
  --compile "${STAGING}" \
  --app-icon xBot \
  --output-partial-info-plist "${STAGING}/icon-info.plist" \
  --platform macosx \
  --target-device mac \
  --minimum-deployment-target 14.0 \
  --include-all-app-icons

for artifact in Assets.car xBot.icns; do
  if [[ ! -f "${STAGING}/${artifact}" ]]; then
    echo "actool did not produce ${artifact}" >&2
    exit 1
  fi
done

cp "${STAGING}/Assets.car" "${OUT_APP}/Assets.car"
cp "${STAGING}/xBot.icns" "${OUT_APP}/xBot.icns"
cp "${STAGING}/xBot.icns" "${OUT_UI}/xBot.icns"

# Drop legacy PNG raster fallbacks if they exist.
rm -f "${OUT_APP}/AppIcon.png" "${OUT_APP}/AppIcon.icns" "${OUT_UI}/AppIcon.png"

echo "Compiled xBot.icon → Assets.car + xBot.icns (XBotApp and XBotUI resources)."
