# xBot redesign: native bots, each with an optional computer

Date: 2026-10-06 · Status: approved in brainstorming, awaiting spec review

## Intent

**What the user said.** Redesign xBot after [monocode](https://github.com/hardbeat920/monocode),
whose experience they love. No more Docker, no more outside services. Add notes and agentic
project chats. Keep xBot's core idea: bots are xBot's own, and — unlike monocode's Monos — a bot
can have its own machine, like Grok's agent computer but native. The user decides per bot. Delete,
move and change anything. Make it an app people pay for.

**Decided in brainstorming.**

1. Intelligence: **both, harness-first.** Drive installed agent CLIs on the user's subscriptions
   (as monocode does), and ship a built-in native agent loop for API keys / Ollama so a
   non-developer needs no installs.
2. Audience: **everyone.** A project is **any folder**; git features appear only for repos.
3. Machine v1: **shell + files + browser with a live screen** and take-over.
4. Approach **A**: xBot hosts an MCP tool server that bridges every bot to its machine.
5. Floor: **macOS 26, Apple silicon** (required by Apple `Containerization`).
6. Pricing: free tier + **xBot Pro, $59 one-time** with a year of updates.

**Success.** A user installs the DMG, connects a brain without a terminal, creates a bot, flips
"Give this bot a computer", and watches it browse and run commands in its own Linux VM — while
chats, notes and project work feel as fast and direct as monocode.

## What monocode is (reference)

Studied at `9ccfc09` (v0.8.0, Tauri + React + Rust, ~56k lines):

- No model of its own: spawns installed CLIs (Claude Code, Codex, Cursor, Grok Build, OpenCode,
  …) on the user's logins and parses their streams (`src-tauri/src/harness.rs`).
- Projects → chat sessions as tabs and split panes, per-session git worktrees, checkpoints with
  Undo All / Keep All, a Changes rail with commit.
- **Monos** (`mono.rs`): persistent personas, not tied to a project, stored in app data as
  `SOUL.md`, `MEMORY.md`, `habits.json`, `memory/`. Kept out of repos so a pull request cannot
  rewrite a soul.
- Notes in SQLite with tags, images, source session (`notes.rs`); automations on schedules or
  events (`automations.rs`); a Quick Composer panel; `/operator` gives an agent a local CLI to
  drive the app.
- What it lacks, and xBot adds: a machine per bot, a native agent loop for people without a CLI,
  and a native macOS client.

We take ideas and UX, not code: monocode is MIT but Rust/TypeScript; xBot is Swift.

## Architecture

**One app, no daemons, no services.** `xBot.app` is Swift/SwiftUI. No Node, no Postgres, no
Docker. The only extra processes are each machine-enabled bot's VM (while awake) and the
`xbot-mcp` helper a harness spawns.

**Storage.**

- One SQLite database in Application Support (system `SQLite3`, no new dependency): projects,
  chats, messages, notes, habits, audit.
- Bot identity as files: `Bots/<id>/SOUL.md`, `MEMORY.md`, `memory/*.md`, `machine/` (VM disk).
  Readable and portable; the user still never needs to open them.
- Keys in the Keychain, through the existing `KeychainSecretStore` / `ProviderKeyVault`.

**Modules.**

| Module | Responsibility | Source |
| --- | --- | --- |
| `XBotCore` | models, SQLite store, Keychain, bot files, license | keeps keychain, provider catalog, markdown; drops engine state |
| `XBotBrain` | `Brain` protocol; `HarnessBrain`, `NativeBrain`; `BrainEvent` stream | new; replaces `XBotEngine` |
| `XBotMachine` | `MachineDriver` protocol; Containerization driver; exec, files, CDP browser, screencast | new; replaces `XBotRuntime` |
| `XBotTools` | tool registry, MCP server, `xbot-mcp` helper, policy gate, audit writes | new; absorbs `ActionPolicy`, `AuditEvent` |
| `XBotUI` | shell, chats, notes, bots, inspector, settings | keeps `DesignSystem`, `Composer`, markdown views |
| `XBotOnboarding` | welcome → connect a brain → meet your first bot | rewritten |

**Data model.**

- `Project` — security-scoped folder bookmark; `isGitRepo` derived.
- `Bot` — name, avatar, soul, memory, `brain: .harness(cli, model, effort) | .native(provider, model)`,
  `machine: MachineConfig?` (`shareProject: off | readOnly | readWrite`).
- `Chat` — optional project (none = Inbox), one bot, optional worktree, folder, title.
- `Message` — role, content blocks (text, tool call, tool result, image), checkpoint ref.
- `Note` — title, markdown body, tags, optional source chat.
- `Habit` — bot, prompt, schedule, target chat or new chat, enabled, last/next run.
- `AuditEntry` — append-only: time, bot, chat, tool, argument summary (secrets reduced to length),
  decision, outcome.

## Bots

A bot is soul + memory + brain + optional machine. Soul and memory load into every turn. A bot
changes its memory only through `memory.write` / `memory.append` tools, never raw file access to
its own folder. Habits run a prompt on a schedule, post the result into a chat and send a
notification; a habit missed while the Mac slept runs once on wake if within its grace window.

## Brains

Both brains emit `AsyncThrowingStream<BrainEvent>`:
`.textDelta`, `.toolCall`, `.toolResult`, `.usage`, `.done`, `.error(BrainError)`. The UI never
knows which brain it shows.

**`HarnessBrain`** spawns a CLI on the Mac in the chat's working directory.

- Claude Code: `claude -p --input-format stream-json --output-format stream-json --verbose
  --mcp-config <generated> --append-system-prompt <soul + memory>`, session resumed with
  `--resume <id>`.
- Codex: `codex exec --json`, MCP server injected with `-c mcp_servers.xbot=…`, resumed by thread id.
- Sub-project 1 ships these two. Grok Build, OpenCode, Cursor, Gemini, etc. follow as one adapter
  file each.
- Detection: probe known install paths and the login shell's `PATH`; check login with the CLI's
  own status command. Missing or logged out → onboarding offers the native path or an in-app
  explanation. It never tells the user to run a command.
- Permission mode maps to the CLI's own flags (supervised / auto-edit / full), shown as the
  composer chip.

**`NativeBrain`** is a Swift tool-use loop against Anthropic, OpenAI, Google and Ollama
(`URLSession`, streaming), keys from the Keychain, the same tool registry, a context budget that
summarises older turns. Default model per provider comes from `ModelProviderCatalog`.

## Tools

One registry, two transports:

- **MCP (for harnesses).** `xbot-mcp` is a small executable inside the app bundle. The generated
  MCP config launches it with a per-chat token; it speaks MCP over stdio and relays to the running
  app over a Unix domain socket in the app's container directory (mode 0600). Token mismatch =
  refused. No TCP ports.
- **In-process (for `NativeBrain`).**

Tool sets:

| Set | Available | Tools |
| --- | --- | --- |
| `notes` | always | list, read, write, search |
| `memory` | always | read, write, append |
| `xbot` | opt-in per chat (`/operator`) | chats.start, chats.list, chats.read, bots.list |
| `shell` | bot has a machine | run (timeout, cwd), background jobs |
| `files` | bot has a machine | read, write, list, upload to Mac (save dialog), download from Mac (open panel) |
| `browser` | bot has a machine | open, click, type, scroll, screenshot, read page text |

**Policy gate.** Every call is classified (read / write / execute / network / outbound-message)
and resolved per bot: allow, ask, deny. "Ask" shows an inline approval card in the chat. Every
call writes an `AuditEntry` before the result returns.

## The machine

Apple `Containerization` (Swift package `apple/containerization`), each container its own
lightweight VM. Off by default; the bot's settings have "Give this bot a computer".

- **Image.** Debian slim with Chromium (run with `--headless=new`, which supports screencast and
  input dispatch, so no X server) and a small `xbot-agentd` (exec, files, CDP proxy). Published by us as an OCI image; pulled once, on first
  enable, with a progress bar (~400 MB). Kernel and init image come with the Containerization
  release.
- **Disk.** Persistent ext4 image under `Bots/<id>/machine/`; survives restarts, deleted with the
  bot.
- **Project sharing.** The chat's project folder shared at `/workspace` over virtiofs:
  off, read-only (default) or read-write, per bot.
- **Lifecycle.** `MachineDriver` state machine: `absent → pulling → stopped → booting → running →
  stopping`, plus `failed(reason)` with one fix-it action. Boots on first tool call, stops after
  10 idle minutes.
- **Network.** NAT outbound only. Nothing listens on the Mac's interfaces; the app talks to the VM
  over vsock.
- **Browser and live screen.** Chromium driven over CDP through `xbot-agentd`. The inspector's
  Machine tab renders `Page.startScreencast` JPEG frames; **Take over** pauses the bot's browser
  tools and forwards the user's mouse and keys via `Input.dispatchMouseEvent` /
  `Input.dispatchKeyEvent`; **Hand back** resumes. Logins made there persist on the bot's disk.
- **Terminal pane.** A read-along view of the bot's shell sessions in the inspector. It is a
  window into the bot's machine, not a tool the user is asked to use.

## UX

Follows monocode's layout, rebuilt in SwiftUI to `docs/08-design-system.md`.

- **Sidebar** — tabs *Chats* (grouped by project, folders, Inbox), *Notes*, *Bots*. Footer: bot
  status (sleeping / working / computer on) and the Pro badge or upgrade card.
- **Center** — chat tabs; panes split right or down. Composer chips: bot, model, effort,
  permission mode. `/` skills and commands, `@` files and notes, drag-in images and files.
- **Inspector** (right, contextual) — *Changes* (diff, commit; git projects only), *Machine*
  (live screen, Take over, terminal pane, machine state), or the open *Note*.
- **Quick Composer** — global hotkey panel; ask any bot, reply lands in a new Inbox chat.
- **Notes** — markdown editor (TextKit 2), tags, images. "Save as note" on any message.
- **Checkpoints** — before each turn. Git repos: a stash-style ref. Plain folders: APFS clones of
  files the turn touched. Undo All / Keep All / Review per turn.
- **Worktrees** — git projects can give a chat its own worktree; offered, never required.

## Onboarding

Three screens: **Welcome** → **Connect a brain** (detected CLIs shown as ready, or paste a key, or
use Ollama if running) → **Meet your first bot** (name, soul from a template, optional "give it a
computer", which starts the image pull in the background). No system check for Docker or Colima;
the only hard requirement is macOS 26 on Apple silicon, enforced by the deployment target.

## Business

- **Free:** unlimited chats and notes; 2 bots; no machines; no habits.
- **xBot Pro — $59 one-time**, a year of updates included; the app keeps working after.
  Unlimited bots, machines, browser + live screen, habits.
- **License:** sold through Paddle or Lemon Squeezy; the key is an Ed25519-signed payload
  (email hash, tier, update-until date) verified offline against a public key in the app. No
  account, no activation server, no phone-home.

## Invariants (replace the list in CLAUDE.md)

1. No terminal for the user, ever.
2. Keys in the Keychain only — never in SQLite, files, logs, errors, crash reports.
3. Audit trail append-only; nothing in the app deletes a row.
4. A secret's value is never echoed; record presence and length.
5. **No listening ports.** Unix socket (0600) for the MCP relay, vsock for the VM.
6. Deleting a bot is confirmed once and deletes its machine disk and browser profile.
7. Degrade honestly: CLI logged out, VM failed, provider down, Ollama absent — say so, offer one
   button.

## What gets deleted

- `engine/` entirely (OpenBot fork), `scripts/dev-db.sh`, engine CI jobs and the pinned engine
  manifest.
- `XBotRuntime` (Docker, Colima, engine image/manifest/port code), `XBotEngine` HTTP/SSE client,
  `AdminWebView`, plugin admin.
- Docs: `03-openbot-fork`, `07-container-runtime`, `env-mapping`; ADRs 0001, 0003, 0007, 0008 marked
  *Superseded by 0009*. New ADR 0009 records this redesign; ADR 0010 the machine design; ADR 0011
  pricing and licensing.
- `NOTICE` keeps crediting OpenBot only while any OpenBot-derived code ships; once `engine/` is
  gone, the credit moves to a "previously based on" line in `CHANGELOG.md`. Monocode credited in
  `NOTICE` for design inspiration.
- `CLAUDE.md` rewritten for the new architecture.

## Build order (each its own plan)

1. **Shell + projects + harness chats** — store, sidebar, tabs/panes, composer, `HarnessBrain`
   (Claude Code, Codex), checkpoints, worktrees, Changes inspector.
2. **Notes** — store, editor, `notes.*` tools, `xbot-mcp` relay.
3. **Bots** — soul, memory, habits, Quick Composer, onboarding rewrite.
4. **Native brain** — Anthropic, OpenAI, Google, Ollama tool loop.
5. **Machine** — Containerization driver, image, `xbot-agentd`, `shell.*`, `files.*`.
6. **Browser + live screen** — CDP, screencast inspector, take over.
7. **Cleanup + licensing** — delete engine and old modules, docs and ADRs, Pro license gate.

## Testing

- TDD for logic: SQLite store, policy gate, `BrainEvent` parsers (fed recorded stream-json
  fixtures from each CLI), native tool loop (stubbed `URLProtocol` with injected fixtures, never
  class-level globals), `MachineDriver` state machine (fake driver), license verification,
  checkpoint restore.
- One real-VM integration test, behind `XBOT_VM_TESTS=1`; CI runners cannot nest virtualisation.
- Verification stays `swift build --build-tests && swift test`; CI must run on a macOS 26 image.

## Open risks

- **Harness stream formats change** without notice. Mitigation: one adapter per CLI, fixture tests,
  and a visible "this CLI version is not supported yet" state.
- **Containerization API churn** (pre-1.0). Mitigation: everything behind `MachineDriver`.
- **Image distribution.** We host an OCI image (GHCR). If it cannot be fetched, the machine shows
  `failed` with Retry; everything else keeps working.
- **Trademark** (ADR 0006) is unchanged and still unresolved.
