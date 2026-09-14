#!/bin/sh
# The secret the routine worker presents to the API beside it.
#
# Routines were dark in this image: they are swept by a separate worker that hands each due firing to
# /internal/routines/run with this secret, and the image ran no worker and set no secret. An agent
# would set up "check the inbox every weekday at nine" and it would never run, with nothing anywhere
# saying so.
#
# Generated for the same reason the computer and agent tokens are: two processes in one container
# should not need a secret invented by hand. Set WORKER_SHARED_SECRET yourself and this leaves it be.
set -eu
environment_dir="${1:-/run/s6/container_environment}"
if [ -z "${WORKER_SHARED_SECRET:-}" ]; then
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' \
    > "$environment_dir/WORKER_SHARED_SECRET"
fi
