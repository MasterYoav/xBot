# Agents and providers

xBot has no model of its own and holds no API keys. Its intelligence comes from the agent CLIs the
person already has installed and is signed in to, run on their own subscriptions. A provider, in
xBot, is a CLI.

Four are supported today, each a case of `HarnessKind` (`apps/mac/Sources/XBotBrain/HarnessKind.swift`):

| Agent | Binary | Models behind it |
| --- | --- | --- |
| Claude Code | `claude` | Anthropic's Claude |
| Codex | `codex` | OpenAI's models on a ChatGPT plan |
| Antigravity | `agy` | Gemini, plus the other models Google offers in it. It replaced Gemini CLI, which no longer works for personal Google accounts |
| GitHub Copilot | `copilot` | Whatever models the person's Copilot plan includes |

With none installed, Home says "xBot works through an agent you already have" and links to Claude
Code and Codex; the welcome tour's agents step installs and signs in to any of the four
([First run](06-onboarding.md)). There is no key field anywhere in the app.

## How a turn runs

`HarnessBrain` (`XBotBrain/HarnessBrain.swift`) runs **one fresh process per turn**, in the chat's
folder, and continues the conversation through the CLI's own session id. A crashed turn cannot
leave a wedged process behind for the next one.

1. If the chat's folder has gone, the turn fails with a sentence saying so, before anything runs.
2. `HarnessKind.arguments(for:)` builds the argv. **The prompt is never in argv for Claude Code and
   Codex**: it goes on stdin, because a prompt starting with `-` would be read as a flag and argv
   has a length limit. Antigravity and Copilot cannot read stdin, so for them the prompt is
   attached to its flag (`--print=…`, `--prompt=…`), which still cannot be mistaken for an option;
   their stdin is empty and closed at once.
3. stdout is split on `\n` bytes by xBot itself (not `bytes.lines`, which also breaks at U+2028 and
   U+2029 inside JSON strings) and each line goes to that CLI's parser, which turns it into
   `BrainEvent`s: session, text, tool call, tool result, structured answer, limits, notice, done,
   failed.
4. The stream ends with exactly one `.done` or `.failed`. If the CLI exits without either, the turn
   fails with the last 4 KB of stderr, or "stopped before finishing (exit code N)".
5. Stop sends `SIGTERM` to the CLI, which tears down its own tools. Writing to a CLI that has
   already exited cannot raise `SIGPIPE` and take the app with it (`F_SETNOSIGPIPE`).

The UI never knows which agent produced an event. Other CLIs' tool names are mapped to Claude
Code's (`view` → Read, `run_command` → Bash, `str_replace` → Edit, …, in `ToolNames`), so tool rows
read the same whichever agent ran them.

### Finding the CLIs

An app started from the Dock inherits launchd's bare `PATH`, which contains none of the places these
CLIs install to — and the CLIs need the person's `PATH` to run their own tools. `HarnessLocator`
therefore runs the login shell (`$SHELL -l -i -c`, five-second limit, the value read between markers
because startup files may print anything) and appends the usual folders: `~/.local/bin`,
`/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`, `~/.bun/bin`, `~/.claude/local`, and the
system bins. The first executable named after the CLI on that path wins. Every CLI is started with
that `PATH`; variables beginning `CLAUDECODE` or `CLAUDE_CODE_` are removed from its environment.

Settings › Agents lists, per agent, where it was found (or "Not installed"), whether it is signed
in, its plan and its usage left, with a **Look Again** button. "Signed in" is read from
`~/.claude.json` for Claude Code; Codex counts as signed in once it has reported a plan; Antigravity
and Copilot are "Checked on the first turn".

## The composer's controls, per agent

### Permission mode

The person picks **Read only**, **Can edit** or **Full access** (`PermissionMode`); each CLI gets
its own flags.

| | Read only | Can edit | Full access |
| --- | --- | --- | --- |
| Claude Code | `--permission-mode default` | `--permission-mode acceptEdits` | `--permission-mode bypassPermissions` |
| Codex | `-c sandbox_mode="read-only"` | `-c sandbox_mode="workspace-write"` | `-c sandbox_mode="danger-full-access"` |
| Copilot | no flag (reads allowed, anything else denied headless) | `--allow-tool write` | `--allow-all-tools --allow-all-paths` |
| Antigravity | `--mode plan` | `--dangerously-skip-permissions` | `--dangerously-skip-permissions` |

Antigravity's edit mode, run headless, refuses even to read, so **Can edit has to use its full
permissions** (`editingNeedsFullAccess`). The permission menu says so when Antigravity is chosen.

