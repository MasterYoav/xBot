#!/usr/bin/env bash
# M5 smoke check: engine health + agents API reachable on loopback.
#
# Usage: scripts/verify-m5-handoff.sh [port]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${1:-}"

if [[ -z "${PORT}" ]]; then
  if command -v docker >/dev/null 2>&1; then
    PORT="$(docker port xbot-engine 2>/dev/null | awk -F: '/->/ {print $NF; exit}')"
  fi
  PORT="${PORT:-3001}"
fi

echo "Checking xBot engine on port ${PORT}…"
"${ROOT}/scripts/check-engine-health.sh" "${PORT}"

URL="http://127.0.0.1:${PORT}/api/agents"
echo ""
echo "Probing ${URL}…"

AUTH=()
if command -v security >/dev/null 2>&1; then
  TOKEN="$(security find-generic-password -s dev.xbot.engine-token -a default -w 2>/dev/null || true)"
  if [[ -n "${TOKEN}" ]]; then
    AUTH=(-H "Authorization: Bearer ${TOKEN}")
  fi
fi

BODY="$(curl -sf "${AUTH[@]}" "${URL}" 2>/dev/null)" || {
  echo "Agents API did not answer — the engine may require a bearer token (expected in production)." >&2
  exit 1
}

echo "${BODY}" | grep -q '"agents"' || {
  echo "Unexpected agents response:" >&2
  echo "${BODY}" >&2
  exit 1
}

echo "M5 handoff smoke check passed."
