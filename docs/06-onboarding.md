# First run

The redesigned xBot has no onboarding flow. There is no welcome screen, no system check, no step
that asks for a key: the app opens to Home, looks for the agent CLIs you already have, and is ready
when it finds one. This page says what happens the first time, on the Mac and when you pair a
phone. The onboarding the [redesign spec](superpowers/specs/2026-10-06-xbot-redesign-design.md)
plans is at the end, and isn't built.

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
3. **The CLIs are looked for.** The window opens on Home and `HarnessLocator` runs: it reads your
   login shell's `PATH` (`$SHELL -l -i -c`, given five seconds) and adds the usual install
   folders (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`,
   `~/.bun/bin`, `~/.claude/local` and the system folders), then takes the first `claude`,
   `codex`, `agy` and `copilot` it finds there. Nothing is installed and nothing is asked.
4. **Nothing listens.** No port is opened and iCloud isn't touched until you pair a device.

While it looks, Home shows the composer. When it has finished, one of two things.

### An agent was found

Home is the composer on its own. A new chat uses the agent picked in the composer, else the one used
most recently, else the first found in the order Claude Code, Codex, Antigravity, Copilot. New chats start in **Can edit**, with the agent's own model and reasoning, until you
change the defaults in Settings › General. A chat without a project runs in
`~/Library/Application Support/xBot/Inbox/`.

xBot doesn't check that a CLI is signed in before the first turn. If it isn't, the turn fails with
whatever the CLI wrote to stderr.

### No agent was found

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
`antigravity.google` and `github.com/github/copilot-cli`. xBot looks again when you press **Look again**, press **Look Again** in
Settings › Agents, or relaunch; it doesn't notice an install on its own.

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

**Scan the code** opens the camera (iOS asks for it once). A code that isn't an xBot link gets
"That isn't an xBot pairing code." Opening an `xbot://pair?…` link on the phone pairs it the same
way. There's no field to paste the link into.

### On the Mac

**Settings › Devices › Pair an iPhone or iPad…** makes a new pairing key, saves it in the Keychain,
starts the local listener and, if this copy of xBot is signed for iCloud, the iCloud lane. The
sheet shows a QR code with the `xbot://pair?…` link: the Mac's id, name, Wi-Fi or Ethernet address,
the listener's port if it already has one, and the key. Under it: "The code pairs one device. Keep
it to yourself: it's the key to this Mac." Anyone who sees the code can pair; see
[Security](10-security.md#pairing).

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

## Planned, not built

The redesign spec's onboarding is three screens, and none of it exists yet:

1. **Welcome.**
2. **Connect a brain:** the CLIs found, shown as ready; or paste an API key; or use Ollama if it's
   running.
3. **Meet your first bot:** a name, a soul from a template, and an optional "give it a computer"
   that starts the VM image download in the background.

No Docker or Colima check: the only requirement is macOS 26 on Apple silicon, enforced by the
deployment target. It depends on parts that aren't built either, the native brain (API keys,
Ollama) and a bot's own computer, and is item 3 in the [roadmap](12-roadmap.md), not started.
