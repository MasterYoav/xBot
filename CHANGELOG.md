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

- A new look: neutral surfaces in light and dark with one accent, a quiet sidebar (search ⌘K,
  Home, Inbox, projects with their chats, Recent), pill tabs, and a Home that asks "What should we
  work on?" over a composer with the project and branch on top and four ways in below. Replies
  read like documents — headings, lists, code — with the agent's tools folded into one line.
  Plan cards, status pills and toasts share one component kit. Deleting a chat offers Undo.

- Reasoning effort on a slider — Low to Max, and Galaxy: Claude Code at max on Opus, Codex at its
  ultra level. Saved per chat. Codex's model menu shows its real models.

- Files and changes (⌥⌘0), a right-hand column for the project in view. **Changes**: the branch,
  how far it is ahead or behind, its state in a word (Up to date, To pull, To push, Diverged,
  Conflict, Local), the branch's pull request and its checks when GitHub's `gh` is installed,
  Commit (⌘↩), Sync, Publish, and each changed file — stage, unstage, discard, or click to read
  its diff. Diverged branches get **Ask the agent to merge**. **Explorer**: the project's files,
  coloured by git and dimmed where git ignores them; preview, open, rename, move to the Trash, or
  mention a file to the agent (also by dragging it onto the composer). Both follow the folder live.
- The account menu, at the bottom of the sidebar: your picture and name, your plans, and the
  usage each agent has left in its five-hour and weekly windows. No passwords or sign-in tokens
  are read.
- A profile page built from your agents' own history on this Mac: lifetime and peak tokens,
  longest task, streaks, your most active projects, a year of token activity, top tools and
  insights.
- Settings (⌘,): background picture, and the agent, reasoning and permission new chats start with.
- The top bar has no grey strip; the background runs up behind the tabs.
- Terminal-style tabs in the title bar (⌘1…⌘9), the sidebar running to the top beside the traffic
  lights, and a sunset that fades across the top of Home and, softly, behind chats.

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
