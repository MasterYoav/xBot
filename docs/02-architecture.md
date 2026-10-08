# Architecture

xBot is one native macOS app. There is no server, no container runtime and no database process to
start. Decided in [ADR-0009](decisions/0009-native-harness-redesign.md); the full design, including
the parts not built yet, is the [redesign spec](superpowers/specs/2026-10-06-xbot-redesign-design.md).

## What runs

| Process | When | Talks to the app over |
| --- | --- | --- |
| `xBot.app` | always | — |
| An agent CLI (`claude`, `codex`) | for the length of one turn | its stdin, stdout and stderr |
| A bot's VM (Apple Containerization) | *not built yet* — while a bot with a computer is working | vsock |

Nothing listens on a network port.

## How a message becomes a reply

1. The composer calls `Workspace.send(_:in:)`. The user's message is saved to SQLite at once.
2. The workspace builds a `TurnRequest` — prompt, the chat's folder (a project folder, or xBot's
   Inbox folder), model, permission mode, and the CLI's session id from the last turn.
3. `HarnessBrain` starts the CLI in that folder with the person's login-shell `PATH`, writes the
   prompt to its stdin and closes it. The prompt never goes on the command line: a prompt starting
   with `-` would be read as a flag, and argv has a length limit.
4. Each JSON line the CLI prints becomes zero or more `BrainEvent`s (`ClaudeStream`,
   `CodexStream`). The stream ends with exactly one `.done` or `.failed` — if the CLI exits without
   saying which, its stderr becomes the failure.
5. The workspace folds events into the reply in progress (`[Part].apply`), which the transcript
   renders live. The session id is saved on the chat as soon as it arrives.
6. When the turn ends — finished, failed, stopped, or the app quitting — the reply is saved as one
   message. Stopping keeps what had arrived and marks it "Stopped."

## Storage

`~/Library/Application Support/xBot/`

- `xbot.sqlite` — `projects`, `chats`, `messages` (a message's parts are JSON). WAL mode.
- `Inbox/` — the working folder for chats that do not belong to a project.

API keys, when the native brain arrives, go in the Keychain and nowhere else.

## Permission modes

The composer's chip maps to each CLI's own flags; xBot does not add a sandbox of its own to a
harness running on the Mac.

| Mode | Claude Code | Codex |
| --- | --- | --- |
| Read only | `--permission-mode default` (anything needing approval is refused, since `-p` cannot ask) | `sandbox_mode="read-only"` |
| Can edit | `--permission-mode acceptEdits` | `sandbox_mode="workspace-write"` |
| Full access | `--permission-mode bypassPermissions` | `sandbox_mode="danger-full-access"` |

## Plan mode

With the Plan chip on, a message becomes three kinds of turn, all through the same `HarnessBrain`
([design](superpowers/specs/2026-10-08-plan-mode-design.md)):

1. **Planning** — always read-only (Claude Code `--permission-mode plan`, Codex
   `sandbox_mode="read-only"`), and the answer must follow `PlanSchemas.plan`: a one-sentence
   summary and steps, each with an imperative title and an "-ing" label. Claude Code returns it as
   `structured_output` on its result line; Codex as its last message (`SchemaTail` holds each
   message back until something else proves it was not the last). Both become `.structured`.
2. **One turn per step**, resuming the session, in the chat's own permission mode, answering in
   `PlanSchemas.step`: done or failed, a note, steps to add. The agent's "failed" is recorded and
   the loop goes on; a turn that itself fails (the CLI crashed, signed out, hit a limit) halts the
   plan, and Resume retries that step. At most 20 steps may be added.
3. **A closing sentence**, read-only, no schema.

xBot runs the loop itself because neither CLI exposes a to-do list when run headless, and because
running one turn per step means every tool row, time and failure belongs to a known step. The plan
is a `.plan` part of one assistant message, saved in place (`Store.replace`) on every change.
