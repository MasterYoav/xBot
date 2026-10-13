# Security

xBot runs agent CLIs on your Mac, as you, in folders you choose, and lets a paired iPhone or iPad
drive all of it from elsewhere. It adds no sandbox of its own. What an agent can do is decided by
the permission mode you pick and enforced by the CLI itself; what a paired device can do is
everything you can do sitting at the Mac, a shell included.

This page says what xBot does, what it reads and stores, how the remote is protected, and what is
not built yet, checked against the code. The architecture is in
[Architecture](02-architecture.md), the remote in [The iPhone and iPad app](14-iphone-and-ipad.md).

## Running an agent

Each turn is one process of the agent CLI (`HarnessBrain`), started in the chat's folder (a project,
or `~/Library/Application Support/xBot/Inbox/` for loose chats) and ended when the turn ends. Stop
sends it `SIGTERM`.

- **Environment.** The CLI inherits xBot's own environment with two changes (`HarnessLocator`):
  `PATH` is replaced by your login shell's `PATH` (read once by running `$SHELL -l -i -c` with a
  five-second limit, plus the usual install folders), and every variable starting `CLAUDECODE` or
  `CLAUDE_CODE_` is removed.
- **The prompt.** Claude Code and Codex read it on stdin, which is then closed. Antigravity and
  Copilot can't, so it goes on their flag, attached as `--print=…` / `--prompt=…`. For those two the
  prompt is in the process's arguments for the length of the turn, where other processes running
  as you can see it (`ps`). The agent's instructions are arguments for all four (Claude Code's
  `--append-system-prompt`, Codex's `developer_instructions`, and ahead of the prompt for the other
  two).
- **Schemas.** When a turn's answer must follow a JSON schema (plans, drawn wallpapers), Codex reads
  the schema from a file in the temporary folder, removed when the turn ends. It holds the schema
  only, never the prompt.
- **Sign-in.** xBot never signs in to anything. Each CLI uses its own sign-in, wherever that CLI
  keeps it.

### Permission modes

The composer's chip maps to each CLI's own flags (`HarnessKind.arguments`). **Can edit** is the
default (Settings › General › Default permission).

| Mode | Claude Code | Codex | Antigravity | Copilot |
| --- | --- | --- | --- | --- |
| Read only | `--permission-mode default` | `sandbox_mode="read-only"` | `--mode plan` | no flag: reads allowed, anything else denied headless |
| Can edit | `--permission-mode acceptEdits` | `sandbox_mode="workspace-write"` | `--dangerously-skip-permissions` | `--allow-tool write` |
| Full access | `--permission-mode bypassPermissions` | `sandbox_mode="danger-full-access"` | `--dangerously-skip-permissions` | `--allow-all-tools --allow-all-paths` |

- Planning turns in Plan mode are always read-only, whatever the chip says (Claude Code
  `--permission-mode plan`, Codex `read-only`). Plan mode is offered for those two only.
- **Antigravity's "Can edit" is full access.** Run headless, its edit mode refuses even to read,
  so xBot gives it `--dangerously-skip-permissions`. The composer says so: "Antigravity can only
  edit with full access, so “Can edit” runs with full access."
- The sandboxing in these modes is the CLI's (Codex's `sandbox_mode`, Claude Code's permission
  modes), not xBot's. xBot doesn't check what a CLI does with them.
- **Full access means full access.** The agent can do anything you can on this Mac: read any file
  you can read, run any command, use your network, your Git credentials, your signed-in tools.

### Things that start turns without you typing

- **Hand-offs.** A manager's reply can contain fenced `handoff` blocks. xBot acts only on names in
  that manager's own team (below them, at any depth); anything else is refused with a notice in the
  manager's reply. Each accepted hand-off starts a new chat with the member, in the manager chat's
  project, in **Can edit** at most and never in more than the manager's own chat has: from a Read
  only chat the member works Read only, and from a Full access chat it gets Can edit
  (`Handoff.mode`). Antigravity can only edit with full access, so an Antigravity member stays Read
  only unless the manager's chat is in Full access, and the manager's reply says so in a notice.
