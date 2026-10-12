# ADR-0009 — A native app that drives the agents people already have

**Status:** Accepted
**Date:** 2026-10-06
**Supersedes:** [ADR-0001](0001-local-history-provider.md), [ADR-0002](0002-per-bot-model-router.md),
[ADR-0003](0003-container-runtime.md), [ADR-0007](0007-wrap-openbot-keep-intelligence.md),
[ADR-0008](0008-local-thread-runner.md). Narrows [ADR-0004](0004-native-vs-webview.md): there is no
embedded web admin any more.
**Design:** [`docs/superpowers/specs/2026-10-06-xbot-redesign-design.md`](../superpowers/specs/2026-10-06-xbot-redesign-design.md)

---

## Context

xBot 1.0 shipped OpenBot's engine — a Node server, Postgres with pgvector, CopilotKit's runner, a
supervisor and a per-agent computer — inside Docker, which the app installed (Colima) and drove on
the person's behalf. It worked, and it was heavy: a container runtime to install and babysit, a
multi-gigabyte image to pull and upgrade, a database to migrate, and an agent loop that duplicated
the ones people already pay for in Claude Code, Codex and their peers.

MonoCode showed a lighter shape: a desktop app that drives the agent CLIs a person already has,
on their own subscriptions, and puts the experience — projects, chats as tabs, notes, persistent
personas — around them. What it lacks is what xBot was for: an agent with a computer of its own.

## Decision

1. **xBot is a native Swift app with no services.** No Docker, no Node, no Postgres, no listening
   ports. Projects, chats and messages live in one SQLite file in Application Support.
2. **Bots think with a harness first.** xBot spawns an installed agent CLI per turn (Claude Code
   and Codex first), feeds the prompt on stdin, reads its JSON stream and resumes its session id.
   A built-in native agent loop for API keys and Ollama follows, so nobody *needs* a CLI.
3. **A bot's computer is an Apple Containerization VM,** off by default and per bot, reached
   through an MCP server xBot hosts. (Sub-projects 5 and 6 of the design.)
4. **macOS 26 on Apple silicon** is the floor, because Containerization is.
5. **OpenBot's code is removed.** The credit to OpenBot and CopilotKit stays in `NOTICE` and the
   About window as the history of the product.

## Consequences

- The app installs and runs in seconds; there is nothing to pull, migrate or keep running.
- Harness stream formats belong to their vendors and change without notice. Each CLI gets one
  parser, tested against output recorded from a real run, and an opt-in live test
  (`XBOT_LIVE_HARNESS=1`) that runs a real turn and a resumed turn.
- Without a CLI or (later) a key, there is no intelligence. The app says so, and offers the way to
  get one, without telling anyone to open a terminal.
- Intel Macs and macOS before 26 are no longer supported.
- xBot 1.x users keep a Docker container and volumes on disk; `scripts/uninstall-xbot.command`
  removes them.

## Since then

Recorded here so the decision above isn't read as describing the app today.

- **Four harnesses, not two.** Antigravity (`agy`) and GitHub Copilot (`copilot`) joined Claude Code
  and Codex ([spec](../superpowers/specs/2026-10-11-more-providers-design.md)). Neither reads a
  prompt from stdin, so for them it goes on its own flag, attached as `--print=…` / `--prompt=…`,
  which a prompt starting with `-` can't be mistaken for.
- **"No listening ports" was relaxed for the phone.** The iPhone and iPad remote
  ([spec](../superpowers/specs/2026-10-11-mobile-remote-design.md)) needs the Mac reachable on the
  local network: after the first pairing, xBot listens on one TCP port, advertised over Bonjour,
  that accepts only TLS with a pairing key. With no paired device it listens on nothing. Away from
  home the phone goes through the person's own iCloud, not a port.
- **Still no services.** One optional LaunchAgent exists, `dev.xbot.automations`, which starts xBot's
  own binary headless once a minute to run due automations while the app is closed. It's off until
  the person turns it on.
