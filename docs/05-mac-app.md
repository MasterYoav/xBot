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

A Swift package with six library/executable targets. **SwiftPM only** — there is no Xcode project
file; build with `swift build` or `swift run`. Dependencies point one way only.

```
XBotApp          @main, scenes, windows, app lifecycle (menu bar planned, not shipped)
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
public protocol EngineClient: Sendable {
    // REST — agents, channels, messages, plugins, handoff grants
    public func agents() async throws -> [Agent]
    // …

    // SSE — the turn stream
    public func send(_ text: String, to: Channel.ID)
        -> AsyncThrowingStream<TurnEvent, Error>

    // Polled screenshots
    public func screen(for: Agent.ID, cadence: ScreenCadence)
        -> AsyncStream<ScreenFrame>
}
```

Implementations: `HTTPEngineClient` (loopback + bearer token), `StubEngineClient` (fixtures),
`UnavailableEngineClient` (engine down).

**The `TurnEvent` stream is the heart of the app.** AG-UI emits text deltas, tool call starts, tool
results, state patches, and errors. The parser must be:

- **Incremental.** Render tokens as they arrive; never buffer a whole message.
- **Resilient to truncation.** Upstream's own configuration notes that agent endpoints "will be
  redeployed mid-answer" and "will sometimes accept a connection and then write nothing at all."
  A stalled stream must surface as a retryable message state, not a hung composer.
- **Ordered per turn, concurrent across turns.** Two channels can stream at once.

### XBotCore

The state everything else reads. One `@Observable` root today — stores split when they earn their
own behaviour (see inline comment in `AppState.swift`).

```swift
@Observable @MainActor
public final class AppState {
    public private(set) var agents: [Agent]
    public private(set) var channels: [Channel]
    public private(set) var messages: [Message]
    // runtime observation, panel, plugins, handoff grants, composer block, …
}
```

Provider keys and connection state live in `ProviderKeyStore`, `ProviderConnectionStore`, and
`EngineTokenStore` — not yet a dedicated Settings store.

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
| Main | `Window` | Rail, conversation, panel. Onboarding crossfades in via `AppShellView` on first run |
| Onboarding | (in Main) | Fixed-size window mode during first run; not a separate scene |
| Settings | `Settings` | General placeholder + Advanced (Plugins…) today |
| Plugins admin | `Window` | `WKWebView` at engine `/admin/plugins` |
| Agent screen (detached) | — | **Not built** |
| Menu bar | — | **Not built** — planned for runtime status when the main window is closed |

**The menu bar item is planned, not shipped.** When it exists, it is where the runtime state lives
when the main window is closed.

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
| Engine loopback port | `UserDefaults` | Stable across relaunch so bookmarks and the admin webview do not drift |
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
| `XBotRuntime` | Unit tests against `FakeDriver`. State transitions including container adoption |
| `XBotEngine` | Unit tests on HTTP client, SSE parser, AG-UI decoder, plugin JSON decoding |
| `XBotCore` | Unit tests on `AppState`, provider stores, onboarding version |
| `XBotOnboarding` | Failure-branch tests with fake runtime |
| `XBotUI` | **No snapshot or XCUITest yet** — planned |
| End to end | `scripts/verify-m5-handoff.sh` against a live engine; full XCUITest not yet |

**The stub engine is a first-class deliverable.** `XBotEngine` ships a `StubEngineClient` conforming
to the same protocol as `HTTPEngineClient`, serving fixtures. Tests and snapshot work stay
deterministic. **Debug builds default to the stub** so `swift run` shows the designed conversation
without Docker; set `XBOT_USE_RUNTIME=1` to exercise `RuntimeController` + `DockerDriver` instead.
Release builds always construct the runtime path and hold `UnavailableEngineClient` until the
runtime is `.running`.