- **Automations** run with **full access**, always (`Workspace+Automations`); the editor says
  "Automations run with full access: they can do anything you can on this Mac." They run while
  xBot is open. **Run when xBot is closed** (off by default) installs a LaunchAgent,
  `~/Library/LaunchAgents/dev.xbot.automations.plist`, which starts xBot's own binary with
  `--automations-tick` every minute; it runs what's due and quits, and does nothing while the app
  is open. Turning the toggle off unloads and removes it. macOS asks once per app the first time
  an automation controls Mail, Calendar and so on.
- **Run** on a shell code block in a reply types it into the chat's terminal and presses Return.
  It needs your click, but it doesn't ask again: what you click is what runs. Only blocks tagged
  as shell (`bash`, `sh`, `zsh` and similar) get the button.

## What xBot reads of the CLIs' own files

For usage, the profile page, the model lists, the Abilities page and the welcome tour. No credential
or token file is read: not Codex's `auth.json` (the tour checks only that it **exists**), not Claude
Code's Keychain item, nothing of Antigravity's or Copilot's.

| File | What for | What is used |
| --- | --- | --- |
| `~/.claude.json` | Plan, "Signed in", Claude Code's MCP servers | The whole file is parsed; only `oauthAccount` (its presence, and `organizationType` for the plan) and `mcpServers` (your user ones and the open project's) are looked at. For a server, its name and its command line or URL are shown, with what looks like a secret masked (below) |
| Claude Code's stream | Usage left | Its `rate_limit_event` lines, as each turn runs |
| `~/.claude/projects/**/*.jsonl` | Profile | Read incrementally: tokens per day, tasks, tool, skill and effort counts, project paths. No message text is kept |
| `~/.codex/sessions/…/rollout-*.jsonl` | Profile, usage left | As above; for limits, the last 512 KB of the newest five logs |
| `~/.codex/models_cache.json` | Codex's model list | Model names and their reasoning levels |
| `~/.codex/config.toml` | Abilities | Configured MCP servers and switched-off skills. It is also **written** (below) |
| `~/.claude/skills`, `~/.codex/skills`, a project's `.claude/skills`, plugin folders | Abilities | Each skill's `SKILL.md` |

Antigravity's model list comes from running `agy` itself. The tour's agents step also runs
`codex login status` (only its exit code is used) when `auth.json` isn't there, because Codex can
keep its login in the Keychain instead.

**An MCP server's command line or URL can hold a token**, so before it's shown on the Abilities page
or sent to a paired phone, xBot masks what looks like one (`SecretRedaction`): a URL's user name and
password and every query value, the value after a flag or a `NAME=` whose name has `token`, `key`,
`secret`, `password` or `auth` in it (`--token …`, `--api-key=…`, `GITHUB_TOKEN=…`), and the word
after `Bearer`. It's a pattern match, not a guarantee: a secret passed as a bare argument with no
name in front of it is shown as it is.

**Abilities changes go through the CLIs.** Plugins and MCP servers are switched, installed and
removed with the CLIs' own commands (`claude plugin …`, `claude mcp add|remove`, `codex plugin …`,
`codex mcp add|remove`). Codex has no command to switch a plugin, MCP server or skill off, so xBot
changes one `enabled` line in `~/.codex/config.toml`, has Codex load it, and puts the file back
exactly as it was if Codex refuses it. Adding a skill copies its folder into `~/.claude/skills` or
`~/.codex/skills`. Abilities manages Claude Code and Codex only. An MCP server or plugin you add is
code the agent will run as you; xBot doesn't vet it.

## What xBot stores

