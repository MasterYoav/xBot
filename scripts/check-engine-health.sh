#!/usr/bin/env bash
# Read-only check: is an xBot engine answering on loopback?
#
# Usage: scripts/check-engine-health.sh [port]
# Default port: 49152 (first slot in RuntimeController's range)
set -euo pipefail

PORT="${1:-49152}"
URL="http://127.0.0.1:${PORT}/health"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found" >&2
  exit 1
fi

BODY="$(curl -sf "$URL" 2>/dev/null)" || {
  echo "No engine answering at ${URL}" >&2
  exit 1
}

echo "$BODY" | grep -q '"product"[[:space:]]*:[[:space:]]*"xBot"' || {
  echo "Engine at ${URL} did not identify as xBot:" >&2
  echo "$BODY" >&2
  exit 1
}

echo "xBot engine healthy at ${URL}:"
echo "$BODY"
