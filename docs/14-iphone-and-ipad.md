# The iPhone and iPad app

The agents run on the Mac: the CLIs, their sign-ins, the projects and their files only exist
there. xBot for iPhone and iPad is a **remote** for that Mac. It shows the Mac's workspace live and
drives it, so you can leave with only a phone, or keep a Mac mini at home, and keep working.

The design and its decisions are in the
[mobile remote spec](superpowers/specs/2026-10-11-mobile-remote-design.md). This page says what is
built. The app is in the open pull requests #31–#42, one feature per PR, each stacked on the one
before it.

## Two lanes

| Lane | When | How |
| --- | --- | --- |
| **Local** | The phone and the Mac are on the same network | Bonjour (`_xbot._tcp`) finds the Mac; the pairing code also carries its address and port. TLS with the pairing key as a pre-shared key (TLS-PSK); the phone's hello must name the key its handshake used. Frames are a 4-byte length plus JSON, at most 16 MB. |
| **iCloud** | Not found nearby within 4 seconds | CloudKit's private database in your own iCloud account (container `iCloud.dev.xbot`). Each record is a batch of messages sealed with the pairing key, its sender, recipient and sequence number authenticated with it; opened in order, once, then deleted, and never read again after a relaunch. Every batch from the phone starts with its hello. No server of ours. |

The phone switches by itself; the status under the Mac's name says "same Wi-Fi" or "through
iCloud". Through iCloud, pushes make things quicker when they arrive, but they're best-effort, so
both sides also read the mailbox: the phone every 2 seconds while it's open, and the Mac every
2 seconds while a phone is attached that way (15 seconds otherwise). The phone says "still here"
once a minute. When the app goes to the background it lets go of everything.

While a phone is attached or an agent is working, the Mac holds a power assertion that keeps it
from idle sleep (the display may still sleep). A closed lid on battery still sleeps; that's a macOS
rule.

When the Mac can't be reached, the phone says so and shows the last chats it knew, read-only, from
its cache.

## Pairing

1. On the Mac: **Settings › Devices › Pair an iPhone or iPad**. It shows a QR code holding an
   `xbot://pair?…` link: a random 256-bit key, the Mac's id, name, address and port.
2. On the phone: scan it with the app, paste the link (**Paste a pairing link**, or type it in the
   field below), or open the `xbot://pair` link on the phone. Each side keeps the key in its
   Keychain. The phone also makes an id for this installation and sends it with every hello.
3. Settings › Devices on the Mac lists paired devices and removes them; removing one ends its
   access on both lanes.

A code pairs one device. The first installation to say hello with it is the device, and the Mac
refuses its key from any other. A code nobody used stops working when the sheet closes, after
10 minutes if the sheet is left open (the sheet then offers a new one), and when xBot quits. Opening
a pairing link on a phone that's already paired asks first: "Replace the pairing with …?"

Until the first pairing the feature is off: no listener, no CloudKit.

## The protocol

`XBotRemote` (in `apps/mac/Sources/XBotRemote`) is the wire, Foundation and Network only, so the
Mac and iOS both build it. It uses plain value types, not the Mac's storage models, so the protocol
is versioned on its own (`Wire.version`, now 1). A message one side doesn't know is skipped, not
fatal.

- **Mac → phone** (`HostMessage`): `hello`, the workspace (projects, chats, agents), a chat that
  changed, a transcript, live parts of a reply as it streams, replies to commands, folders, files,
  git status and diffs, notes, automations, the crew, abilities, the profile, shell output, and
  the world (which setting, who lives there and who reports to whom).
- **Agentic Mode**: chats carry `thread`, `agentID` and, for threads, `preview` (the last message
  in a line); messages carry pictures, approvals and lessons as parts (a part a side doesn't know
  arrives as nothing). The phone sends `threadSend` (a member, text and photos) and
  `answerApproval` (allow or not); an approval reaches the phone as its card in the thread, and an
  answer is recorded with the phone's name.
- **Phone → Mac** (`ClientMessage`): open and close a chat, send, stop, edit, plan answers, chat
  settings, rename, retry, delete and undo; list and act on folders, files and git; add or remove a
  project (browsing the Mac's folders); notes, automations, crew (hire, edit, let go, undo, talk
  to, organise, draw an avatar), abilities and plugins, MCP servers; open, type into, resize and
  close a shell; the profile; the world's setting; and `away` for the iCloud lane.
- Every command carries a request id and is answered, `ok` or refused with a reason, so the phone
  never guesses.

On the Mac, `RemoteHost` (in `XBotCore/Remote`, one file per feature) answers through
`Workspace`'s own methods, the same ones the Mac's window calls, so the two can't drift apart and
the Mac's window updates live while you act on the phone. Live text is coalesced before it's sent.

