# The Mac app

A Swift package in `apps/mac`. Swift 6 language mode with strict concurrency, macOS 26, Apple
silicon. Two dependencies: [Sparkle](https://sparkle-project.org) for updates and
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for terminals. The iPhone and iPad app in
`apps/ios` builds three of this package's libraries; see [its page](14-iphone-and-ipad.md).

## Modules

Dependencies point one way:

```
XBotApp ── XBotUI ── XBotCore ─┬─ XBotBrain     (Foundation only)
                               ├─ XBotTools     (Foundation only; also linked by XBotApp)
                               ├─ XBotRemote    (Foundation + Network; also built for iOS)
                               └─ XBotWorld     (SwiftUI; also built for iOS)
XBotMarkdown                                    (Foundation; used by the iOS app)
```

| Module | Owns |
| --- | --- |
| `XBotBrain` | `Brain`, `BrainEvent`, `TurnRequest`; `HarnessKind` (each CLI's arguments, permission flags and abilities); `HarnessBrain` (one process per turn); `HarnessLocator` (finding the CLIs and the login-shell `PATH`); the stream parsers (`ClaudeStream`, `CodexStream`, `MoreStreams` for Antigravity and Copilot, `SchemaTail`); `Effort`; `RateLimits` |
| `XBotTools` | Agentic Mode's xbot MCP server as `XBot --mcp` speaks it: `JSONValue`, `MCPServer` (JSON-RPC 2.0: initialize, ping, tools/list, tools/call), `MCPStdio`, `ToolCatalog` (every tool and its schema), `ToolResult` and `ToolCall`, and the Unix socket (`ToolClient`, `ToolSocketListener`) |
| `XBotRemote` | The wire to the phone: `HostMessage` and `ClientMessage`, the value types they carry, `Frame` (length-prefixed JSON), `PairingKey` and `PairingInvite`, `LocalTransport` (TLS-PSK listener and browser, `FramedConnection`) and `CloudTransport` (`CloudChannel` over a `CloudMailbox`; `CloudKitMailbox` is the real one) |
| `XBotWorld` | The crew's look and home, shared with the phone: `AgentAvatar` and `AvatarSprite` (pixel avatars), `WorkplaceWorld` (who stands and walks where), the five realms and `WorkplaceBackdrop`, `WorldStage` (the drawn world, in tiers by rank), `OrgChart` (who reports to whom, suggested managers), `Motion` (the `motionPaused` environment value) |
| `XBotMarkdown` | `MarkdownDocument` (a Markdown file as blocks that keep their exact source, so an edit changes only what was touched) and `InlineMarkdown` |
| `XBotCore` | Models (`Project`, `Chat`, `ChatMessage`, `Part`); `Database` and `Store` (SQLite, schema v6); `Workspace`, the `@MainActor @Observable` object every view and the remote talk to, split by feature (`+Plan`, `+Edit`, `+Panels`, `+Home`, `+Abilities`, `Agents/`, `Automations/`); `Git/` (status, diffs, pull requests through `gh`, a folder watcher); `History/` (the profile, built from the CLIs' own history); `Abilities/` (connectors, plugins, skills and MCP servers through the CLIs); `Notes`; `Usage`; `Appearance` and `AsciiWallpaper`; `TerminalDeck` (each chat's terminal window and its tabs); `Onboarding/` (`OnboardingModel`: the welcome tour's steps and completion; `AgentSetup` and `AgentInstaller`: finding, installing and signing in to the CLIs; `FileAccess`: folder grants and Full Disk Access); `Remote/` (`RemoteService`: pairing, the lanes, keep-awake; `RemoteHost` and one extension per feature; `RemoteShell`); `Agentic/` (`ApprovalCenter`, `ExperienceStore`, `RiskRules`, `ToolHost` and its xbot and mac tools, `QuestionCenter`, `MacControlling` with `LiveMac` and `MacControlAccess`, `ToolHook`, `AntigravityMCP`) and `Workspace+Agentic`. Re-exports `XBotBrain` and `XBotWorld` |
| `XBotUI` | The design system and every view: `Shell/` (root, sidebar, top bar, Home), `Chat/` (transcript, composer, plan cards, effort control), `Inspector/`, `Agents/`, `Abilities/`, `Notes/`, `Automations/`, `Profile/`, `Account/`, `Settings/`, `Terminal/` (SwiftTerm views), `Onboarding/` (the welcome tour, its step views, the install sheet, the Full Disk Access guide panel, and `Scenes/`), `Components/` |
| `XBotApp` | `@main`, menus and commands, Sparkle, the app icon, quitting cleanly (`AppDelegate` stops running turns so their replies are saved), the headless `--automations-tick` run for the automations helper, and the headless `--mcp` (the xbot MCP server) and `--hook` (Claude Code's PreToolUse hook) |

`XBotBrain` and `XBotRemote` never import SwiftUI. Views hold no logic: they read the workspace and
call its methods. The remote calls the same methods, so the phone and the Mac's window can't
behave differently.

## Where things are stored

`~/Library/Application Support/xBot/xbot.sqlite` (projects, chats, messages, usage, agents,
automations) and `Inbox/` for loose chats; notes in `<project>/notes/`; settings in user defaults;
pairing keys in the Keychain. See [architecture](02-architecture.md#storage).

## Tests

633 tests, Swift Testing, in seven targets: `XBotBrainTests`, `XBotCoreTests`, `XBotToolsTests`,
`XBotRemoteTests`, `XBotWorldTests`, `XBotMarkdownTests` and `XBotUITests`. (`Tests/XBotRuntimeTests` is an empty
folder left from 1.x.)

- **Agentic tools**: `RiskRules` both ways for every rule; the MCP server's JSON-RPC and a whole
  stdio session against a fake app socket; the socket's mode, token and concurrency; every xbot and
  mac tool against a scripted workspace and a `FakeMac` (no real click, key or screenshot);
  approvals allowed, refused, expired and the Mac-alert path; each CLI's arguments with the tools
  attached; the hook's exit codes.
- **Stream parsers** are tested against lines recorded from real CLI runs
  (`Tests/XBotBrainTests/Fixtures`, personal paths removed). When a CLI changes its format, record a
  new fixture; never hand-write one from documentation.
- **`HarnessBrain`** is tested against fake CLIs (small shell scripts) that check the prompt arrived
  where it should, that cancelling kills the process, and that an exit without a result is a
  failure.
- **`Workspace`** is tested with a scripted `Brain` and an in-memory store: chats, plans, edits,
  hand-offs and the org chart (`OrgTests`), automations, panels, the profile.
- **Abilities** parsers are tested against CLI output recorded on a real Mac
  (`Tests/XBotCoreTests/Fixtures/abilities`, personal paths and secrets removed); the catalog's
  actions run against a scripted `CommandRunner`.
- **The remote**: every wire message round-trips, the local transport over loopback (a wrong key is
  refused), the cloud channel against a fake mailbox, and `RemoteHost` for each feature.
- **Onboarding**: `OnboardingModel` (first launch, completion and its version, skip and Home's
  reminder, reopening, existing libraries, Back/Continue and the agents rule); `AgentSetup` with a
  scripted Mac (each state, install → sign in → ready, failures keep their reason, a missing tool
  offers its page, looking again after a run); `AgentInstaller`'s exact commands and sources;
  `FileAccess` with scripted probes (no prompt on appearing, each folder, Full Disk Access, polling
  stops on grant, close or cancel); the guide panel's docking geometry (`GuideDockTests`).
- **The world**: `OrgChartTests` (tiers, loops, suggestions by role) and `WorkplaceWorld`'s slots.
- **Live**, opt-in: `LiveHarnessTests` runs real turns against the installed CLIs with
  `XBOT_LIVE_HARNESS=1`; `scripts/e2e_automations.py` has launchd run automations through the
  installed app (xBot must be closed). The phone's live tests are on
  [its page](14-iphone-and-ipad.md#tests).

```sh
scripts/generate-app-icon.sh          # once, on a fresh clone (compiles xBot.icon; needs Xcode 26)
cd apps/mac && swift build --build-tests && swift test
```

CI (`.github/workflows/ci.yml`) runs the same commands on a macOS 26 runner. Its Swift is older
than a current Xcode's, so two rules keep it building: don't pass a method reference as a
`Binding` setter (the compiler crashes), and annotate closure types where inference is long.
