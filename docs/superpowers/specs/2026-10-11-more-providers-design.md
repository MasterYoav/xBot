# More providers: Antigravity (Gemini) and GitHub Copilot

Status: approved in conversation, 2026-10-11.

xBot drives agent CLIs on the person's own subscriptions, so a provider is a CLI. Asked for:
Gemini, Grok/Cursor, and other top providers. Found on this Mac (2026-10-11):

| CLI | State | Outcome |
|---|---|---|
| Gemini CLI 0.46 | Google refuses personal accounts: "no longer supported… migrate to the Antigravity suite" | Not added |
| **Antigravity CLI** (`agy` 1.2.5), Google's successor | Signed in | **Added**: Gemini 3.x Flash/Pro, plus the Claude and GPT-OSS models Google offers in it |
| **GitHub Copilot CLI** 1.0.83 | Signed in | **Added**: on this plan only `auto` is available; other plans get Grok 4.x, Gemini, Claude, GPT, Kimi |
| Cursor CLI (`cursor-agent`) | Installed, not signed in | Next, once signed in (it offers Grok) |
| OpenCode 1.18 | Installed, its token expired (401) | Next, once signed in (xAI/Grok and many providers) |
| xAI Grok | No official coding CLI (a community `grok-cli` exists) | Through Copilot, Cursor or OpenCode |

Parsers are built from recorded real output (`Tests/XBotBrainTests/Fixtures/copilot-*.jsonl`,
`antigravity-*`; paths scrubbed), like Claude Code's and Codex's.

## Differences the app handles

- **Prompt**: neither reads stdin; the prompt is passed attached to its flag (`--prompt=…`,
  `--print=…`) so one starting with `-` can't be read as an option (verified).
- **Who the agent is** (crew instructions): no system-prompt option, so it goes ahead of the
  prompt in `<instructions>`.
- **Permissions**: Copilot read-only = default (reads auto-approved, everything else denied
  headless; verified), can edit = `--allow-tool write`, full = `--allow-all-tools`. Antigravity
  read-only = `--mode plan` (reads, no edits; verified). Its edit mode refuses even reads headless,
  so "Can edit" uses `--dangerously-skip-permissions`; the permission menu says so.
- **Plan mode and drawn wallpapers** need schema'd answers: Antigravity's `--json-schema` came back
  empty, Copilot has none. The Plan chip is greyed out for them (and a plan-mode chat on one just
  runs); the wallpaper sheet offers only Claude Code and Codex.
- **Models**: Antigravity's from `agy models` when agents are found. Copilot: its automatic choice
  (no list command; named models not on the plan fail with "not available").
- **Reasoning**: Copilot `--reasoning-effort`; Antigravity `--effort low|medium|high`.
- **Sessions**: Copilot `--resume <id>` (id arrives on its final `result` line); Antigravity
  `--conversation <id>` (from `init`). Both verified to remember the previous turn.
- **Usage limits** and **Abilities** stay Claude Code and Codex only: the others don't report
  limits, and managing their plugins is separate work.
- Tool names are mapped to Claude Code's (view → Read, bash/run_command → Bash, …) so tool rows
  read the same whichever agent ran them.
