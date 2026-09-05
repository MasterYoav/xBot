#!/usr/bin/env bash
# Build the animated README logo (MP4 + poster PNG) from xBot.icon source art.
#
# Usage: scripts/generate-readme-logo.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="${ROOT}/assets"
ICON_PNG="${ROOT}/xBot.icon/Assets/Untitled blend-4096x4096 2.png"
ICNS="${ROOT}/apps/mac/Sources/XBotApp/Resources/xBot.icns"
FRAMES="$(mktemp -d)"
SRC="$(mktemp -t xbot-logo-src.XXXXXX.png)"

cleanup() { rm -rf "${FRAMES}" "${SRC}"; }
trap cleanup EXIT

mkdir -p "${ASSETS}"

if [[ -f "${ICON_PNG}" ]]; then
  cp "${ICON_PNG}" "${SRC}"
elif [[ -f "${ICNS}" ]]; then
  sips -s format png "${ICNS}" --out "${SRC}" >/dev/null
else
  echo "No icon source — add xBot.icon or build apps/mac/Sources/XBotApp/Resources/xBot.icns first." >&2
  exit 1
fi

python3 - "${SRC}" "${FRAMES}" <<'PY'
import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

src = Path(sys.argv[1])
frames_dir = Path(sys.argv[2])
logo = Image.open(src).convert("RGBA")
size = 480
frames = 120

colors = [
    (255, 201, 163, 100),
    (240, 138, 140, 100),
    (182, 94, 140, 100),
]
origins = [(0.22, 0.18), (0.78, 0.28), (0.62, 0.78)]

for frame in range(frames):
    t = frame / frames * 2 * math.pi
    base = Image.new("RGBA", (size, size), (255, 243, 236, 255))
    for i, (ox, oy) in enumerate(origins):
        phase = t * (0.9 + i * 0.05) + i * 2.0
        cx = size * ox + math.sin(phase) * 38
        cy = size * oy + math.cos(phase * 1.1) * 34
        r = size * 0.29
        blob = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(blob)
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=colors[i])
        blob = blob.filter(ImageFilter.GaussianBlur(radius=45))
        base = Image.alpha_composite(base, blob)

    scale = 1.0 + 0.03 * math.sin(t)
    float_y = 6 * math.sin(t * 0.7)
    logo_size = int(size * 0.62 * scale)
    logo_scaled = logo.resize((logo_size, logo_size), Image.LANCZOS)
    x = (size - logo_size) // 2
    y = int((size - logo_size) // 2 + float_y)
    base.paste(logo_scaled, (x, y), logo_scaled)
    base.convert("RGB").save(frames_dir / f"frame_{frame:04d}.png")
PY

ffmpeg -y -framerate 30 -i "${FRAMES}/frame_%04d.png" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
  "${ASSETS}/logo-animated.mp4" >/dev/null 2>&1

cp "${FRAMES}/frame_0000.png" "${ASSETS}/logo-mark.png"
echo "Wrote ${ASSETS}/logo-animated.mp4 and ${ASSETS}/logo-mark.png"