## What the app does

The layout is a bottom tab bar (**Home, Chats, Agents, Projects, Search**) that folds away as you
scroll, in Liquid Glass.

| Area | What you can do |
| --- | --- |
| **Home** | The Mac's name and lane, a plan board with what each agent has left (one ring per provider up to four, a segmented arc beyond that, each in the provider's colours), what's working now, recent chats, and **Places**: Notes, Automations, Abilities, Terminal, Profile, each opened full screen |
| **Chats** | Every chat, live: streaming replies, tool rows, plans to approve or change. Send, stop, edit and resend, retry, rename, delete with undo; new chats with the agent, model, permission, reasoning and plan chips |
| **Agents** | The same pixel world as the Mac, in the same setting (change it here or there, the other follows). The crew in tiers by who reports to whom; a member's page, the editor (role, instructions, look, model, **Reports to**), talk to them, let them go. **Suggested agents** to hire with one tap; **Organise like a company** |
| **Projects** | Files (browse, read, edit and save text; Markdown opens as a formatted document you edit in place and is written back as Markdown, untouched parts byte for byte), git changes and diffs, commit, sync, pull requests and checks, add a project from the Mac's folders. A save is refused if the file changed on the Mac since you opened it |
| **Notes** | Each project's Markdown notes: read, write, delete with undo |
| **Automations** | See, edit, run and switch on or off; turn on the Mac's helper that runs them while xBot is closed |
| **Abilities** | Each agent CLI's connectors, plugins, skills and MCP servers; switch them, install plugins, add an MCP server |
| **Terminal** | A real login shell on the Mac in a project's folder, drawn on the phone by SwiftTerm |
| **Profile** | Lifetime and peak tokens, streaks, activity, top projects, tools and skills, plan usage |
| **Settings** | Appearance (light, dark, system), the accent colour (eight presets or your own), "Show .md files as code", the paired Mac |

On iPad the tab bar can become a sidebar (`.sidebarAdaptable`); the screens are the same.

## Agentic Mode

Settings › **Mode** switches between **Developer** (everything above, the default) and
**Agentic**: no tab bar and no Places, just a chat with each crew member, who do the work on the
Mac. The choice is kept on the phone (`UserDefaults` `mode`); switching is instant and Settings
stays open. The design is in the [Agentic Mode spec](superpowers/specs/2026-10-13-agentic-mode-design.md).

- **Chats**: the Mac's name with a dot (same Wi-Fi, through iCloud, connecting, offline), ⚙ for
  Settings and a hire button (the suggested agents). HeadMaster is pinned first, *"Ask me
  anything"*; then everyone on the crew, most recent first, each with their still pixel face, the
  last message, its time, an unread dot and *typing…* while a turn runs. Pull down to search.
