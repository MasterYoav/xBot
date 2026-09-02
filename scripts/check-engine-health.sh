#!/usr/bin/env bash
# Read-only check: is an xBot engine answering on loopback?
#
# Usage: scripts/check-engine-health.sh [port]
# Without a port: reads it from the xbot-engine container, then tries 3001 and 49152–49400.
set -euo pipefail

if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found" >&2
  exit 1
fi

check_port() {
  local port="$1"
  local url="http://127.0.0.1:${port}/health"
  local body
  body="$(curl -sf "$url" 2>/dev/null)" || return 1
  echo "$body" | grep -q '"product"[[:space:]]*:[[:space:]]*"xBot"' || {
    echo "Engine at ${url} did not identify as xBot:" >&2
    echo "$body" >&2
    return 1
  }
  echo "xBot engine healthy at ${url}:"
  echo "$body"
}

if [[ -n "${1:-}" ]]; then
  check_port "$1"
  exit 0
fi

if command -v docker >/dev/null 2>&1; then
  mapped="$(docker port xbot-engine 2>/dev/null | awk -F: '/->/ {print $NF; exit}')"
  if [[ -n "$mapped" ]]; then
    check_port "$mapped"
    exit 0
  fi
fi

for port in 3001 $(seq 49152 49400); do
  if check_port "$port" 2>/dev/null; then
    exit 0
  fi
done

echo "No xBot engine found on loopback (tried 3001 and 49152–49400)" >&2
exit 1
