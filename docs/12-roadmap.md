# Roadmap

What's built, what's waiting to be merged, and what's next. The direction comes from the
[redesign spec](superpowers/specs/2026-10-06-xbot-redesign-design.md); each sub-project gets its own
spec in [`superpowers/specs/`](superpowers/specs/) before it's built. The history of xBot 1.x (the
Docker/OpenBot engine and its milestones M0–M7) is in git and in the [changelog](../CHANGELOG.md).

## Status

| | Sub-project | State |
| --- | --- | --- |
| 1a | Shell, projects, harness chats (Claude Code, Codex); the old engine deleted | **Merged** (#15) |
| — | Workspace panels: inspector (Changes, Explorer), account menu, profile | **Merged** (#16) |
| — | Plan mode, edit and resend, appearance, tab reordering, app icons | **Merged** (#18–#22) |
| 2 | Notes (as Markdown in the project) and Abilities | **Merged** (#23). The `notes.*` tools and the `xbot-mcp` relay aren't built |
| 3 | The crew: HeadMaster, hand-offs, pixel avatars, the workplace and its five worlds | **Merged** (#24, #27). Memory, habits and Quick Composer aren't built |
| — | In-app terminal | **Merged** (#25) |
| — | Agent-drawn text-art wallpapers | **Merged** (#26) |
| — | More providers: Antigravity and GitHub Copilot | **Merged** (#28) |
| — | Automations, also while xBot is closed (replacing the Inbox) | **Merged** (#29) |
| — | Motion gate: animations pause while xBot isn't in view | **Open** (#30) |
| — | The iPhone and iPad app | **Open**, a stack of PRs, each based on the one before: #31 pairing, lanes and chats → #32 managing chats → #33 projects → #34 notes → #35 automations → #36 crew → #37 abilities → #38 terminal → #39 profile → #40 Liquid Glass and the shared world → #41 accent, plan board, suggested agents, Markdown documents |
| — | The crew as a company: who reports to whom | **Open** (#42, on top of the stack) |
| 1b | Split panes, checkpoints, worktrees | Not started (the Changes inspector is built) |
| 3 | Onboarding rewrite | Not started. Today's first run is in [06-onboarding.md](06-onboarding.md) |
| 4 | Native brain: Anthropic, OpenAI, Google, Ollama tool loop | Not started |
| 5 | The machine: Containerization driver, image, `xbot-agentd`, shell and file tools | Not started |
| 6 | Browser and live screen: CDP, screencast inspector, take over | Not started |
| 7 | Licensing: the Pro licence gate | Not started |
| — | A signed 2.0 release | **Automated**: CI publishes `v<VERSION>` when `VERSION` changes on master; 2.0.0 publishes when the release PR merges. What's left: the [launch checklist](13-launch-checklist.md) |

Every merged step passes CI (`swift build --build-tests && swift test` on macOS 26). Each open PR
was built test-first, run live against a real Mac, and installed on a real iPhone.

## Next

In order:

1. **Merge the open PRs**: #30, then #31 → #42 in order. Each PR's base is the branch before it, so
   merging them in order keeps every diff reviewable.
2. **Release 2.0** from master: Developer ID signing, notarization, Sparkle, and a Developer ID
   provisioning profile with iCloud so the phone's away lane works on a downloaded build. The steps
   that need the account holder are in the [launch checklist](13-launch-checklist.md).
3. **Ship the phone app** through TestFlight.
4. **Native brain** (step 4), so a person without a CLI can start with an API key or Ollama. This is
   what lets xBot keep its promise to someone who has never opened a terminal.
5. **Onboarding**: the three screens from the redesign spec, built around the native brain.
6. **The machine and the browser** (steps 5 and 6).

## Later, unordered

- **Agents' memory and habits.** Automations already cover part of what habits were for. Whether
  habits are still needed, or become automations an agent owns, isn't decided.
- **Notifications on the phone** when a turn finishes or a plan needs an answer.
- **Import agents you already have**, starting with an `AGENTS.md` or `CLAUDE.md` file in a project:
  a system prompt maps onto an agent's instructions; tools and memory don't, and an import should
  say what didn't come across.
- **Shared agents**: export a crew member as a file someone else can import. A file, not a
  marketplace.

## Open questions

- **⚠️ The name** ([ADR-0006](decisions/0006-naming-and-trademark.md)) is still undecided.
- **Pricing.** The redesign spec proposes a free tier and xBot Pro at $59 one-time. Nothing of it is
  built, and what's free will need revisiting now that the crew and the phone exist.

## Explicitly not planned

Recorded so they don't get proposed again.

- **A hosted version.** It would be a different product and would break the promise.
- **Windows, Linux or Intel Macs.** The phone is a remote for a Mac, not a replacement.
- **Our own model.** xBot supplies none; that's what lets it support every CLI honestly.
- **Running agents on the phone.** The CLIs, projects and sign-ins are on the Mac.
- **A plugin marketplace of our own.** The CLIs' plugins and MCP are the ecosystem; Abilities
  manages them.
