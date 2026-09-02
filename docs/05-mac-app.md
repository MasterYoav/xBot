# The Mac app

## Platform floor

- **macOS 14 Sonoma** minimum. Buys `@Observable`, modern SwiftUI navigation, and `ContentUnavailableView`.
- **Swift 6**, strict concurrency, complete checking. Not negotiable — this app coordinates a
  container runtime, a network client, and a streaming parser, and data races there produce bugs
  that reproduce once a fortnight.
- **Apple silicon and Intel.** Universal binary. The container runtime story differs by
  architecture — see [ADR-0003](decisions/0003-container-runtime.md).
- **Unsandboxed, hardened runtime, Developer ID, notarized.** A sandboxed app cannot drive a
  container runtime. See [ADR-0005](decisions/0005-distribution-outside-app-store.md).

## Module layout

A Swift package with six targets, plus a thin Xcode app target. Dependencies point one way only.

```
XBotApp          @main, scenes, windows, menu bar, app lifecycle
   ├── XBotOnboarding    first-run flow
   ├── XBotUI            all views + the design system
   ├── XBotCore          models, state, persistence, coordination
   ├── XBotEngine        API client, SSE stream, screen polling
   └── XBotRuntime       container lifecycle, health, images, ports

XBotUI       → XBotCore
XBotCore     → XBotEngine, XBotRuntime
XBotEngine   → (Foundation only)
XBotRuntime  → (Foundation only)
```

**`XBotEngine` and `XBotRuntime` never import `XBotUI` or SwiftUI.** They are testable without a
window. This is what lets the client develop against a stub API while the engine fork is in flight.

### XBotRuntime

Owns the container runtime. Everything the user must never see.

```swift
public actor RuntimeController {
    public private(set) var state: RuntimeState
    public var events: AsyncStream<RuntimeEvent> { get }

    public func detect() async -> RuntimeAvailability
    public func start() async throws
    public func stop() async
    public func restart() async throws
    public func pullImages(progress: @Sendable (PullProgress) -> Void) async throws
    public func diagnostics() async -> Diagnostics
}

public enum RuntimeState: Sendable {
    case notDetected(RuntimeAvailability)
    case stopped
    case pulling(PullProgress)
    case starting(Stage)
    case running(EngineEndpoint)
    case degraded(reason: DegradedReason)
    case failed(RuntimeError)
}
```

Details in [07-container-runtime.md](07-container-runtime.md). The important design property: **the
state machine is explicit and every state has a UI representation.** There is no "probably starting,
let's spin." A spinner with no state behind it is how you get an app the user force-quits.

### XBotEngine

The API client. Three transports:

```swift
public actor EngineClient {
    // REST
    public func agents() async throws -> [Agent]
    public func createAgent(_ draft: AgentDraft) async throws -> Agent
    public func updateAgent(_ id: Agent.ID, _ patch: AgentPatch) async throws -> Agent
    public func channels() async throws -> [Channel]
    public func messages(in: Channel.ID, before: Cursor?) async throws -> Page<Message>

    // SSE — the turn stream
    public func send(_ text: String, to: Channel.ID, attachments: [Attachment])
        -> AsyncThrowingStream<TurnEvent, Error>

    // Polled screenshots
    public func screenStream(for: Agent.ID, cadence: ScreenCadence)
        -> AsyncStream<ScreenFrame>
}
```

**The `TurnEvent` stream is the heart of the app.** AG-UI emits text deltas, tool call starts, tool
results, state patches, and errors. The parser must be:

- **Incremental.** Render tokens as they arrive; never buffer a whole message.
- **Resilient to truncation.** Upstream's own configuration notes that agent endpoints "will be
  redeployed mid-answer" and "will sometimes accept a connection and then write nothing at all."
  A stalled stream must surface as a retryable message state, not a hung composer.
- **Ordered per turn, concurrent across turns.** Two channels can stream at once.

### XBotCore

The state everything else reads. One `@Observable` root, and stores hanging off it.

```swift
@Observable @MainActor
public final class AppState {
    public var runtime: RuntimeState
    public var agents: AgentStore
    public var channels: ChannelStore
    public var settings: SettingsStore
    public var providers: ProviderStore
}
```

**Rule: views read from stores, and send intents to stores.** A view never holds a `URLSession`,
never constructs a request, never parses a response. If `import XBotEngine` appears in a file under
`XBotUI/`, that is a bug.

### XBotUI

Views and the design system. Structure mirrors the UI spec:

