# xBot for iPhone and iPad: a remote for the Mac

Status: draft for approval, 2026-10-11.

## What it is

The agents keep running on the Mac: the CLIs (Claude Code, Codex, Antigravity, Copilot), their
logins, the projects and the files only exist there. The iPhone/iPad app is a **remote**: it shows
the Mac's workspace live and controls it. Leave with only an iPhone, or keep a Mac mini at home,
and keep working.

Decided with the person (2026-10-11):

- **Connection: both.** Direct over the local network when the phone and the Mac are on the same
  Wi-Fi, through iCloud (the private CloudKit database, no server of ours) when away. The phone
  switches between them by itself.
- **First version: Chats.** Every chat live (streaming replies, tool rows, plans), send, stop,
  edit and resend, approve or change a plan, new chat, and the agent, model, permissions, effort
  and plan chips. Projects/files/diffs, Agents, Automations, Notes and the terminal come later.
- **Sleep:** the Mac stays awake only while a phone is attached or an agent is working.
- **Performance comes first** (below).

## Performance budget

The Mac app must cost the same as today when no phone is attached, and very little when one is.

| State | Budget on the Mac | How |
|---|---|---|
| No phone paired | nothing | No listener, no CloudKit; the feature is off until the first pairing. |
| Paired, no phone attached | < 0.1% CPU idle, < 3 MB | A Bonjour listener (kernel-woken) and one CloudKit subscription (push-woken), plus one small CloudKit read every 15 s (pushes alone proved unreliable on the Mac; see below). |
| Phone attached, nothing running | < 0.5% CPU | Changes are pushed as small diffs when the workspace changes; no polling, no snapshots on a timer. |
| Phone attached, agent streaming | < 2% CPU over the turn's own cost | Live text is coalesced: at most 10 sends/s on the local network and 1 write/s (per running chat) through iCloud. |

Rules that hold it there:

- Event-driven only: the Mac sends when `Workspace` changes (it is already `@Observable`); the phone
  never polls. iCloud is used only when a phone says it is away (a heartbeat record, renewed every
  60 s while the phone app is open), so a phone at home costs no CloudKit writes.
