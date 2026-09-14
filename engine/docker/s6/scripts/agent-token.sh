#!/bin/sh
# The secret the API presents to the Bot beside it.
#
# Same posture as computer-token.sh, and for the same reason: two processes in one container that an
# operator cannot address separately should not need a shared secret invented by hand. The Bot
# refuses to start without one, and the API only sends it to the endpoint it was configured for, so
# a customer's own agent never sees it. Set MANAGED_AGENT_TOKEN yourself and this leaves it be.
set -eu
environment_dir="${1:-/run/s6/container_environment}"
if [ -z "${MANAGED_AGENT_TOKEN:-}" ]; then
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' \
    > "$environment_dir/MANAGED_AGENT_TOKEN"
fi

# The reverse direction needs its own token too: the Bot calls the API to execute granted tools.
# Both services load this environment; a signed run assertion is still required on every callback.
if [ -z "${AGENT_TOOL_TOKEN:-}" ]; then
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' \
    > "$environment_dir/AGENT_TOOL_TOKEN"
fi
