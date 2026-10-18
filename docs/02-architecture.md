# Architecture

xBot is one native macOS app, plus an iPhone/iPad app that remote-controls it. There is no server
of ours, no container runtime and no database process to start. Decided in
[ADR-0009](decisions/0009-native-harness-redesign.md); the full design, including the parts not
built yet, is the [redesign spec](superpowers/specs/2026-10-06-xbot-redesign-design.md).

## What runs

| Process | When | Talks to the app over |
| --- | --- | --- |
| `XBot.app` | while you use it | — |
| An agent CLI (`claude`, `codex`, `agy`, `copilot`) | for the length of one turn | its arguments, stdin, stdout and stderr |
| A login shell | while a terminal window or tab is open (on the Mac or from the phone) | a pseudo-terminal |
| `XBot --automations-tick` | once a minute, only if **Run when xBot is closed** is on and the app isn't open | the same SQLite file |
| A bot's VM (Apple Containerization) | *not built yet* | — |

The app listens on one TCP port, and only after an iPhone or iPad has been paired: the local lane
of the [remote](14-iphone-and-ipad.md), advertised over Bonjour and accepting only TLS with a
pairing key. Unpair the last device and the listener stops. The iCloud lane listens on nothing; it
reads and writes records in your own CloudKit database.

## How a message becomes a reply

1. The composer calls `Workspace.send(_:in:)`. The user's message is saved to SQLite at once.
2. The workspace builds a `TurnRequest`: the prompt, the chat's folder (a project folder, or xBot's
   Inbox folder for loose chats), model, reasoning effort, permission mode, the agent's
   instructions when the chat is with a crew member, and the CLI's session id from the last turn.
3. `HarnessBrain` starts the CLI in that folder with the person's login-shell `PATH`
   (`HarnessLocator`). Claude Code and Codex get the prompt on stdin, which is then closed;
   Antigravity and Copilot only take it from a flag, attached as `--print=…` / `--prompt=…` so a
   prompt starting with `-` can't be read as an option.
4. Each line the CLI prints becomes zero or more `BrainEvent`s (`ClaudeStream`, `CodexStream`, and
   `MoreStreams` for the other two). The stream ends with exactly one `.done` or `.failed`; if the
   CLI exits without saying which, its stderr becomes the failure.
5. The workspace folds events into the reply in progress (`[Part].apply`), which the transcript
   renders live. The session id is saved on the chat as soon as it arrives.
6. When the turn ends (finished, failed, stopped, or the app quitting) the reply is saved as one
   message. Stopping keeps what had arrived and marks it "Stopped."

How each CLI is run, its models and reasoning levels are in
[Agents and providers](04-model-providers.md).

## Storage

`~/Library/Application Support/xBot/`

