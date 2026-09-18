#!/usr/bin/env bash
# Print the Sparkle EdDSA public key, generating the pair on first run.
#
# docs/13-launch-checklist.md step 3. Sparkle's own tool is already in the SwiftPM artifacts, so
# there is nothing to download: this only finds it and runs it.
#
# The private key goes into your login Keychain, which is where Sparkle's tool puts it. Back it up —
# losing it strands every shipped version, because an app cannot verify an update signed by a key it
# has never seen.
set -euo pipefail

MAC="$(cd "$(dirname "$0")/../apps/mac" && pwd)"

GENERATE_KEYS="$(find "${MAC}/.build/artifacts/sparkle" -name generate_keys -type f 2>/dev/null | head -1)"
if [[ -z "${GENERATE_KEYS}" ]]; then
  echo "Sparkle's generate_keys is not built yet — run: cd apps/mac && swift build -c release" >&2
  exit 1
fi

# -p prints the public key for a pair that already exists, and says so if there is none, so a second
# run never quietly replaces the key every shipped build was signed against.
if "${GENERATE_KEYS}" -p 2>/dev/null; then
  echo
  echo "That is XBOT_SPARKLE_PUBLIC_KEY. The private key is already in your login Keychain."
  exit 0
fi

"${GENERATE_KEYS}"
