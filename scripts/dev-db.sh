#!/usr/bin/env bash
# Test/dev database for the engine suite.
#
# Port 55432, not 5432: a Homebrew Postgres already owns 5432 on this machine, and the
# engine then connects to it and fails with `role "openbot" does not exist`. That exact
# collision is documented in docs/03-openbot-fork.md and is what the app's port negotiation
# exists to solve. This script is the developer's version of that — it never touches 5432.
#
# pgvector, not plain postgres: the knowledge schema uses the extension.
#
# Usage:  eval "$(scripts/dev-db.sh)"   # starts it if needed, prints DATABASE_URL
set -euo pipefail

NAME=xbot-dev-db
PORT=55432
URL="postgres://openbot:openbot@127.0.0.1:${PORT}/openbot"

if [ -z "$(docker ps -q -f "name=^${NAME}$")" ]; then
  if [ -n "$(docker ps -aq -f "name=^${NAME}$")" ]; then
    docker start "${NAME}" >/dev/null
  else
    docker run -d --name "${NAME}" \
      -e POSTGRES_DB=openbot -e POSTGRES_USER=openbot -e POSTGRES_PASSWORD=openbot \
      -p "127.0.0.1:${PORT}:5432" \
      pgvector/pgvector:pg17 >/dev/null
  fi
  until docker exec "${NAME}" pg_isready -U openbot -d openbot >/dev/null 2>&1; do sleep 1; done
fi

echo "export DATABASE_URL=${URL}"
