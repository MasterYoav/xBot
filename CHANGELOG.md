# Changelog

## Unreleased — the redesign

xBot is now a native app that drives the agent CLIs you already have. See
[ADR-0009](docs/decisions/0009-native-harness-redesign.md).

### Added
- Projects: add any folder; chats in it work in that folder.
- Chats as tabs, with Claude Code or Codex answering on your own subscription, streamed live, with
  each tool call shown and its output a click away. Every chat continues its CLI session.
- An Inbox for chats that don't belong to a project.
- Read only / Can edit / Full access per chat.
- Everything saved locally in one SQLite file; a reply interrupted by Stop or by quitting keeps
  what had arrived.

- Plan mode: turn on **Plan** in the composer and the agent first investigates without changing
  anything and proposes steps. Edit, reorder, remove or add steps, then **Run plan** (⌘↩) and
  watch each one run: progress, the step in progress and its tools, how long each took, failures
  with their reason, and steps the agent adds to finish the job. **Review plan first** off runs the
  plan straight away. Stop and Resume work mid-plan.

### Removed
- The OpenBot engine, Docker and Colima, Postgres, the CopilotKit runner, the engine image and its
  update pipeline, onboarding, settings and the web admin. Onboarding, bots, notes, the native model
  loop and each bot's own computer come back rebuilt, in the order the
  [redesign spec](docs/superpowers/specs/2026-10-06-xbot-redesign-design.md) sets out.
- Intel Macs and macOS before 26.

### From upstream
- xBot 1.x was built on [OpenBot](https://github.com/CopilotKit/openbot) (MIT, © 2026 CopilotKit).
  No OpenBot code ships any more; the credit stays in `NOTICE` and the About window.

## 1.0.0

The Docker/OpenBot release. See the git history before the redesign.
