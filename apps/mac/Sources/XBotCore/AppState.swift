import Foundation
import XBotEngine
import XBotRuntime

/// What the whole app reads from, and sends intents to.
///
/// ponytail: one object, not the five stores docs/05-mac-app.md lists. Agents, channels and
/// settings are separate stores in the spec because they will have separate logic — but they do not
/// yet, and four empty classes forwarding to one array is more places to look, not fewer. Split
/// when a store earns its own behaviour (settings persistence and provider probing will earn it
/// first); the split is mechanical because views already go through intents rather than reaching
/// into the arrays.
///
/// `@MainActor` on the whole thing, without exceptions. Everything here is read during layout.
@Observable
@MainActor
public final class AppState {
    private var engine: any EngineClient

    /// Set only when `AppState` owns the engine's lifecycle rather than being handed a fixed
    /// client. Nil for `StubEngineClient` and for tests that construct `AppState(engine:)` directly.
    private let runtime: RuntimeController?
    private let environmentFactory: (@Sendable (UInt16, String) -> [String: String])?
    private let engineFactory: (@Sendable (EngineEndpoint) -> any EngineClient)?
    private var runtimeObservation: Task<Void, Never>?

    public private(set) var agents: [Agent] = []
    public private(set) var channels: [Channel] = []
    public private(set) var messages: [Message] = []

    /// Nil until the first load resolves, so the rail does not paint a selection that then moves.
    public var selectedAgentID: Agent.ID?

    /// Why the composer is disabled, or nil if it is not.
    public private(set) var composerBlock: ComposerBlock?

    /// What the floating pill says, or nil.
    ///
    /// Nil when everything is fine. The spec is explicit: do not confirm good news. A pill that is
    /// always present stops carrying information.
    public private(set) var status: Status?

    public enum Status: Hashable, Sendable {
        case startingUp
        case reconnecting
        case updating

        public var sentence: String {
            switch self {
            case .startingUp: String(localized: "Starting up")
            case .reconnecting: String(localized: "Reconnecting")
            case .updating: String(localized: "Updating")
            }
        }
    }

    /// The turn currently streaming, if any. One per channel would be right for multi-agent; one
    /// here is right for a window that shows a single conversation at a time.
    private var turn: Task<Void, Never>?

    // MARK: - The right panel

