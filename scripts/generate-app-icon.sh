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

# The alternate app icons (Settings › Appearance › App icon). Each is the same pack with one colour
# layer shown and the rest hidden, so xBot.icon stays the only source of every icon.
# name:layer image — must match Appearance.AppIcon in XBotCore.
VARIANTS_OUT="${OUT_UI}/AppIcons"
rm -rf "${VARIANTS_OUT}"
mkdir -p "${VARIANTS_OUT}"
for variant in "ink:Image 2.png" "rose:Image 3.png" "sunset:Image 4.png" "plum:Image 5.png"; do
  name="${variant%%:*}"
  layer="${variant#*:}"
  work="${STAGING}/variant-${name}"
  mkdir -p "${work}/out"
  cp -R "${ICON}" "${work}/xBot.icon"
  /usr/bin/python3 - "${work}/xBot.icon/icon.json" "${layer}" <<'PY'
import json, sys
path, layer = sys.argv[1], sys.argv[2]
icon = json.load(open(path))
layers = [l for g in icon["groups"] for l in g["layers"]]
if not any(l["image-name"] == layer for l in layers):
    sys.exit(f"xBot.icon has no layer named {layer!r}")
for l in layers:
    l["hidden"] = l["image-name"] != layer
json.dump(icon, open(path, "w"), indent=2)
PY
  actool "${work}/xBot.icon" --compile "${work}/out" --app-icon xBot \
    --output-partial-info-plist "${work}/out/info.plist" --platform macosx --target-device mac \
    --minimum-deployment-target 14.0 --include-all-app-icons >/dev/null
  cp "${work}/out/xBot.icns" "${VARIANTS_OUT}/${name}.icns"
done

# Drop legacy PNG raster fallbacks if they exist.
rm -f "${OUT_APP}/AppIcon.png" "${OUT_APP}/AppIcon.icns" "${OUT_UI}/AppIcon.png"

echo "Compiled xBot.icon → Assets.car + xBot.icns (XBotApp and XBotUI resources)."