- `xbot.sqlite`: `projects`, `chats`, `messages` (a message's parts are JSON), `usage` (the plan
  limits last read), `agents` (the crew, with each one's manager) and `automations`. WAL mode,
  schema version 6, migrated forward in place.
- `Inbox/`: the working folder for chats that don't belong to a project.
- `Experience/<agent-id>.json`: what each agent has learnt (below). Kept beside the library, so a
  library in memory (tests, or one that couldn't open) gets a temporary folder of its own.

Notes live in the project itself, as Markdown in `<project>/notes/`, so they travel with it.
Settings and appearance are in the app's user defaults. Pairing keys are in the Keychain. Nothing
is kept on a server.

## Permission modes

The composer's chip maps to each CLI's own flags. xBot adds no sandbox of its own around a CLI
running on the Mac: **Full access** means the agent can do what you can.

| Mode | Claude Code | Codex | Antigravity | Copilot |
| --- | --- | --- | --- | --- |
| Read only | `--permission-mode default` (anything needing approval is refused, since `-p` can't ask) | `sandbox_mode="read-only"` | `--mode plan` | no flag: reads allowed, anything else denied |
| Can edit | `--permission-mode acceptEdits` | `sandbox_mode="workspace-write"` | `--dangerously-skip-permissions` (headless, its edit mode refuses even to read; the composer says so) | `--allow-tool write` |
| Full access | `--permission-mode bypassPermissions` | `sandbox_mode="danger-full-access"` | `--dangerously-skip-permissions` | `--allow-all-tools --allow-all-paths` |

## Plan mode

With the Plan chip on, a message becomes three kinds of turn, all through the same `HarnessBrain`
([design](superpowers/specs/2026-10-08-plan-mode-design.md)). Claude Code and Codex make plans;
the other two can't answer to a schema, so the chip is off for them.

1. **Planning**: always read-only (Claude Code `--permission-mode plan`, Codex
   `sandbox_mode="read-only"`), and the answer must follow `PlanSchemas.plan`: a one-sentence
   summary and steps, each with an imperative title and an "-ing" label. Claude Code returns it as
   `structured_output` on its result line; Codex as its last message (`SchemaTail` holds each
   message back until something else proves it was not the last). Both become `.structured`.
2. **One turn per step**, resuming the session, in the chat's own permission mode, answering in
   `PlanSchemas.step`: done or failed, a note, steps to add. The agent's "failed" is recorded and
   the loop goes on; a turn that itself fails (the CLI crashed, signed out, hit a limit) halts the
   plan, and Resume retries that step. At most 20 steps may be added.
3. **A closing sentence**, read-only, no schema.

xBot runs the loop itself because no CLI exposes a to-do list when run headless, and because
running one turn per step means every tool row, time and failure belongs to a known step. The plan
is a `.plan` part of one assistant message, saved in place (`Store.replace`) on every change.

## The crew

An agent ([design](superpowers/specs/2026-10-10-agents-workplace-design.md)) is a row in `agents`:
name, role, instructions, a pixel avatar, a CLI and model, a home project, and a manager. A chat
with an agent is an ordinary chat with `agent_id` set; on each turn, `instructions(for:)` tells
the CLI who it is, who it reports to and who is on its team, then adds its own instructions
(Claude Code and Codex take these as a system or developer prompt; the other two get them ahead of
the prompt).

**Who reports to whom.** `managerID` nil means the agent reports to the person; only HeadMaster,
the founding agent and CEO, does. `OrgChart` (in `XBotWorld`) builds the tree, refuses loops and
suggests a manager from a role title: executives (CTO, CFO, CMO, CPO, COO, VP, Head of…) report to
HeadMaster, leads to their department's executive, everyone else to their department's lead or
executive; product falls back to engineering, and anyone unmatched goes to HeadMaster. **Organise**
applies the suggestions to everyone; the person can override anyone. Letting a manager go moves
their team up to the next manager, and Undo restores it.

**Hand-offs.** A manager's reply can contain fenced `handoff` blocks naming a member and a task.
When the turn ends, `handOff(from:reply:)` starts a chat with each named member who is below that
manager (at any depth) and sends them the task "From <manager>: …". A name outside the team, or not
on the crew, is refused with a notice in the manager's reply. When the member's turn finishes,
`reportBack` adds a notice to the manager's chat with the gist of what they did.

**Experience.** From Google's [Harness²](https://github.com/google-research/harness2): each agent
keeps evidence-backed lessons, *cue → lesson*, for later tasks (`ExperienceStore`, in
`XBotCore/Agentic/Experience.swift`). A `Lesson` has a cue, the lesson, a confidence (low, medium,
high), one line of evidence, when it was learnt and how many turns it was given to (`uses`). The
agent writes them itself, at the end of its own turn, through the `xbot_remember` tool — one
reflection per task and no second model run; `remember` replaces a lesson with the same cue
(ignoring case, spacing and punctuation). On each turn, `instructions(for:toolsAttached:)` adds
the agent's `selection` under *"What you've learnt (from earlier tasks; apply when the cue fits):"*,
one line each (*"- When <cue>: <lesson> (high confidence)"*; the evidence stays out): ranked by
confidence, then the newest, then the cue, at most 12 lines and 1,500 characters, skipping a line
too long for what's left rather than stopping there. Each one sent counts a use. When the turn has
xBot's tools attached, the instructions end with the reflection: *"When you finish a task, if you
learnt something general that would help next time (not task-specific facts), call the
xbot_remember tool once with the cue, the lesson, your confidence and the evidence."* When the
library opens, `decay` drops low-confidence lessons more than 30 days old that were never used.
The person reads, rewords and forgets them in the agent editor (`Workspace+Experience.swift`;
forgetting returns an Undo).

**The world.** `WorldStage` (in `XBotWorld`, shared with the phone) draws the crew in one of five
pixel-art settings, in tiers by rank: HeadMaster on top, each team below its manager. Each agent
has a slot of its own, walks within it and sits at its desk while one of its chats is running, with
a bubble saying what it's doing (`activity(in:)`).

## Automations

An automation ([design](superpowers/specs/2026-10-11-automations-design.md)) is a trigger (Run now,
hourly, daily, weekdays, weekly) and steps in plain words, each with an app (Mail, Calendar,
Reminders, Notes, Messages and others, a connector, or "anything"). xBot compiles the steps into
one turn with full access, run as a chat tagged with the automation. Before a run starts it is
claimed in the database, so the app and the background helper never both run one. The helper is a
LaunchAgent (`dev.xbot.automations`) that starts xBot's own binary headless every minute, only
while the toggle is on.

## The remote

The [iPhone and iPad app](14-iphone-and-ipad.md) is a remote; agents never run on the phone.

```
XBotRemote (Foundation + Network, macOS and iOS)   the wire: versioned Codable messages
  ├── Mac: RemoteService + RemoteHost (XBotCore)    pairing, lanes, answers through Workspace
  └── iOS: RemoteClient                             a mirror of the Mac's workspace
Lanes (both carry the same messages)
  ├── local   Bonjour "_xbot._tcp", TLS with the pairing key (PSK), length-prefixed JSON frames
  └── iCloud  CloudKit private database, container iCloud.dev.xbot, batches sealed with the key
```

Commands from the phone go through the same `Workspace` methods the Mac's window calls, so the two
can't drift apart. The Mac sends changes as they happen; nothing is polled on the local lane. On
the iCloud lane both sides read the mailbox every 2 seconds while a phone is attached (the Mac every
15 seconds otherwise), because pushes are best-effort. While a phone is attached or a turn runs, the
Mac holds a power assertion against idle sleep.

## Modules

```
XBotApp ── XBotUI ── XBotCore ─┬─ XBotBrain     the CLIs: locating, running, parsing (Foundation only)
                               ├─ XBotRemote    the wire to the phone (also built for iOS)
                               ├─ XBotWorld     avatars, worlds, org chart, stage (also iOS)
                               └─ XBotMarkdown  Markdown documents as blocks (iOS's editor)
```

Ownership and tests are in [The Mac app](05-mac-app.md).

## Performance

Every looping animation (the wallpaper, the world, sprites, the effort knob) runs through the
motion gate and stops while xBot isn't the active app. On the installed release build, paired with
a phone and in the background, xBot used 0.01% CPU on average over a minute and 63 MB of memory.