Codex takes the sandbox through `-c` rather than `-s` because `codex exec resume` has no `-s`.

### Reasoning effort

One slider, six stops, for every agent: Low, Medium, High, Extra, Max and Galaxy (`Effort.swift`).
The slider marks a "Recommended" stop: the model's own default where the agent reports one (Codex),
otherwise Medium. Each CLI gets its own spelling:

| Stop | Claude Code `--effort` | Codex `model_reasoning_effort` | Copilot `--reasoning-effort` | Antigravity `--effort` |
| --- | --- | --- | --- | --- |
| Low | `low` | `low` | `low` | `low` |
| Medium | `medium` | `medium` | `medium` | `medium` |
| High | `high` | `high` | `high` | `high` |
| Extra | `xhigh` | `xhigh` | `xhigh` | `high` |
| Max | `max` | `max` | `max` | `high` |
| Galaxy | `max`, and the model becomes `opus` | `ultra`, on a model that supports it | `max` | `high` |

**Galaxy** is the most each agent can do. On Claude Code it forces Opus whatever model was picked. On
Codex it keeps the chosen model if that model reasons at `ultra`, otherwise switches to the first
listed model that does (`CodexModels.model(for:chosen:in:)`).

### Models

The agent chip lists, per agent, **Default model** (no `--model` flag: the CLI's own choice,
whatever it is this week) and then the models from `Workspace.modelOptions`, filled when the agents
are found:

| Agent | Models offered | Where the list comes from |
| --- | --- | --- |
| Claude Code | Opus, Sonnet, Haiku | A fixed list of the aliases the CLI takes (`Workspace.claudeModels`) |
| Codex | Whatever the account can use, in Codex's order, with each model's reasoning levels and default | `~/.codex/models_cache.json`, the cache Codex keeps (models with `visibility: "list"`) |
| Antigravity | Whatever Google offers the account | `agy models`, run when agents are found (it asks Google; 20-second limit) |
| Copilot | Default only | Copilot has no list command; a named model not on the plan fails with "not available" |

Changing a chat's agent clears its model and its session.

### Plan mode

Plan mode needs answers that follow a JSON schema: one read-only planning turn that returns the
plan, then one turn per step that returns the step's outcome. Only Claude Code and Codex can do that
(`givesStructuredAnswers`, sent to the phone as `makesPlans`).

- **Claude Code**: `--json-schema <schema>`; the planning turn runs with `--permission-mode plan`.
  Its plan-mode file writes into `~/.claude/plans` and its `StructuredOutput` tool are hidden from
  the transcript.
- **Codex**: `--output-schema <file>`, a temporary file written per turn and removed when it ends;
  the planning turn runs in the read-only sandbox.
- **Antigravity and Copilot**: Antigravity's `--json-schema` came back empty when tried; Copilot has
  none. The Plan chip is greyed out with "can't make plans in xBot yet", and a chat with plan mode
  on simply runs. Drawn wallpapers need schema'd answers too, so that sheet offers only Claude Code
  and Codex.

### Who the agent is

A crew member's instructions are sent on every turn. Claude Code takes them as
`--append-system-prompt`, Codex as `-c developer_instructions=<TOML string>`. Antigravity and Copilot
have no system-prompt option, so the instructions go ahead of the prompt inside
`<instructions>…</instructions>`.

### Sessions

| Agent | Session id read from | Passed back as |
| --- | --- | --- |
| Claude Code | `system` / `init` line, `session_id` | `--resume <id>` |
| Codex | `thread.started`, `thread_id` | `codex exec resume … <id> -` |
| Copilot | the final `result` line, `sessionId` | `--resume <id>` |
| Antigravity | `init`, `conversation_id` | `--conversation <id>` |

## The four, in detail

### Claude Code

```
claude -p --output-format stream-json --verbose --include-partial-messages
       --permission-mode <mode> [--model <alias>] [--effort <level>] [--resume <id>]
       [--json-schema <schema>] [--append-system-prompt <instructions>]
```

Prompt on stdin. Parsed by `ClaudeStream`: reply text from the `stream_event` text deltas only (the
complete `assistant` message that follows repeats it); tool calls from the `assistant` message,
where their input is whole, with "+N" lines for a write or an edit; anything a subagent says
(`parent_tool_use_id` set) is left out of the reply.

### Codex

```
codex exec [resume] --json --skip-git-repo-check -c sandbox_mode="<mode>" [-m <model>]
           [-c model_reasoning_effort="<level>"] [--output-schema <file>]
           [-c developer_instructions="<instructions>"] [<session id>] -
```

