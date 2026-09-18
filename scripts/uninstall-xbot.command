#!/usr/bin/env bash
# Remove everything xBot stored on this Mac, for somebody who already dragged the app to the Trash.
#
# Ships in the DMG. docs/11-packaging-and-updates.md: this is the one place the no-terminal promise
# yields, because the alternative is gigabytes of orphaned volumes with no way to remove them. The
# in-app path (Settings → Advanced → Uninstall) does the same, and is what everybody else should use.
#
# Mirrors AppState.uninstall() and RuntimeController.uninstall(). Change one, change the other.
#
# Like the app, it leaves the container runtime alone — Docker or Colima may be in use for something
# else.
set -uo pipefail

SUPPORT="${HOME}/Library/Application Support/xBot/runtime"

cat <<'EOF'
This removes everything xBot stored on this Mac:

  - your conversations and your agents
  - the websites your agents are signed in to
  - the keys xBot saved in your Keychain
  - xBot's preferences

It does not remove Docker or Colima. It cannot be undone.
EOF
printf '\nType "remove" to continue: '
read -r answer
if [[ "${answer}" != "remove" ]]; then
  echo "Nothing was removed."
  exit 0
fi

if pgrep -xq XBot; then
  echo "Quit xBot first, then run this again."
  exit 1
fi

# The Docker CLI xBot installed, or whichever one is on the PATH.
DOCKER="${SUPPORT}/bin/docker"
[[ -x "${DOCKER}" ]] || DOCKER="$(command -v docker || true)"

# Colima that xBot installed for them, started the way the app starts it. Without this the line
# below would tell somebody to "start Colima" — a tool they never chose and have no way to start.
COLIMA="${SUPPORT}/bin/colima"
if [[ -n "${DOCKER}" && -x "${COLIMA}" ]] && ! "${DOCKER}" info >/dev/null 2>&1; then
  echo "Starting the container runtime xBot installed. This can take a minute…"
  PATH="${SUPPORT}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" "${COLIMA}" start >/dev/null 2>&1
  for _ in $(seq 1 60); do
    "${DOCKER}" info >/dev/null 2>&1 && break
    sleep 1
  done
fi

if [[ -n "${DOCKER}" ]] && "${DOCKER}" info >/dev/null 2>&1; then
  "${DOCKER}" rm -f xbot-engine >/dev/null 2>&1
  for volume in xbot-data xbot-workspace xbot-profiles; do
    "${DOCKER}" volume rm -f "${volume}" >/dev/null 2>&1
  done
  echo "Removed the engine and its data."
else
  # Said, not skipped quietly: the volumes are the gigabytes this script exists for.
  echo "Docker is not running, so the engine's data could not be removed."
  echo "Start Docker Desktop or Colima, then run this again."
fi

# Every service xBot writes, by name — never a wildcard sweep of the login Keychain. One service can
# hold several accounts (a key per provider), so each is deleted until none is left.
for service in dev.xbot.provider-key dev.xbot.engine-token dev.xbot.key-encryption-key \
  dev.xbot.intelligence-key dev.xbot.copilotkit-license; do
  while security delete-generic-password -s "${service}" >/dev/null 2>&1; do :; done
done
echo "Removed xBot's Keychain items."

# The pre-upgrade dump is a plain-SQL copy of the database, kept outside the volume on purpose.
rm -f "${SUPPORT}/engine-pre-upgrade.sql" "${SUPPORT}/restore.log"

defaults delete dev.xbot.app >/dev/null 2>&1
echo "Removed xBot's preferences."

echo
echo "Done."