| Where | What |
| --- | --- |
| `~/Library/Application Support/xBot/xbot.sqlite` | Projects (paths), chats, every message with its tool rows, the crew, automations, usage last read. Not encrypted: protected by your account and FileVault, like the CLIs' own logs |
| `…/xBot/history.sqlite` | The profile's counts, derived from the CLIs' logs; rebuilt if deleted |
| `…/xBot/Inbox/` | The working folder for chats without a project |
| `…/xBot/profile.png` | The account picture, if you set one |
| `<project>/notes/*.md` | Notes, in the project |
| User defaults (`dev.xbot.app`) | Settings, appearance, the Mac's remote id, the paired devices' names and installation ids, the identities of outstanding invites, iCloud change tokens and replay marks; the welcome tour's state (`onboarding.completedVersion`, `onboarding.skipped`, `onboarding.reminderDismissed`, and which of Desktop, Documents and Downloads it has asked for, `onboarding.foldersAsked`) |
| Keychain | Pairing keys, nothing else (below) |
| `~/Library/LaunchAgents/dev.xbot.automations.plist` | Only while **Run when xBot is closed** is on |

xBot itself makes no web requests: no telemetry, no crash reporting, no account. The network
traffic it causes is the CLIs' own, `git` and `gh` when you use the Changes inspector, CloudKit for
the remote's iCloud lane, and Sparkle once updates are configured.

## The Keychain

The only secrets xBot holds are pairing keys. There are no API keys: the native brain that would
take them isn't built.

- **On the Mac:** a generic password per device, service `dev.xbot.remote.pairing`, account the
  key's identity (a UUID), value the 256-bit key in base64, accessible
  `AfterFirstUnlockThisDeviceOnly` (`KeychainSecretStore`, `KeychainPairingSecrets`).
- **On the phone:** the whole invite (Mac id, name, address, port and key) as one item, service
  `dev.xbot.mobile.pairing`, also `AfterFirstUnlockThisDeviceOnly`, so it isn't synced or restored
  to another device.
- **Debug builds only:** `XBOT_PAIRING_SECRETS_FILE` makes the Mac keep pairing keys in a JSON file
  instead (`FilePairingSecrets`), so a rebuilt, re-signed debug binary doesn't trigger a Keychain
  password prompt every launch. The code that reads that variable is inside `#if DEBUG` in
  `XBotApp.swift`; the type is compiled into every build, but nothing in a release build creates
  one.

## The remote