    public enum PanelSection: String, CaseIterable, Identifiable, Sendable {
        case screen, activity, routines, settings
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .screen: String(localized: "Screen")
            case .activity: String(localized: "Activity")
            case .routines: String(localized: "Routines")
            case .settings: String(localized: "Agent settings")
            }
        }

        public var symbol: String {
            switch self {
            case .screen: "display"
            case .activity: "list.bullet.rectangle"
            case .routines: "clock.arrow.circlepath"
            case .settings: "slider.horizontal.3"
            }
        }
    }

    public var isPanelVisible = true {
        didSet { retuneScreen() }
    }
    public var panelSection: PanelSection = .screen {
        didSet { retuneScreen() }
    }

    /// Held in the client for the open conversation, and gone on reload.
    ///
    /// A window, not a record. The record is the audit trail, server-side — the panel says so, and
    /// this property being in-memory is that sentence expressed as a design rather than a caption.
    public private(set) var activity: [ActivityEntry] = []

    public private(set) var screenFrame: ScreenFrame?
    public private(set) var control: ScreenControl = .agent
    public private(set) var models: [ModelSelection] = []

    private var screenTask: Task<Void, Never>?

    /// True while a turn is in flight, which is what makes the screen poll fast.
    private var isTurnRunning = false

    /// The agent currently answering, if any. The rail draws its working ring from this.
    public var workingAgentID: Agent.ID? {
        isTurnRunning ? selectedAgentID : nil
    }

    public init(engine: any EngineClient) {
        self.engine = engine
        self.runtime = nil
        self.environmentFactory = nil
        self.engineFactory = nil
    }

    /// The app's real path: `AppState` owns nothing about *how* the engine runs, only that it
    /// watches `runtime` and swaps in a live client the moment one is reachable.
    ///
    /// `engine` starts as `UnavailableEngineClient()` — not an optional — so every existing call
    /// site keeps working unchanged whether the engine has never started, just stopped, or is
    /// running for real. `environment` is `RuntimeController.start(environment:)`'s own closure
    /// shape, kept at the call site rather than assembled here: building an `EngineEnvironment`
    /// needs a key-encryption key, and that is a security decision this type should not be the one
    /// making.
    public init(
        runtime: RuntimeController,
        environment: @escaping @Sendable (UInt16, String) -> [String: String],
        engineFactory: @escaping @Sendable (EngineEndpoint) -> any EngineClient = {
            HTTPEngineClient(baseURL: $0.baseURL)
        }
    ) {
        self.engine = UnavailableEngineClient()
        self.runtime = runtime
        self.environmentFactory = environment
        self.engineFactory = engineFactory
    }

    public var selectedAgent: Agent? {
        agents.first { $0.id == selectedAgentID }
    }

    private var selectedChannelID: Channel.ID? {
        guard let selectedAgentID else { return nil }
        return channels.first { $0.agentIds.contains(selectedAgentID) }?.id
    }

    public func load() async {
        guard let runtime else {
            status = .startingUp
            await refreshFromEngine()
            return
        }
        // Applied directly, before subscribing — not left to the background observation task's
        // first event. `Task { for await event in await runtime.events { ... } }` starting is not
        // ordered against `load()` returning, and a caller that reads `composerBlock` the instant
        // `load()` completes (every test in RuntimeConnectedTests does exactly that) would see it
        // one event behind. `observeRuntime()` still re-applies this same state as its own first
        // event when it subscribes; that is redundant, not wrong.
        _ = await runtime.detect()
        await apply(await runtime.state)
        observeRuntime()
    }

    /// Agents, channels, the current conversation, and the model list — the one thing `load()`
    /// and a fresh `.running` transition both need, so they say so identically rather than by
    /// agreement between two separate copies of the same five calls.
    private func refreshFromEngine() async {
        do {
            agents = try await engine.agents()
            channels = try await engine.channels()
            if selectedAgentID == nil { selectedAgentID = agents.first?.id }
            await loadMessages()
            await loadPanel()
            models = (try? await engine.availableModels()) ?? []
            status = nil
        } catch {
            // Honest degradation: the rail is empty because the engine is down, and the composer
            // says so. Never an empty state that implies there is simply nothing here.
            status = .reconnecting
            composerBlock = .engineNotRunning
        }
    }

    /// Start watching the runtime's state machine, once. Every state it can report already has a
    /// UI representation (docs/07-container-runtime.md) — this is only the translation into what
    /// `Conversation` and `Composer` already know how to render.
    private func observeRuntime() {
        guard runtimeObservation == nil, let runtime else { return }
        runtimeObservation = Task { [weak self] in
            for await event in await runtime.events {
                guard case .stateChanged(let runtimeState) = event else { continue }
                guard let self else { return }
                await self.apply(runtimeState)
            }
        }
    }

    private func apply(_ runtimeState: RuntimeState) async {
        switch runtimeState {
        case .notDetected(let probe):
            engine = UnavailableEngineClient()
            status = nil
            switch probe {
            case .absent:
                composerBlock = .runtimeUnavailable
            case .installedNotRunning, .ready:
                // Ready-but-notDetected is a brief probe race; treat it as "start me."
                composerBlock = .engineNotRunning
            }
        case .stopped:
            engine = UnavailableEngineClient()
            composerBlock = .engineNotRunning
            status = nil
        case .failed(let error):
            engine = UnavailableEngineClient()
            composerBlock = .engineFailed(reason: error.sentence)
            status = nil
        case .pulling, .starting:
            status = .startingUp
        case .running(let endpoint):
            guard let engineFactory else { return }
            engine = engineFactory(endpoint)
            composerBlock = nil
            await refreshFromEngine()
        case .degraded:
            // The conversation stays readable and usable — docs/09-ui-spec.md is explicit that a
            // health blip must not yank away what is already loaded.
            status = .reconnecting
        }
    }

    /// Bring the engine up. A no-op without a runtime to ask — `AppState(engine:)` has none, and
    /// its composer is never in the `.engineNotRunning` state that would call this anyway.
    public func startEngine() {
        guard let runtime, let environmentFactory else { return }
        Task { await runtime.start(environment: environmentFactory) }
    }

    /// What the composer's inline action button does, keyed by the same reason that put it there.
    public func handleComposerBlockAction() {
        switch composerBlock {
        case .engineNotRunning, .engineFailed:
            startEngine()
        case .humanHoldsControl:
            setControl(.agent)
        case .runtimeUnavailable, .noModelConnected, nil:
            // Runtime install is M6. Settings isn't a scene yet (M6/M7).
            break
        }
    }

    /// Create an agent and open it. Optimistic on the rail: the row exists before the channel
    /// round-trip finishes, so the fill never waits on a second request.
    public func createAgent(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = AgentDraft(
            name: trimmed.isEmpty ? String(localized: "New agent") : trimmed,
            label: ""
        )
        Task { [engine] in
            guard let agent = try? await engine.createAgent(draft) else { return }
            agents.append(agent)
            select(agent.id)
            if let channel = try? await engine.createChannel(agentIds: [agent.id]) {
                channels.append(channel)
                if selectedAgentID == agent.id {
                    await loadMessages()
                    await loadPanel()
                }
            }
        }
    }

    public func select(_ id: Agent.ID) {
        guard id != selectedAgentID else { return }
        selectedAgentID = id
        // The selection does not wait for the conversation. It is applied now; messages catch up.
        turn?.cancel()
        turn = nil
        messages = []
        activity = []
        screenFrame = nil
        Task {
            await loadMessages()
            await loadPanel()
        }
    }

    private func loadPanel() async {
        guard let agent = selectedAgentID else { return }
        activity = (try? await engine.activity(for: agent)) ?? []
        retuneScreen()
    }

    /// Match the polling cadence to what is actually on screen.
    ///
    /// Stopped when the panel is hidden or showing something else — an app that keeps requesting
    /// screenshots nobody is looking at is the reason laptops get warm, and this is the product
    /// whose whole pitch is that it runs on your own machine.
    private func retuneScreen() {
        screenTask?.cancel()
        guard let agent = selectedAgentID else { return }

        let cadence: ScreenCadence =
            (isPanelVisible && panelSection == .screen)
            ? (isTurnRunning ? .active : .idle)
            : .stopped
        guard cadence.interval != nil else {
            screenTask = nil
            return
        }

        screenTask = Task { [engine] in
            for await frame in engine.screen(for: agent, cadence: cadence) {
                if Task.isCancelled { return }
                screenFrame = frame
            }
        }
    }

    /// Take the browser, or hand it back.
    ///
    /// Optimistic, like sending: the overlay flips immediately because the user pressed the button,
    /// and reverts if the engine refuses. Waiting for a round trip to show that a click registered
    /// is exactly the latency the design system opens by forbidding.
    public func setControl(_ next: ScreenControl) {
        let previous = control
        let previousBlock = composerBlock
        control = next
        // Holding the browser is a composer-level reason, not a toast: the field sits where
        // the user is looking, and "Give it back" is the one action that unblocks it.
        if next == .human {
            composerBlock = .humanHoldsControl
        } else if composerBlock == .humanHoldsControl {
            composerBlock = nil
        }
        Task { [engine, selectedAgentID] in
            guard let agent = selectedAgentID else { return }
            do {
                try await engine.setControl(next, for: agent)
            } catch {
                control = previous
                composerBlock = previousBlock
            }
        }
    }

    public func updateSelectedAgent(_ patch: AgentPatch) {
        guard let id = selectedAgentID else { return }
        Task { [engine] in
            guard let updated = try? await engine.updateAgent(id, patch) else { return }
            if let index = agents.firstIndex(where: { $0.id == id }) {
                agents[index] = updated
            }
        }
    }

    private func loadMessages() async {
        guard let channel = selectedChannelID else {
            messages = []
            return
        }
        messages = (try? await engine.messages(in: channel)) ?? []
    }

    /// Send, optimistically.
    ///
    /// The bubble exists before the request does. A send that fails becomes a retryable bubble
    /// holding the same text — the one thing that must never happen is losing what somebody typed.
    public func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, composerBlock == nil, let channel = selectedChannelID else { return }

        let sent = Message(id: "local-\(UUID().uuidString)", author: .user, text: trimmed, state: .sending)
        messages.append(sent)

        let agentID = selectedAgentID ?? ""
        turn?.cancel()
        isTurnRunning = true
        retuneScreen()
        turn = Task { [engine] in
            defer {
                isTurnRunning = false
                retuneScreen()
            }
            var replyID: String?
            do {
                for try await event in engine.send(trimmed, to: channel) {
                    switch event {
                    case .started(let id):
                        replyID = id
                        mark(sent.id, as: .complete)
                        messages.append(
                            Message(id: id, author: .agent(agentID), text: "", state: .streaming)
                        )
                    case .textDelta(let id, let text):
                        append(text, to: id)
                    case .toolCall(let id, let name, let target):
                        recordTool(name: name, target: target, on: id)
                    case .finished(let id):
                        mark(id, as: .complete)
                    case .failed(let id, let reason):
                        mark(id, as: .failed(reason: reason))
                    }
                }
            } catch {
                mark(replyID ?? sent.id, as: .failed(reason: error.localizedDescription))
            }
        }
    }

    private func append(_ text: String, to id: Message.ID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += text
    }

    private func recordTool(name: String, target: String, on id: Message.ID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].toolCalls.append(
            Message.ToolCall(id: "\(id)-\(messages[index].toolCalls.count)", name: name, target: target)
        )
    }

    private func mark(_ id: Message.ID, as state: Message.State) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].state = state
    }
}
