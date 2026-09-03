#!/usr/bin/env bash
# Emit a pinned engine manifest JSON for the Mac app's update pipeline (M3).
#
# Usage:
#   scripts/generate-engine-manifest.sh                     # local xbot/engine:1
#   scripts/generate-engine-manifest.sh ghcr.io/org/xbot-engine@sha256:abc…
#
# Local tags have no registry digest — the script uses the image ID as a dev placeholder.
# CI should pass the pushed ghcr.io reference after `docker push`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="${ROOT}/scripts/engine-manifest.template.json"
IMAGE="${1:-xbot/engine:1}"
CHANNEL="${CHANNEL:-stable}"
MIN_APP="${MINIMUM_APP_VERSION:-1.0.0}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found on PATH" >&2
  exit 1
fi

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "Image ${IMAGE} not found — run scripts/build-engine-image.sh first." >&2
  exit 1
fi

VERSION="$(git -C "${ROOT}" describe --tags --always --dirty 2>/dev/null || echo dev)"
SIZE="$(docker image inspect "${IMAGE}" --format '{{.Size}}')"

if [[ "${IMAGE}" == *"@sha256:"* ]]; then
  REF="${IMAGE}"
else
  ID="$(docker image inspect "${IMAGE}" --format '{{.Id}}')"
  REF="local-dev@${ID#sha256:}"
fi

SCHEMA="$(curl -sf "http://127.0.0.1:3001/health" 2>/dev/null | python3 -c "
import json, sys
try:
    o = json.load(sys.stdin)
    print(o.get('schemaVersion', '0'))
except Exception:
    print('0')
" 2>/dev/null || echo "0")"

python3 - <<PY
import json
from pathlib import Path

template = json.loads(Path("${TEMPLATE}").read_text())
template.update({
    "channel": "${CHANNEL}",
    "version": "${VERSION}",
    "image": "${REF}",
    "size": int("${SIZE}"),
    "minimumAppVersion": "${MIN_APP}",
    "migration": {
        "schemaVersion": "${SCHEMA}",
        "backwardCompatibleWith": 0,
    },
})
print(json.dumps(template, indent=2))
PY