A paired device has the same power as sitting at the Mac. It can start chats in any mode
including Full access, read and write files in projects, commit and push, add any folder on the Mac
as a project (it can browse the Mac's folders to find one), hire agents, add MCP servers, install
plugins, switch the automations helper on, and open a login shell. Treat pairing as handing over
the Mac.

### Listening

Nothing listens until you ask to pair. Pressing **Pair an iPhone or iPad…** starts one TCP
listener on a port the system picks, advertised over Bonjour as `_xbot._tcp` with the Mac's id and
the protocol version in its TXT record (and the Mac's name as the service name). At launch it
starts again only if a device is paired. Removing the last device, or closing the pairing sheet
with nothing paired, stops it. The iCloud lane listens on nothing.

### Pairing

The QR code is an `xbot://pair?v=…` link holding, in base64 JSON, the Mac's id and name, its
Wi-Fi/Ethernet IPv4 address and port when known, and **the pairing key itself**: a UUID identity
and 256 random bits (`PairingKey.generate`, `SecRandomCopyBytes`). Whoever sees the code, or a
photo or screen recording of it, while it's still valid has the key and can pair, if they use it
before your device does. The sheet says so: "The code pairs one device and works for 10 minutes,
until you close this. Keep it to yourself: it's the key to this Mac."

A code is an **invite**, and it's short-lived (`RemoteService.invite`, `withdraw`):

- **Until the sheet closes.** Closing or cancelling the sheet, however it closes, withdraws an
  invite nobody used: its key leaves the Keychain, the listener restarts without it, and the
  iCloud lane stops reading mail sent with it.
- **For 10 minutes at most.** Left open, the code expires on its own and the sheet offers a new one.
- **Not across a relaunch.** Outstanding invites are noted in user defaults (identities only); at
  the next launch their keys are removed.
- **Once.** The phone makes an installation id when it pairs and sends it, inside the encrypted
  channel, in its hello. The first installation to say hello with an invite's key becomes the
  device, and the invite is used up. From then on the Mac refuses that key from any other
  installation, on both lanes. (A device paired before this was recorded claims its key with its
  next hello.)

The Mac accepts only the keys of paired devices and of live invites. Any other key in the Keychain
under `dev.xbot.remote.pairing` (an invite left by an older build, say) opens nothing.

On the phone, scanning the code, pasting the link or opening it saves it to the Keychain and
connects. Opening a pairing link while already paired asks first ("Replace the pairing with …?"),
so a link someone sends you can't silently point your phone at their Mac. A device appears in
Settings › Devices the first time it says hello.

### The local lane

TLS 1.2 with the pairing key as a pre-shared key, cipher suite `TLS_PSK_WITH_AES_128_GCM_SHA256`
(`LocalTLS`). There are no certificates: a peer without one of the keys can't complete the
handshake. The listener's PSK selection block picks the key for the identity the phone offers and
notes which one it chose (`PSKChoices`); the first message must be a hello naming that same
identity, or the Mac closes the connection. So a phone holding one device's key can't say hello as
another. Frames are a 4-byte length and JSON.

### The iCloud lane

Messages are batched into records in the **private** CloudKit database of your own iCloud account
(container `iCloud.dev.xbot`), so the phone and the Mac must be signed in to the same account. Each
batch is sealed with AES-GCM under the pairing key before it's written (`CloudChannel`), so iCloud
holds ciphertext. Alongside it, each record carries in the clear who it's from and to (device
identity or `mac`) and a sequence number; those three are sealed in as authenticated data, so a
batch that's been re-addressed or renumbered doesn't open. Batches are opened in order, once, and
deleted after reading. A batch numbered at or below the last one delivered is dropped as a replay,
and that mark is kept in user defaults on both sides, so it holds across relaunches.

Every batch from a phone starts with its hello. The Mac checks each one against the installation
that paired and drops any that doesn't match; only a batch it takes moves the replay mark, so a
refused sender can't push the mark ahead and lock the real one out. Mail for the Mac sent with a
key it doesn't accept is deleted unread.

This lane needs the Mac app signed with the iCloud entitlement. Builds signed by
`scripts/sign-mac-remote.sh` have it; the Developer ID release script signs without entitlements,
so a release falls back to the local lane and Settings › Devices says why.

### Files from the phone

Every project path from the phone is resolved, symlinks included, and refused unless it stays
inside the project folder (`RemoteHost.inside`). Names for new files and renames can't contain `/`
or be `.` or `..`. A save carries the text the phone opened, and is refused with "It changed on the
Mac since you opened it" if the file no longer matches. Deletion moves to the Trash. These checks
keep the file browser honest; they are not a boundary, because the same device can open a shell
or add any folder as a project.

### The shell from the phone

**Terminal** opens a real login shell (`$SHELL -l`) on the Mac, in the project's folder or your home
folder, with the Mac app's environment (`RemoteShell`). Only the connection that opened it can type
into it, resize it or close it. It ends when that connection goes: at once on the local lane (the
phone lets go when its app goes to the background), and on the iCloud lane after 150 seconds
without hearing from the phone.

### Keeping the Mac awake

While a device is attached or an agent is working, the Mac holds an `IOPMAssertion` against idle
system sleep ("xBot: a phone is attached or an agent is working"). The display may still sleep, and
a closed lid on battery still sleeps.

### Removing a device

Settings › Devices › **Remove** deletes the key from the Keychain, closes that device's connections
on both lanes, and restarts the listener without the key. **Unpair this device** on the phone forgets
the pairing and the cached chat list there; it doesn't tell the Mac, so remove the device on the Mac
too.

## The welcome tour: installers and file access

**Installers run the vendors' official commands, in a terminal you can see.** The agents step's
**Install** and **Sign in** run one fixed command per CLI (`AgentInstaller`; the commands and their
sources are in [First run](06-onboarding.md#step-2-your-agents)) in your login shell, as you, in a
sheet that shows the command and a live terminal. Each install is `curl -fsSL <vendor URL> | bash`
(or `| sh`): it runs whatever the vendor's server sends at that moment, over HTTPS, the same as
pasting the vendor's documented command into Terminal. Nothing runs without a click; Cancel hangs
the command up. xBot doesn't install npm, Homebrew or anything else on its own: if an installer
needed a tool the Mac doesn't have, the card would offer that tool's download page. The commands
are pinned by a test, so a change to one is a reviewed change to the code. In debug builds only,
`XBOT_ONBOARDING_FAKE_COMMAND` swaps a harmless command in for all of them, to look at the sheet
without installing anything; the code that reads it is inside `#if DEBUG`.

**File access is asked for, not taken.** **Allow** lists Desktop, Documents or Downloads once from
xBot itself, so macOS asks you there; xBot keeps no list of what's in them. A folder never asked
about isn't touched, because touching it is what asks. **Full Disk Access is optional**, and only
you can grant it, in System Settings. While the guide panel is up xBot checks for it once a second
by listing `~/Library/Safari` (or `~/Library/Mail`), which macOS refuses without Full Disk Access;
the names in it aren't kept. Full Disk Access lets xBot, and the agents and shells it starts, read
what any app of yours can, including other apps' data such as Mail and Messages.

## The in-app terminal

A floating window per chat, with tabs, each a login shell drawn by SwiftTerm, as you. It gets the
app's environment minus a few app-only variables and any starting with `XBOT_`. It is a terminal;
it has no more and no fewer rights than Terminal.app.

## Updates and signing

- **Sparkle 2 with EdDSA.** The updater starts only when the bundled `Info.plist` has both
  `SUFeedURL` and `SUPublicEDKey`; today's builds have neither, so it's inert. The feed must be
  HTTPS. A release takes both values only from the signed bundle; reading them from the
  environment (`XBOT_APPCAST_URL`, `XBOT_SPARKLE_PUBLIC_KEY`) is allowed in debug builds only
  (`AppUpdateTrust`). Automatic installs are off: the injected plist sets `SUAutomaticallyUpdate`
  to false. An update is never installed while a turn is running: the relaunch that installs it
  waits until none is (`UpdateInstallDeferral`), and background checks wait too.
- **Code signing.** `scripts/sign-mac-app.sh` signs with Developer ID and the hardened runtime,
  then notarises and staples when the credentials are present. `scripts/sign-mac-remote.sh` signs
  a local build with Apple Development and the iCloud and push entitlements. The app is **not
  sandboxed**: it starts CLIs and shells, which the App Sandbox forbids. See
  [Packaging and updates](11-packaging-and-updates.md).

## Not built

The [redesign spec](superpowers/specs/2026-10-06-xbot-redesign-design.md) plans protections that
don't exist yet. Don't read this page as describing them.

- **A bot's own computer.** An Apple Containerization VM per bot, with the project shared read-only
  by default and nothing listening on the Mac. Until it exists, agents run directly on the Mac.
- **A policy gate.** Every tool call classified (read, write, execute, network, outbound message)
  and allowed, asked about or denied per bot, with an approval card in the chat. Today the only
  gate is the CLI's permission mode.
- **An append-only audit trail.** A record of every tool call, written before its result returns.
  Today the record is the chat's transcript, which can be edited and deleted like any chat.
- **API keys.** The native brain (API keys, Ollama) is planned, with keys in the Keychain only.

## Threat model

| Who or what | What they could do | What stops them |
| --- | --- | --- |
| The agent itself, doing something you didn't mean | Anything its mode allows; in Full access, anything you can | The permission mode, enforced by the CLI. Plan mode's read-only planning. Stop (⌘.). The Changes inspector to see and discard edits. No checkpoints, no gate of xBot's own |
| Prompt injection (a web page, file, issue or tool output the agent reads) | Steer the agent within its mode; write `handoff` blocks; put a harmful command in a shell block you then **Run** | The CLI's own defences and its mode. Hand-offs only reach the manager's team, never with more than the manager's chat has. **Run** needs your click. Nothing else |
| Someone who sees the pairing QR or link | If they use it before your device does, and within 10 minutes, before the sheet closes: pair a device and get everything a paired device gets, the shell included, over the local network; over iCloud only if signed in to your iCloud account | The code works once, and only while the sheet is open (10 minutes at most). Keep it private; close the sheet. Remove unknown devices in Settings › Devices |
| Someone on the same network without a key | See the Bonjour advertisement (the Mac's name and id); open a TCP connection | TLS-PSK: no key, no handshake |
| A lost or stolen paired phone | If unlocked, everything a paired device can do | The phone's passcode (keys are kept after first unlock, this device only). Remove it on the Mac |
| Anyone who can read your iCloud data | See records' sender, recipient, sequence numbers, sizes and timing; post or re-post records | AES-GCM with the pairing key over the contents, with sender, recipient and sequence number authenticated. Replays and re-addressed records are refused |
| Another process running as you on the Mac | Read `xbot.sqlite` and transcripts, the CLIs' own logs and credentials, Antigravity and Copilot prompts in process arguments | Nothing of xBot's. Your macOS account is the boundary, as for every app you run |
| An MCP server or plugin you add | Run code as you when an agent uses it | You choosing it. xBot installs only what you ask, through the CLI |
| A tampered update | Run code as you | EdDSA signatures, HTTPS-only feed, key only from the signed bundle in release. Inert until configured |
| A compromised vendor install script | Run code as you, once, when you press Install | The vendor's own HTTPS URL; you see the command and its output; nothing runs without a click. The same trust as pasting the vendor's command into Terminal |
| An automation running unattended | Anything you can, on a schedule, while the app is closed if the helper is on | Off by default; each run is a chat in its history; the helper is removed when the toggle is turned off |

## Known weaknesses

Found while writing this page and not fixed yet.

- **No forward secrecy on the local lane.** Plain PSK suites don't add an ephemeral key exchange,
  so someone who records the traffic and later gets the pairing key can read it.
- **First to use a code wins.** An invite pairs whichever installation says hello with it first.
  Someone who copies the code and uses it before your phone does is paired instead, and your phone
  is then refused. Settings › Devices shows the name the device gave; remove one you don't
  recognise.
- **The sequence number follows the phone's clock.** It starts from the time in milliseconds when
  the lane starts. A phone whose clock is set back has its iCloud batches refused as replays until
  the clock passes the last one the Mac read.
- **MCP masking is a pattern match.** A token passed as a bare argument, with no flag or name
  in front of it, is shown on the Abilities page and sent to a paired phone as it is.

## What we tell the user

In plain words, and all of it true today:

> **Your agents run on this Mac, as you.** xBot uses the agent apps you already have, signed in
> with your own accounts. It doesn't put them in a sandbox. "Read only" and "Can edit" are each
> agent's own settings; "Full access" lets an agent do anything you can do on this Mac.
>
> **What stays on your Mac.** Your chats, your crew and your automations are in a database on this
> Mac. xBot has no server and no account, and sends nothing about you anywhere.
>
> **What xBot reads.** The agents' own logs, to show your usage and your profile. Never their
> passwords or sign-in tokens.
>
> **Pairing a phone.** The pairing code is the key to this Mac: anyone who sees it can pair, until
> a device has used it, the sheet is closed or ten minutes pass. A paired phone can do everything
> you can do here, including open a terminal. On the same Wi-Fi it
> connects directly and encrypted; away, through your own iCloud, encrypted with the same key.
> Remove a phone in Settings › Devices and it can't connect again.
>
> **Automations** run with full access, and only run while xBot is closed if you turn that on.

If any of it stops being true, that is a release blocker.
