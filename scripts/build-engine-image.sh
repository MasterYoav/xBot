#!/usr/bin/env bash
# Build the xBot engine image locally for development.
#
# Tags the upstream Dockerfile output as xbot/engine:1 — the reference XBotApp and the runtime
# tests expect. The app then finds it with `docker image inspect` and skips a registry pull.
#
# This is a developer script, not something the shipped app runs. Users get a pinned digest from a
# manifest (docs/10-security.md); M3's publish pipeline replaces this tag with that.
#
# Usage:
#   scripts/build-engine-image.sh              # build xbot/engine:1
#   scripts/build-engine-image.sh --no-cache   # rebuild from scratch
#
# Requires Docker (or OrbStack/Colima with the docker CLI on PATH). First build is slow — Playwright
# base, bun install, app build — and needs network access to pull base layers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="xbot/engine:1"
CACHE=()

if [[ "${1:-}" == "--no-cache" ]]; then
  CACHE=(--no-cache)
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found on PATH — install Docker Desktop, OrbStack, or Colima first." >&2
  exit 1
fi

echo "Building ${IMAGE} from engine/Dockerfile (this takes several minutes on first run)…"
if ((${#CACHE[@]})); then
  docker build "${CACHE[@]}" -t "${IMAGE}" "${ROOT}/engine"
else
  docker build -t "${IMAGE}" "${ROOT}/engine"
fi

echo ""
echo "Done. ${IMAGE} is ready."
echo "Run the app against the real runtime:"
echo "  cd apps/mac && XBOT_USE_RUNTIME=1 swift run"