The trailing `-` reads the prompt from stdin. Parsed by `CodexStream`. Items arrive whole, so a
Codex reply appears a message at a time rather than token by token. Commands are shown without the
`/bin/zsh -lc '…'` wrapper Codex puts round them; connector calls are named `mcp__<server>__<tool>`
as Claude Code names them. A top-level `error` line is a notice, not the end of the turn: Codex
reports a reconnect that way and carries on.

### Antigravity

```
agy --print=<prompt> --output-format stream-json [--mode plan | --dangerously-skip-permissions]
    [--model <id>] [--effort low|medium|high] [--conversation <id>]
```

Parsed by `AntigravityStream`: reply text from `agent_response` steps, tools from `tool` steps
(`ACTIVE` when they start, `DONE` or `ERROR` with their output), `result` with status `SUCCESS` ends
the turn.

### GitHub Copilot

```
copilot --prompt=<prompt> --output-format json --no-color [permission flags]
        [--model <id>] [--reasoning-effort <level>] [--resume <id>]
```

Parsed by `CopilotStream`: reply text from `assistant.message_delta` only (`assistant.message`
repeats it, and `assistant.reasoning*` is the model thinking), tools from `tool.execution_start` and
`tool.execution_complete`, and a final `result` line that carries the session id and exit code.

## xBot's tools on a turn

Thread turns (and every turn, with Settings › Agents › **xBot tools in every chat**) carry
`TurnRequest.tools`: the running XBot binary, which each CLI starts as `XBot --mcp`, and the turn's
token, passed in the server's environment as `XBOT_TOOLS_TOKEN` (with `XBOT_TOOLS_SOCKET`) and in
the CLI's own environment too. Each CLI's flags, checked against its own help and docs
(Claude Code 2.1.296, Codex 0.162.1, Copilot 1.0.95, Antigravity 1.4.2):

