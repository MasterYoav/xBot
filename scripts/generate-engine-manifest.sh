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

# The engine reports its schema as a migration tag — "0025_backfill_existing_users_have_onboarded".
# Absent when nothing is running to ask, which is the normal case in CI.
SCHEMA_TAG="$(curl -sf "http://127.0.0.1:3001/health" 2>/dev/null \
  | "${ROOT}/scripts/read-health-field.py" schemaVersion 2>/dev/null || echo "")"

# Every value reaches Python through the environment, never spliced into its source.
#
# They used to be interpolated into a heredoc directly, which made any value carrying a newline or
# a quote a syntax error in the generated program rather than data. CI failed on exactly that:
# `"schemaVersion": "0` and an unterminated string literal. A value that came from `curl` is input,
# and input does not belong in source.
CHANNEL="${CHANNEL}" \
VERSION="${VERSION}" \
IMAGE_REF="${REF}" \
IMAGE_SIZE="${SIZE}" \
MIN_APP="${MIN_APP}" \
SCHEMA_TAG="${SCHEMA_TAG}" \
TEMPLATE_PATH="${TEMPLATE}" \
  "${ROOT}/scripts/build-engine-manifest.py"
