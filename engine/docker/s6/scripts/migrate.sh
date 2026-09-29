#!/bin/sh
# Migrations, for the embedded database only.
#
# An external database is somebody else's release process: two replicas starting together would
# race, and a failed migration should stop a deploy rather than leave a half-migrated database
# serving. An embedded one has exactly one process and no deploy pipeline, so doing it here is the
# difference between the container working and the operator reading a runbook.
set -eu
[ "${EMBEDDED_POSTGRES:-off}" = "on" ] || exit 0
cd /app/server
# `postgres` is a longrun with no readiness notification, so s6 starts this the moment the process
# exists, not when it accepts connections. After an unclean stop it replays WAL first and answers
# 57P03 "not yet accepting connections"; migrating then exits 1, and `api`, which depends on this,
# never starts — the container sits unhealthy with nothing on :3001. Wait for it, but not forever.
i=0
until /usr/lib/postgresql/16/bin/pg_isready -q -h 127.0.0.1 -p 5432; do
  i=$((i + 1))
  if [ "$i" -ge 120 ]; then
    echo "migrate: postgres did not accept connections within 60s" >&2
    exit 1
  fi
  sleep 0.5
done
# `scripts/migrate.ts`, not `drizzle-kit`. The CLI is a development dependency and needs esbuild to
# read its TypeScript config, which `bun install --production` leaves out of this image: asked to
# migrate here it exits 1 without printing why, and the container comes up against an empty database.
exec s6-setuidgid pwuser /usr/local/bin/bun scripts/migrate.ts