- The phone receives the chat list once, then diffs; a transcript only when opened, then diffs.
- Nothing new draws on the Mac. The motion gate (`motionGate()`, `\.motionPaused`) pauses every
  looping animation (wallpaper, the agents' world, sprites, the effort knob) while xBot isn't the
  active app, so a Mac serving a phone, or just sitting behind other apps, draws nothing.
- iCloud pushes are best-effort (APNs throttles and coalesces silent pushes, and on the Mac they
  didn't arrive at all in the first live test), so they only make things quicker. The Mac reads
  the mailbox itself: every 2 s while a phone is attached through iCloud (as the phone reads the
  Mac), every 15 s otherwise, to notice a phone that just went away.
- Measured before merge on the installed release build, each row of the table, with the numbers in
  the PR.

## Shape

```
XBotRemote (new, Foundation-only, macOS + iOS)   the protocol: Codable messages, versioned
  ├── Mac side: RemoteHost in XBotCore            watches Workspace, sends diffs, runs commands
  └── iOS side: RemoteClient                      keeps a mirror of the Mac's workspace
Transports (both carry the same messages)
  ├── LocalTransport   Network.framework, Bonjour "_xbot._tcp", TLS with the pairing key (PSK)
  └── CloudTransport   CloudKit private DB, container iCloud.dev.xbot; records = message batches,
                       pushed by CKSubscription both ways; old records deleted after 1 day
apps/ios  (Xcode project, iOS/iPadOS 26)          SwiftUI: chat list, chat, composer
```

- **Messages.** Mac → phone: `hello(version, macName)`, `chats([ChatSummary])`, `chatChanged`,
  `transcript(chatID, [Message])`, `live(chatID, parts delta)`, `turnEnded`, `options(agents,
  models, efforts)`. Phone → Mac: `open(chatID)`, `send`, `stop`, `edit(messageID, text)`,
  `answerPlan(approve | change)`, `newChat(project)`, `setChat(agent, model, mode, effort, plan)`.
  Every command is answered (`ok` / `refused(reason)`), so the phone never guesses.
- **Commands go through `Workspace`'s existing methods** (the same ones the Mac's own UI calls), so
  the Mac and the phone can't drift apart, and the Mac's window updates live as you act on the phone.
- **Pairing.** Mac: Settings › Devices › Pair an iPhone or iPad shows a QR code (a random 256-bit
  key plus the Mac's id). The phone scans it; both keep the key in their Keychain. The local
  connection is TLS with that key; iCloud records are encrypted with it too
  (`encryptedValues`), on top of the private database. Settings › Devices lists paired devices and
  removes them.
- **Keeping awake.** An `IOPMAssertion` (prevent idle sleep, display may sleep) while a phone is
  attached or a turn runs; released otherwise. The lid closed on battery still sleeps (macOS rule);
  the Mac's devices page says so.
- **When the Mac can't be reached** (asleep, off, no network): the phone says so plainly, shows the
  last known chats read-only, and queues nothing it can't deliver.

## Mobile UI (first version)

- iPhone: Messages-like. A list of chats grouped by project (Recent first), a chat screen with the
  streaming reply, tool rows and plans, and a composer with the same chips as the Mac. Native
  sheets for agent/model/permissions.
- iPad: a sidebar of projects and chats beside the chat, keyboard shortcuts (⌘N, ⌘Return, Esc).
- A status line: "Connected to Yoav's Mac mini · same Wi-Fi" / "· through iCloud" / "Mac asleep".

## Setup the person does once

- Xcode signing: the iOS app and the Mac app get the iCloud capability with container
  `iCloud.dev.xbot` (Apple Developer account, team N6883L5366). The Mac app is Developer ID signed,
  so it needs a Developer ID provisioning profile with iCloud; xcodebuild can create it with
  `-allowProvisioningUpdates` once the container exists.
- Install the iOS app on the iPhone/iPad from Xcode (development signing), later TestFlight.

## Tests

- Protocol: every message round-trips; unknown future messages are ignored, not fatal.
- RemoteHost with a scripted brain: a phone's `send` runs a turn, the live deltas arrive coalesced,
  `stop`/`edit`/plan answers do what the Mac's buttons do.
- Transports: a loopback local connection with the PSK (and a wrong key refused); the cloud
  transport against a fake database (batching, ordering, dedupe, cleanup).
- Budget: a test that a host with no clients does no work per workspace change.
- Live: the real iPhone 15 Pro, on the same Wi-Fi and then on cellular (iCloud path): open a chat,
  send, watch it stream, stop, approve a plan; CPU/RAM on the Mac measured for each budget row.

## Measured (installed release build, 2026-10-11)

| State | CPU | Memory |
|---|---|---|
| Paired, no phone attached, xBot in the background | 0.01% avg (max 0.1%) over 60 s | 63 MB |
| Same, before the motion gate (Sky Realm wallpaper looping off-screen) | 17.3% avg | 212 MB |
| xBot in front, wallpaper animating (not the remote's cost) | ~12% | |

A 5 s `sample` of the paired, idle Mac put CloudKit at 20 of 2,778 main-thread samples (< 1%).

Live on the real iPhone 15 Pro (iOS 27): paired by scanning the QR; same Wi-Fi ("· same Wi-Fi"),
chats listed; Wi-Fi off, "· through iCloud", a new Codex chat sent from the phone answered through
iCloud. Simulators (iPhone 17 Pro, iPad Pro 13" M5): `LiveRemoteUITests` pairs with a debug Mac
build, starts a Codex chat, gets "pong", sends a follow-up, gets "ping".

## Mac signing for iCloud

iCloud and push are restricted entitlements, so the Mac app needs a provisioning profile.
`apps/ios/project.yml` has a helper target, `XBotMacSigning` (bundle `dev.xbot.app`, same
container), that Xcode's automatic signing provisions; `scripts/sign-mac-remote.sh` builds it,
embeds its profile in XBot.app and signs with the same identity and entitlements. That is
development signing (this team's Macs). A Developer ID release needs a Developer ID profile with
iCloud from the developer portal; without one, the release falls back to the local lane and says so
in Settings › Devices.
