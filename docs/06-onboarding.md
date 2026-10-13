# First run

The first time xBot opens, a welcome tour fills the window: what xBot is, the agent CLIs it works
through (installed and signed in from the tour if they're missing), the main features, the folders
agents need, the phone, and a world and theme. Then Home. This page says what happens on the Mac
the first time, in the tour and around it, and when you pair a phone. The design is in the
[onboarding spec](superpowers/specs/2026-10-12-onboarding-design.md).

xBot needs macOS 26 on Apple silicon ([ADR-0009](decisions/0009-native-harness-redesign.md)).

## On the Mac

### Launch

1. **The library is made.** `Store.live()` opens
   `~/Library/Application Support/xBot/xbot.sqlite`, creating it, and runs the migrations up to
   schema version 6. If it can't be opened, xBot runs on an in-memory library and says so: "xBot
   couldn't open its library, so this session won't be saved."
2. **The founding crew is seeded.** The migration that adds the `agents` table (version 4) saves
   four agents if the table is empty: **HeadMaster** (founder and orchestrator), **Forge**
   (builder), **Hawk** (reviewer) and **Quill** (scribe), each with a pixel avatar and
   instructions (`Agent.foundingCrew`). It runs once per library, so a member you let go stays
   gone. All four use Claude Code; a chat with one of them uses the first CLI found if Claude Code
   isn't installed. The three members report to HeadMaster, and HeadMaster to you.
3. **The tour, or Home.** `OnboardingModel` decides (below). Either way `HarnessLocator` runs: it
   reads your login shell's `PATH` (`$SHELL -l -i -c`, given five seconds) and adds the usual
   install folders (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`,
   `~/.bun/bin`, `~/.claude/local` and the system folders), then takes the first `claude`,
   `codex`, `agy` and `copilot` it finds there. Nothing is installed without a click.
4. **Nothing listens.** No port is opened and iCloud isn't touched until you pair a device.

### When the tour shows

The tour shows in place of the window's content when `onboarding.completedVersion` in user
defaults is missing or lower than the tour's version (`OnboardingModel.currentVersion`, 1 today),
and it wasn't skipped. Raising the version shows a new tour to everyone who finished an old one.

- **Someone upgrading isn't sent through it.** If the library already has chats or projects the
  first time this version runs, the tour is recorded as finished.
- **Skip**, on any step, closes it and sets `onboarding.skipped`. Home then shows a quiet **Finish
  setting up** row above the composer, with **Continue** (the tour again, from the start) and ×
  (`onboarding.reminderDismissed`: the row goes for good). The tour doesn't show on later launches.
- **Start**, on the last step, records the version, clears the reminder, and opens Home with the
  composer focused.
- **Help › Welcome Tour** shows it again from the start, at any time. Skipping a tour you'd
  already finished leaves no reminder.

### The tour

Full window, over the wallpaper's colours. Each step is an animated scene, a title, one sentence
and up to three bullets, with the step's controls beside them. Underneath: **Skip**, eleven
progress dots (each a button; not past the agents step until it's done), **Back** and
**Continue**. ← and → move between steps, Return continues. A new step slides in from the side
it's travelling towards (a cross-fade under Reduce Motion).

| # | Step | What you do |
| --- | --- | --- |
| 1 | **Your AI crew, on your Mac.** | Continue |
| 2 | **Your agents** | Install or sign in to a CLI (below). Continue needs one ready, or **Skip for now** ticked |
| 3 | **Projects and chats** | — |
| 4 | **Plans you can edit** | — |
| 5 | **Changes, files and a terminal** | — |
| 6 | **Your crew, organised like a company** | — |
| 7 | **Notes, abilities and automations** | — |
| 8 | **Let your agents into your files** | Allow Desktop, Documents and Downloads, or give Full Disk Access (below) |
| 9 | **Your iPhone, too** | **Show the code** to pair, or **Not now** |
| 10 | **Make it yours** | Pick the crew's world (the Agents page's setting) and Dark, Light or Match System (Settings › Appearance's) |
| 11 | **Ask HeadMaster anything.** | **Start** |

The scenes (`XBotUI/Onboarding/Scenes/`) are drawn in SwiftUI with the `XBotWorld` sprites, loop
while their step is on screen, pause while xBot isn't the active app, and hold their last frame
under Reduce Motion. They are decoration: hidden from VoiceOver and not clickable.

### Step 2: your agents

A card per CLI, with its state (`AgentSetup`):

| State | The card says | Its button |
| --- | --- | --- |
| Looking | "Looking for it on this Mac…" | — |
| Not installed | "Not on this Mac yet." | **Install** |
| Not signed in | "Installed. Sign in with your account to use it." | **Sign in** |
| Ready | "Installed and signed in." | — |
| Ready, sign-in unconfirmed | "Installed. It asks you to sign in the first time it runs, if it needs to." | **Sign in** (quiet) |
| Needs a tool | "Its installer needs npm, which this Mac doesn't have." | **Get npm** (the download page) |
| Didn't work | The reason | **Try again** |

How xBot tells whether a CLI is signed in, without reading a token:

- **Claude Code:** the account block in `~/.claude.json` (`ClaudeAccount.isSignedIn()`).
- **Codex:** whether `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`) exists, not what's in it;
  without it, `codex login status`, which exits 0 when signed in (Codex can keep its login in the
  Keychain instead of the file).
- **Antigravity and GitHub Copilot:** they keep their sessions in the Keychain and document no
  status command, so an installed one counts as ready and signs in the first time it runs.

**Install** and **Sign in** open a sheet with the command on top and a real terminal under it,
running the command in your login shell; you can type into it if the CLI asks something, and
**Cancel** stops it (a hang-up, as when a terminal window closes). When it ends xBot looks again: a
CLI that's now there and signed in turns its card green. An installer that stopped with an error,
or finished without leaving the CLI behind, says so in a sentence under the terminal, whose output
stays on screen. A sign-in that ends with the CLI still signed out says "The sign-in didn't
finish." Antigravity's sign-in is the CLI's own session, which keeps running afterwards, so the
sheet also has **I've signed in**.

The commands are the vendors' own (`AgentInstaller`, with each source URL beside it in the code),
checked against their documentation on 2026-10-13:

| CLI | Install | Sign in |
| --- | --- | --- |
| Claude Code | `curl -fsSL https://claude.ai/install.sh \| bash` ([setup](https://code.claude.com/docs/en/setup)) | `claude auth login` ([CLI reference](https://code.claude.com/docs/en/cli-reference)) |
| Codex | `curl -fsSL https://chatgpt.com/codex/install.sh \| sh` ([CLI](https://developers.openai.com/codex/cli)) | `codex login` ([auth](https://developers.openai.com/codex/auth)) |
| GitHub Copilot | `curl -fsSL https://gh.io/copilot-install \| bash` ([install](https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli)) | `copilot login` ([authenticate](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli)) |
| Antigravity | `curl -fsSL https://antigravity.google/cli/install.sh \| bash` ([install and auth](https://antigravity.google/docs/cli/install)) | `agy` (it signs in through the browser when it has no session) |

All four install into `~/.local/bin` without npm or Homebrew. The sign-in runs the binary that was
found, by its full path, because a shell started right after an install may not have that folder
on its `PATH` yet. If a vendor's installer ever needs a package manager the Mac doesn't have, its
card offers that tool's download page instead (`RequiredTool`); xBot never installs one itself.

### Step 8: your files

macOS asks the first time an app's process touches Desktop, Documents or Downloads, and an agent
turn in a project there would otherwise stop mid-task on the prompt.

- **Allow** (per folder) and **Allow all** list each folder once from xBot itself, so macOS's prompt
  comes up there and then, one folder after another. A folder turns green when allowed; refused, it
  says "Not allowed: change it in System Settings." with **Open Settings** (Privacy & Security ›
  Files & Folders).
- A folder never asked about stays "Not asked yet": reading it to find out would raise the prompt.
  The ones already asked about (`onboarding.foldersAsked`) are read again each time the step
  appears or xBot becomes active, so a change made in System Settings shows.
- **Or give Full Disk Access…** opens System Settings at Privacy & Security › Full Disk Access and
  puts a small floating guide beside its window (`PermissionGuide`): xBot's icon, which can be
  dragged into the list, a switch turning on, and one line. The guide follows the System Settings
  window (every half second, from the window list), checks for Full Disk Access every second, and
  when it's granted shows a check, closes, and brings xBot back to the front with every folder
  green. Closing the guide or quitting System Settings stops it; the step stays as it was.
- Full Disk Access is detected by listing `~/Library/Safari` (or `~/Library/Mail`), which macOS
  allows only with Full Disk Access and refuses without a prompt.

Both are optional: Continue works without them.

### Step 9: your iPhone

The same code as Settings › Devices, with the same rules: it pairs one device, runs out after ten
minutes, and is withdrawn when you leave the step, however you leave it. "Paired with <device>."
when a phone says hello.

### Home afterwards

#### An agent was found

Home is the composer on its own. A new chat uses the agent picked in the composer, else the one used
most recently, else the first found in the order Claude Code, Codex, Antigravity, Copilot. New chats start in **Can edit**, with the agent's own model and reasoning, until you
change the defaults in Settings › General. A chat without a project runs in
`~/Library/Application Support/xBot/Inbox/`.

xBot doesn't check that a CLI is signed in before a turn. If it isn't, the turn fails with
whatever the CLI wrote to stderr.

#### No agent was found

Home says, in full (`HomeView`):

> **xBot works through an agent you already have.**
>
> Install Claude Code, Codex, Antigravity or GitHub Copilot and sign in, then come back. xBot will
> find it.
>
> Get Claude Code · Get Codex · Get Antigravity · Get GitHub Copilot
>
> [ Look again ]

The four links open `claude.com/product/claude-code`, `developers.openai.com/codex`,
`antigravity.google` and `github.com/github/copilot-cli`. xBot looks again when you press **Look
again**, press **Look Again** in Settings › Agents, finish or skip the tour, or relaunch; it doesn't
notice an install on its own. **Help › Welcome Tour** installs from inside the app.

### Settings › Agents

One section per CLI, all four always listed:

| Row | Shows |
| --- | --- |
| Found at | The executable's path, "Looking…" or "Not installed" |
| Signed in | Claude Code: "Yes" or "No", from the account block in `~/.claude.json`. Codex: "Yes" once its session logs have shown a plan, else "Not seen yet". Antigravity and Copilot: "Checked on the first turn" |
| Plan | Claude Code's from `~/.claude.json`; Codex's from its session logs |
| 5-hour / Weekly usage left | When the CLI has reported its limits |

What xBot reads of those files, and what it doesn't, is in [Security](10-security.md).

## Pairing an iPhone or iPad

The phone app is a remote for the Mac ([The iPhone and iPad app](14-iphone-and-ipad.md)). It's
installed from Xcode for now; there's no TestFlight or App Store build.

### On the phone, before pairing

Until it's paired the app shows one screen (`PairView`), not the tab bar:

> **Your Mac, in your pocket**
>
> Keep working with your agents from here. They still run on your Mac; this is the remote.
>
> 1. On your Mac, open xBot › Settings › Devices.
> 2. Click Pair an iPhone or iPad.
> 3. Scan the code it shows.
>
> [ Scan the code ]
> [ Paste a pairing link ]   Or type it: xbot://pair?…

**Scan the code** opens the camera (iOS asks for it once). **Paste a pairing link** reads the link
from the clipboard, or type it in the field. A code that isn't an xBot link gets "That isn't an xBot
pairing code." Opening an `xbot://pair?…` link on the phone pairs it the same way; if the phone is
already paired, it first asks "Replace the pairing with <Mac>?".

### On the Mac

**Settings › Devices › Pair an iPhone or iPad…** (or the tour's iPhone step) makes a new pairing
key, saves it in the Keychain, starts the local listener and, if this copy of xBot is signed for
iCloud, the iCloud lane. The sheet shows a QR code with the `xbot://pair?…` link: the Mac's id,
name, Wi-Fi or Ethernet address, the listener's port if it already has one, and the key. Under it:
"The code pairs one device. Keep it to yourself: it's the key to this Mac." Anyone who sees the code
can pair; see [Security](10-security.md#pairing).

### Connecting

1. The phone saves the code in its Keychain and looks for the Mac: over Bonjour by the Mac's id,
   and straight at the address and port in the code if there are both. iOS asks once for local
   network access.
2. Not found within 4 seconds, it goes through iCloud, which needs the phone and the Mac signed in
   to the same iCloud account. With iCloud off on the phone it says "Your Mac isn't on this
   network, and iCloud is off on this device."
3. When the phone first connects, the Mac lists it in Settings › Devices and the sheet changes to
   "Paired. You can close this." The phone opens on Home; the status under the Mac's name says
   which lane it's on.

If the Mac's copy of xBot isn't signed for iCloud (a Developer ID release, for now), Settings ›
Devices says "This copy of xBot isn't signed for iCloud, so phones can reach it on the same network
only."

### Unpairing

**Remove** in the Mac's Settings › Devices ends that device's access on both lanes. **Unpair this
device** in the phone's Settings forgets the Mac and the cached chat list on the phone, and brings back the pairing
screen; it doesn't tell the Mac, so remove the device there too.

## Coming from xBot 1.x

The redesign imports nothing from 1.x. Its Docker container and volumes stay on disk until removed
with `scripts/uninstall-xbot.command`, which also removes the current app's library and
preferences.

## Not built

- **An API key or Ollama** in the agents step: the native brain that would use them isn't built
  (item 3 in the [roadmap](12-roadmap.md)).
- **A live install test.** The install and sign-in commands are pinned by tests and were checked
  against the vendors' pages, but no automated run installs a CLI.