```
XBotUI/
├── DesignSystem/      tokens, motion, materials, typography
├── Components/        Avatar, Bubble, Composer, StatusPill, RailItem, …
├── Rail/
├── Conversation/
├── Panel/             Screen · Activity · Routines · Agent settings
├── Settings/
└── Admin/             WKWebView host — see ADR-0004
```

Every view that renders a value the user can change takes it from a store, not a binding threaded
five levels down. Every view that animates uses the motion tokens from `DesignSystem`.

### XBotOnboarding

Kept separate because it runs once, has its own window, and must work when nothing else does — no
engine, no runtime, no database. Making it depend on `AppState` would mean `AppState` has to model
"nothing exists yet," which pollutes it forever.

See [06-onboarding.md](06-onboarding.md).

## Windows and scenes

| Scene | Kind | Notes |
| --- | --- | --- |
| Main | `Window` | Rail, conversation, panel. One at a time. Restores position and selection |
| Onboarding | `Window` | Fixed size, no resize, no minimise. Closes into Main |
| Settings | `Settings` | Standard macOS settings scene, tabbed |
| Agent screen | `WindowGroup` | Optional detached full-size live view, one per agent |
| Menu bar | `MenuBarExtra` | Engine state, quick agent access, start/stop |

**The menu bar item is not decoration.** It is where the runtime state lives when the main window is
closed, and it is the answer to "is this thing running and eating my battery." It shows a dot for
state and offers Stop Engine.

## Threading

- **`@MainActor` on every view model and every store.** No exceptions, no "just this once."
- **`actor` for `EngineClient` and `RuntimeController`.** Both serialise access to a resource.
- **`AsyncStream` / `AsyncThrowingStream` for everything continuous.** Turn events, runtime events,
  screen frames, pull progress. No delegates, no Combine.
- **`Sendable` everywhere it can be.** Strict concurrency will demand it; fighting the compiler here
  produces exactly the design you want.

## Persistence

Three stores, deliberately separate:

| What | Where | Why |
| --- | --- | --- |
| Conversations, agents, audit | **Engine Postgres** | The engine owns product data. The app is a client |
| Window state, selection, appearance | `UserDefaults` | Trivial, non-secret, per-machine |
| API keys, engine token, DB encryption key | **macOS Keychain** | See [10-security.md](10-security.md) |

**The app has no local database.** Tempting — offline history, faster launch — and wrong. Two
sources of truth for conversations means a sync problem, and a sync problem in an app whose whole
value is a local server is self-inflicted. If launch feels slow, cache in memory and paint from the
last known list.

## Offline and degraded behaviour

The engine will be down sometimes: the runtime is updating, the Mac just woke, an image is pulling.

**Rules:**

- **Never show an empty state that implies emptiness.** No agents because the engine is down is not
  "no agents yet." It is "the engine isn't running," with a Start button.
- **The composer disables with a reason**, inline, where the user is looking. Not a toast.
- **Read-only where possible.** If the engine goes down mid-session, the loaded conversation stays
  on screen and scrollable. Losing what you were reading because a container restarted is
  infuriating.
- **Recovery is automatic and visible.** The status pill — the same one in the Grok Bot
  screenshots — shows `Reconnecting`, then goes away. It does not require a click.

## Accessibility

Not a phase. Built in from the first component.

- **VoiceOver** on every control, with labels that describe the action, not the icon.
- **Full keyboard access.** The rail is a list with arrow navigation; `⌘1`–`⌘9` jump to agents
  (visible in the Grok Bot command palette screenshot); `⌘K` opens it; `Tab` cycles panes.
- **Dynamic Type.** Layout scales with text. Spacing in relative units, never fixed points that
  break at accessibility sizes.
- **`accessibilityReduceMotion`** → cross-fades instead of springs, handled inside the motion
  tokens so no call site can forget.
- **`accessibilityReduceTransparency`** → materials go opaque, handled inside the material tokens.
- **`accessibilityDifferentiateWithoutColor`** → the runtime status dot gets a shape as well as a
  colour.

## Testing

| Layer | Approach |
| --- | --- |
| `XBotRuntime` | Unit tests against a fake runtime driver. Every state transition, including failures |
| `XBotEngine` | Recorded fixtures. Especially: truncated SSE, malformed events, mid-stream disconnect |
| `XBotCore` | Unit tests on stores and reducers |
| `XBotUI` | Snapshot tests, light and dark, at default and accessibility text sizes |
| End to end | XCUITest against a real engine in CI: onboard → create agent → send → receive |

**The stub engine is a first-class deliverable.** `XBotEngine` ships a `StubEngineClient` conforming
to the same protocol, serving fixtures. It is how the client team works while the fork is in flight,
how snapshot tests stay deterministic, and how a designer runs the app without Docker.
