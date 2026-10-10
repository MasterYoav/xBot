# The Mac app

A Swift package in `apps/mac`. Swift 6 language mode, macOS 26, Apple silicon.

## Modules

Dependencies point one way:

```
XBotApp ── XBotUI ── XBotCore ── XBotBrain   (Foundation only)
```

| Module | Owns |
| --- | --- |
| `XBotBrain` | `Brain`, `BrainEvent`, `TurnRequest`; `HarnessKind` (arguments and stream parsing per CLI); `HarnessBrain` (one process per turn); `HarnessLocator` (finding CLIs and the login-shell `PATH`) |
| `XBotCore` | Models (`Project`, `Chat`, `ChatMessage`, `Part`); `Database` and `Store` (SQLite); `Workspace`, the `@MainActor @Observable` object the window talks to; `AbilityCatalog` (connectors, plugins, skills, MCPs through the agents' CLIs), `ProjectNotes` (`<project>/notes/*.md`), and the crew: `Agent` (a persona over a CLI, with a pixel `AgentAvatar` and role instructions sent on every turn), HeadMaster's hand-offs, `WorkplaceWorld` (the Agents page's map), and `TerminalDeck` (each chat's floating terminal windows; the shells are SwiftTerm views in `XBotUI/Terminal`). Re-exports `XBotBrain`. |
| `XBotUI` | The design system; `RootView`, the sidebar, chat tabs, transcript and composer |
| `XBotApp` | `@main`, menus, Sparkle, quitting cleanly (`AppDelegate` stops running turns so their replies are saved) |

`XBotBrain` never imports SwiftUI. Views hold no logic: they read the workspace and call its
methods.

## Tests

- Stream parsers are tested against JSON lines recorded from real CLI runs
  (`Tests/XBotBrainTests/Fixtures`). When a CLI changes its format, record a new fixture.
- `HarnessBrain` is tested against fake CLIs — small shell scripts — that check the prompt arrived
  on stdin, that cancelling kills the process, and that an exit without a result is a failure.
- `Workspace` is tested with a scripted `Brain` and an in-memory store.
- Abilities parsers are tested against CLI output recorded on a real Mac
  (`Tests/XBotCoreTests/Fixtures/abilities`, personal paths and secrets removed); the catalog's
  actions run against a scripted `CommandRunner`.
- `LiveHarnessTests` runs real turns against the installed CLIs, only with `XBOT_LIVE_HARNESS=1`.

```sh
scripts/generate-app-icon.sh          # once, on a fresh clone
cd apps/mac && swift build --build-tests && swift test
```
