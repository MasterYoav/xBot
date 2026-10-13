# Onboarding: the first run

Status: approved in conversation, 2026-10-12. Replaces the onboarding sketched in the
[redesign spec](2026-10-06-xbot-redesign-design.md#onboarding) (three screens around a native brain
that isn't built). Mac only; the iPhone keeps its pairing screen.

## What the person asked for

"An intuitive, beautiful onboarding process for first-time users. All inclusive. Explaining all
features with nice animations, guiding the user on granting permissions like ChatGPT, where the user
has everything in front of him and the permission pages are really coming to him."

Decided with the person:

- **Full window, cinematic.** One idea per screen, each with an animated scene, progress dots, Back,
  Continue and Skip. Reopenable from **Help › Welcome Tour**.
- **Agents installed in the app.** xBot finds each CLI; for a missing one it runs the CLI's official
  installer in a small embedded terminal, then the CLI's own sign-in (which opens the browser), and
  confirms it worked. The person never opens Terminal.
- **Permissions: files only.** Desktop, Documents and Downloads, so an agent never stops mid-task to
  ask; or Full Disk Access. The prompt comes to the person (below).
- **Pair your iPhone**: an optional step with the QR.

## The flow

Shown on first launch (no `onboarding.completedVersion` in defaults) in place of the main window's
content, edge to edge, over the chosen wallpaper's colours. Skip at any point leaves a quiet
**Finish setting up** row on Home until it's done or dismissed. Every step can be returned to.

| # | Screen | Scene (animation) | What the person does |
| --- | --- | --- | --- |
| 1 | **Welcome** — "Your AI crew, on your Mac." | The village at dawn; HeadMaster, Forge, Hawk and Quill walk in one by one and wave; the xBot mark settles above them | Continue |
| 2 | **Your agents** — "xBot works through the agents you already pay for." | Four cards (Claude Code, Codex, Antigravity, GitHub Copilot), each with its state | Install / Sign in / nothing (Ready). At least one Ready to continue, or "Skip for now" |
| 3 | **Projects and chats** | A mock window: a folder drops in, a tab opens, a reply streams in with a tool row folding | — |
| 4 | **Plans you can edit** | A plan card unfolds step by step; one step is dragged up; the steps tick off | — |
| 5 | **Changes, files and a terminal** | The inspector slides in: changed files, a diff line turning green, a PR check passing; a terminal tab types `swift test` | — |
| 6 | **Your crew, organised like a company** | HeadMaster on top; a CTO is hired and drops onto the tier below; Forge and Hawk walk under them; a hand-off bubble travels down and a "done" bubble comes back up | — |
| 7 | **Notes, abilities and automations** | Three cards flip in: a Markdown note, connectors toggling on, an automation's steps snapping into place with a clock | — |
| 8 | **Let your agents into your files** | Folder icons for Desktop, Documents, Downloads; each turns green as it's allowed | Allow (below) |
| 9 | **Your iPhone, too** (optional) | A phone slides up beside a Mac; the QR draws itself | Show the code / Not now |
| 10 | **Make it yours** | Five worlds as small living postcards; light/dark | Pick a world (sets the Agents world) and appearance |
| 11 | **Ready** — "Ask HeadMaster anything." | The crew in the chosen world | Start → main window, Home's composer focused |

Scenes are drawn with SwiftUI and the shared `XBotWorld` sprites (no video files), loop while the
step is on screen, pause under the motion gate, and show their final frame under Reduce Motion.
Text is short: a title, one sentence, at most three bullets.

## Agents (step 2)

`AgentSetup` (XBotCore) holds, per CLI, a state: `checking`, `missing`, `installing`, `installed`
(not signed in), `signingIn`, `ready`, `failed(reason)`. It uses `HarnessLocator` to find the binary
and each CLI's signed-in check (Claude Code: `ClaudeAccount.isSignedIn()`; others: their own
status command or credentials-file presence, whichever the CLI documents; never reading a token's
value).

- **Install** runs the CLI's **official** install command, verified from its own documentation when
  implemented and recorded in `AgentInstaller` with the source URL beside it. Where the official
  route needs a package manager the Mac doesn't have (npm, Homebrew), the card says what it needs
  and offers that CLI's download page instead of installing a package manager silently.
- **Sign in** runs the CLI's own login command.
- Both run in a small sheet holding an embedded SwiftTerm terminal (the person sees exactly what
  runs, can type if the CLI asks, and can cancel). The command is shown above it. When the process
  ends, xBot re-detects; success turns the card green with a check.
- Nothing runs without a click. A failure keeps the terminal output and says so in a sentence.

## Files (step 8): the permission comes to the person

macOS asks for Desktop, Documents and Downloads the first time an app's process touches them, and
an agent turn touching a project there would otherwise raise the prompt mid-task.

- **Allow** reads each folder once, from xBot itself, so macOS shows its prompt right there, in
  front of the onboarding window, one folder after another. Each folder turns green when allowed,
  or shows "Not allowed: change it in System Settings" with a button.
- **Or give Full Disk Access** (one switch, covers everything). macOS only grants this in System
  Settings, so:
  1. xBot opens System Settings at Privacy & Security › Full Disk Access
     (`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`).
  2. A small floating **guide panel** (`NSPanel`, non-activating, always above) docks beside the
     System Settings window, tracking its frame: xBot's icon, which the person can **drag into the
     list**, and an animated switch flipping on, with one line of text.
  3. xBot polls the grant (a cheap read that only succeeds with Full Disk Access) every second while
     the panel is up; when it flips, the panel shows a check, closes, and xBot comes back to the
     front with the step done.
  4. If the panel is closed or System Settings quits, the step stays as it was.
- The state of each grant is read live whenever the step appears, so returning later shows the
  truth.

`FileAccess` (XBotCore) holds the probes behind a protocol so tests script them.

## iPhone (step 9)

The same QR as Settings › Devices, with the same rules (single use, withdrawn when the step is left,
10 minutes). "Paired with <device>" when a phone says hello.

## Where it lives

- `XBotCore/Onboarding/`: `OnboardingModel` (steps, current index, completion with a version so a
  future tour can be shown again, skip, the Home reminder), `AgentSetup`, `AgentInstaller`,
  `FileAccess`.
- `XBotUI/Onboarding/`: `OnboardingView` (the shell: scene area, text, dots, buttons), one view per
  step, `Scenes/` (the animated scenes), `PermissionGuidePanel` (the floating guide), `InstallSheet`.
- Help menu: **Welcome Tour**. Home: **Finish setting up** while skipped and not done.

## Tests

- `OnboardingModel`: first launch shows it; completion persists; skip leaves the reminder; dismissing
  the reminder; Welcome Tour reopens; the version bump re-shows; Back/Continue bounds; the agents
  step's Continue rule.
- `AgentSetup` with a scripted locator, runner and sign-in checks: each state transition, install →
  installed → sign in → ready, failure keeps the reason, a missing package manager offers the
  download page, re-detection after the sheet closes.
- `AgentInstaller`: each CLI's install and login commands (the exact strings, with their source).
- `FileAccess` with scripted probes: each folder's state, Full Disk Access detection, polling stops
  when granted or the panel closes.
- UI: screenshots of every step at the default window size, light and dark, Reduce Motion; the guide
  panel docked beside System Settings. A live install is opt-in (`XBOT_LIVE_ONBOARDING=1`) and runs
  in a sandboxed home.