- **A thread**: your bubbles on the right in the accent colour, theirs on the left (Markdown, code
  in its own well). While they work: the typing dots, then one activity line that changes in place
  (*"Running swift test…"*), folded into *"Did 7 things ›"* when the reply lands. Cards: a Mac
  screenshot (tap for full screen, pinch to zoom), an approval with **Allow** / **Don't Allow** and
  then the answer and who gave it, a hand-off (opens that member's thread), a member finishing, and
  a quiet *Learnt: …* line. Long-press: Copy and Retry on theirs, Copy and **Edit and resend** on
  yours.
- **Composer**: a growing field; the mic dictates with `SFSpeechRecognizer` (on the device where
  it can), the live transcript going into the field until tapped again; **+** picks up to four
  photos, downscaled on the phone to JPEGs of at most 1600 px (quality 0.7); send, or stop while
  they work.

On the Mac each member's **thread** is one chat flagged `chats.thread` (schema 7), started by the
first message and kept going: Full access, on the member's own CLI and model, in xBot's Inbox
folder. Photos are saved as JPEGs ≤ 1600 px in `~/Library/Application Support/xBot/Images` and in
the folder's `Attachments/`, and the prompt names them (*"Attached: /…/Attachments/<id>.jpg"*); the
person's message shows the text and the pictures. When the session can't be resumed (the member
moved to another CLI, or the CLI says it lost or can't fit the session), the thread continues in a
new chat that starts with the last twelve messages; the old one stays as a plain chat with that
member. Threads are listed on the Mac like any chat with an agent.

Light by design: the list and thread draw no world and run no timers; messages render lazily; a
thread keeps its last 200 messages on the phone (older ones stay on the Mac); pictures are decoded
at the size they're shown, off the main thread, and cached small (12 MB at most).

## Code

```
apps/ios/
  project.yml                 XcodeGen: XBotMobile (iOS 26), XBotMobileUITests, XBotMacSigning
  Sources/
    XBotMobileApp.swift       app, tabs (AppTab), Places (Tool), Settings, Theme
    RemoteClient.swift        the mirror of the Mac: lanes, pairing store, cache, commands
    Glass.swift, Accent.swift the look: cards, gauges, accent store, provider colours
    HomeScreen, UsageBoard, ChatListView, ChatScreen, Composer, AgentsWorldScreen, CrewScreen,
    SuggestedAgents, ProjectsScreen, ProjectScreen, MarkdownEditor, NotesScreen,
    AutomationsScreen, AbilitiesScreen, TerminalScreen, ProfileScreen, PairView
    AgenticRoot, AgenticChatsView, AgenticThreadView, AgenticCards, AgenticComposer   Agentic Mode
  UITests/LiveRemoteUITests.swift
```

It links three libraries from `apps/mac/Package.swift`: `XBotRemote` (the wire), `XBotWorld`
(avatars, the five worlds, the org chart, the stage) and `XBotMarkdown` (Markdown documents as
blocks, so an edit only changes what you touched). SwiftTerm draws the terminal.

`XBotMacSigning` is not part of the phone app. It's a helper target with the Mac's bundle id, there
so Xcode will make a provisioning profile with iCloud and push for the Mac app; see
[packaging](11-packaging-and-updates.md).

## Building and running

```sh
cd apps/ios && xcodegen generate     # after adding or removing files
xcodebuild -project XBotMobile.xcodeproj -scheme XBotMobile \
  -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation build
```

`-skipPackagePluginValidation` is needed on every `xcodebuild` call because SwiftTerm ships a build
plugin. On a device, add `-allowProvisioningUpdates` with your own team in `project.yml`, then
install with `xcrun devicectl device install app`. The phone has to be unlocked to install or
launch. There's no TestFlight or App Store build yet.

## Tests

- **Package tests** (`swift test` in `apps/mac`): every message round-trips; the local transport
  over loopback with the key (a wrong key refused, and the listener knowing which key a phone
  used); the cloud channel against a fake mailbox (order, dedupe, cleanup, renumbered, reflected
  and replayed batches refused); pairing in `RemoteService` (codes withdrawn on close, expired,
  removed at relaunch, used once, a hello that names another key refused); `RemoteHost` for each feature with a scripted brain; remote shells;
  path checks; the world and the org chart. Agentic Mode: threads (schema 7 and its migration, one
  per member in Full access in the Inbox, photos downscaled and attached by path, a lost session
  continuing in a new thread), `threadSend` and `answerApproval` from a phone, and what the phone
  derives (`AgenticDigest`: threads by member, the activity line, *Did N things*, hand-off notes,
  previews).
- **Live phone tests** (`UITests/LiveRemoteUITests.swift`, 21 of them; `testAgenticMode` switches
  to Agentic Mode and gets HeadMaster to answer, `testAgenticActivity` watches the activity line
  and opens *Did N things*, `testAgenticCards` answers an approval card and opens a screenshot from
  the debug Mac's `XBOT_AGENTIC_DEMO=1` cards). Photos and dictation aren't driven live: the
  simulator's picker and microphone are outside the app: the simulator pairs with a
  debug build of the Mac app (pairing link in `TEST_RUNNER_XBOT_PAIR_URL`) and goes through each
  feature for real: a new Codex chat answering, managing chats, projects and files, notes,
  automations, the crew and the org chart, suggested agents, abilities, the terminal (typing
  commands that write files on the Mac), the profile, the world staying in step with the Mac, the
  plan board at 0, 1, 3 and 6 providers, Markdown editing and the accent colour. They are not in CI:
  they need a signed-in agent CLI on the Mac. Point them at a sandboxed debug Mac, not your own
  library.
- **On a real iPhone 15 Pro:** paired by QR, chats over the same Wi-Fi, then a new chat answered
  through iCloud with Wi-Fi off.

## Measured

On the installed release build of the Mac app (2026-10-11):

| State | CPU | Memory |
| --- | --- | --- |
| Paired, no phone attached, xBot in the background | 0.01% average (0.1% peak) over 60 s | 63 MB |
| The same before the motion gate | 17.3% | 212 MB |

## Known limits

- The iCloud lane needs the Mac app signed with the iCloud entitlement. Builds made with
  `scripts/sign-mac-remote.sh` have it; a Developer ID release needs a Developer ID provisioning
  profile with iCloud, which isn't set up yet. Without it, the Mac falls back to the local lane.
- Agents never run on the phone. With the Mac off or asleep, the phone shows its cache and nothing
  else.
- There's no distribution channel for the phone app yet: it's installed from Xcode.