| CLI | Attachment | Source |
| --- | --- | --- |
| Claude Code | `--mcp-config <file>` (`{"mcpServers":{"xbot":{"type":"stdio","command":…,"args":["--mcp"],"env":{…}}}}`), `--allowedTools mcp__xbot__*`, and `--settings <file>` with a `PreToolUse` hook (`matcher` `Bash\|mcp__.*`, exec form `XBot --hook`, `timeout` 660, `onFailure` `block`). Both files temporary, 0600, removed after the turn | `claude --help`; code.claude.com/docs: hooks (exit 0 allows, exit 2 blocks with stderr; 600 s default timeout; `onFailure` from 2.1.295), permissions (`mcp__<server>__*`), env-vars (stdio MCP calls have no per-request timer) |
| Codex | `-c mcp_servers.xbot.command="…"`, `-c mcp_servers.xbot.args=["--mcp"]`, `-c mcp_servers.xbot.env.XBOT_TOOLS_TOKEN="…"` (and `…SOCKET`), `-c mcp_servers.xbot.tool_timeout_sec=900` (the default 60 s is shorter than an approval's 10 minutes) | `codex mcp add --help`; developers.openai.com/codex/mcp (`[mcp_servers.<name>]`: `command`, `args`, `env`, `tool_timeout_sec`) |
| GitHub Copilot | `--additional-mcp-config <json>` (`{"mcpServers":{"xbot":{"type":"local","command":…,"args":["--mcp"],"tools":["*"],"env":{…},"timeout":900000}}}`, the shape `copilot mcp add --json` writes), plus `--allow-tool xbot` outside Full access | `copilot --help`, `copilot mcp add --help --json` |
| Antigravity | No per-run flag. `agy mcp add xbot -- <XBot> --mcp` once, the first time an Antigravity turn has the tools (remembered with the binary's path in `agentic.antigravityMCP`; added again if the app moves); Settings › Agents › xBot tools removes it (`agy mcp remove xbot`). The token reaches the server through the `agy` process's environment | `agy mcp add --help` |

Live-checked: a Claude Code turn and a Codex turn each called `xbot_crew` and `mac_apps` through
the debug app; Claude Code's hook blocked a `git push` the scripted approval refused. Copilot and
Antigravity attachment is checked by tests of their arguments only.

## Comparison

| | Claude Code | Codex | Antigravity | GitHub Copilot |
| --- | --- | --- | --- | --- |
| Binary | `claude` | `codex` | `agy` | `copilot` |
| Prompt | stdin | stdin (`-`) | `--print=…`, empty stdin | `--prompt=…`, empty stdin |
| Output | `stream-json` | `exec --json` | `stream-json` | `json` |
| Streams token by token | Yes | No, a message at a time | Yes | Yes |
| Resume | `--resume` | `exec resume <id>` | `--conversation` | `--resume` |
| Instructions | `--append-system-prompt` | `developer_instructions` | In the prompt | In the prompt |
| Model list | Opus, Sonnet, Haiku | `~/.codex/models_cache.json` | `agy models` | Default only |
| Effort levels used | low…max (+ Opus for Galaxy) | low…ultra | low, medium, high | low…max |
| Plan mode | Yes | Yes | No | No |
| Can edit | `acceptEdits` | `workspace-write` | Needs full access | `--allow-tool write` |
| Usage limits shown | Yes, from the turn's stream | Yes, from session logs | No | No |
| Abilities page | Yes | Yes | No | No |

## Usage and plan limits

The account menu's **Usage remaining** shows, per agent, what is left of the five-hour and weekly
windows and when each resets. **No credentials are read**: the numbers are what the agents
themselves report.

- **Claude Code** prints a `rate_limit_event` in every turn's stream; `ClaudeStream` reads the
  `five_hour` and `seven_day` windows from it. So Claude Code's usage appears after the first turn
  ("Run a turn to see Claude Code's usage."). The plan name (Claude Pro, Max, Team, Enterprise) comes
  from the `oauthAccount` block of `~/.claude.json`, which holds no secrets.
- **Codex** writes its limits into its session logs. `CodexUsage.latest()` reads the newest of
  `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` that has a `rate_limits` line — trying up to five
  files, and only the last 512 KB of each — taking `primary` as the five-hour window, `secondary` as
  the weekly one and `plan_type` as the plan (ChatGPT Plus, Pro, Team, Business, Enterprise).
  `Workspace.refreshCodexUsage()` runs when the account menu or Settings › Agents opens, and every
  minute while the menu is open.
- **Antigravity and Copilot** do not report limits, so they are not shown.

Each agent's last report is kept in the `usage` table of `xbot.sqlite`, so the menu has numbers
straight after a relaunch, with "Updated N min ago" beneath. The phone shows the same numbers on its
Home plan board, in each provider's own colours (`ProviderStyle` in `apps/ios/Sources/Accent.swift`:
Claude clay `#D97757`, Codex green `#10A37F`, Antigravity blue `#4285F4`, Copilot purple `#8957E5`).
On the Mac each agent's dot uses `Palette.agent`: Claude's clay, Codex in ink, Google blue, Copilot
purple.

## Adding a provider

One adapter per CLI. The design for the last two is
[2026-10-11-more-providers-design.md](superpowers/specs/2026-10-11-more-providers-design.md), which
also records what was looked at and not added (Gemini CLI, Cursor, OpenCode, Grok).

1. **Record real output first.** Run the CLI headless on a real turn and save its lines as a fixture
   in `apps/mac/Tests/XBotBrainTests/Fixtures/` (`<cli>-read-turn.jsonl` and so on), with paths
   scrubbed. Parsers are written against what the CLI actually prints, not its documentation.
2. **Add a case to `HarnessKind`**: display name, executable name, `arguments(for:)` (prompt,
   permission mapping, model, effort, resume, instructions), and whether it reads stdin, gives
   structured answers, needs instructions in the prompt, or needs full access to edit.
3. **Write its parser** beside the others (`MoreStreams.swift`), mapping tool names through
   `ToolNames.canonical`, ending in exactly one `.done` or `.failed`.
4. **Models**: a list command, a cache file, or default only — wired into
   `Workspace.refreshHarnesses()`.
5. **Test** the parser against the fixtures, then run the live suite on a signed-in Mac:

   ```
   cd apps/mac && XBOT_LIVE_HARNESS=1 swift test --filter Live
   ```

   `LiveHarnessTests` runs, per installed agent, a real read-only turn that must use a tool, find a
   word in a file and then resume the session to recall it; and a real two-step plan run to the end
   (which only an agent that makes plans can pass). It costs tokens and is off by default. Run it
   again after a CLI update, to see whether its stream still reads.

## Not built yet

The [redesign spec](superpowers/specs/2026-10-06-xbot-redesign-design.md) plans a second brain,
**`NativeBrain`**: a Swift tool-use loop against Anthropic, OpenAI, Google and Ollama over
`URLSession`, with keys in the Keychain, for people who have an API key or a local model rather than
an agent CLI. It is step 4 of the spec's build order. None of it exists in the app today: there is
no key field, no Ollama detection, and no per-token cost accounting. `BrainEvent` is already the
shape it would speak, so the transcript would not need to change.

The 1.x model router (`BOT_PROVIDER`, the engine's provider registry, Settings › Models) was removed
with the Docker/OpenBot engine; see [ADR-0009](decisions/0009-native-harness-redesign.md).
