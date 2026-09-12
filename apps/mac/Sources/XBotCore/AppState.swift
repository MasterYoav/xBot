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
    /// Every open conversation's messages, keyed by channel.
    ///
    /// Keyed rather than a single array because a turn outlives the selection. Switching agents used
    /// to cancel the reply that was streaming — the agent was mid-answer and it was silently thrown
    /// away — and a single array is why: there was nowhere for a background turn to write.
    private var messagesByChannel: [Channel.ID: [Message]] = [:]
    private var historyProblems: [Channel.ID: String] = [:]
    public var historyProblem: String? { selectedChannelID.flatMap { historyProblems[$0] } }
    public private(set) var creationProblem: String?
    public private(set) var isCreatingAgent = false
    private var pendingAgentDraft: AgentDraft?
    public private(set) var isCreatingConversation = false
    public private(set) var conversationCreationProblem: String?
    public var needsConversation: Bool { selectedAgentID != nil && selectedChannelID == nil }
    public var canSend: Bool {
        composerBlock == nil && selectedChannelID != nil && !isTurnInFlight
    }

    /**
     Why a send has to wait, for the composer to say beside itself. Nil when it does not, and nil when
     a `composerBlock` is already saying something — one reason at a time.

     One turn runs at a time across the whole app, because there is one running channel. That is a
     fair limit, but on its own it greyed out every conversation's field while any agent answered,
     with nothing on screen to say so: switch to a second agent mid-reply and its composer was simply
     dead. docs/09 — "disabled with a reason, inline… never a silent no-op".
     */
    public var sendBlockedReason: String? {
        guard composerBlock == nil else { return nil }
        guard selectedChannelID != nil else {
            return String(localized: "Open a conversation to send a message.")
        }
        guard let runningChannel else { return nil }
        if runningChannel == selectedChannelID {
            return String(localized: "Wait for this reply to finish before sending another.")
        }
        let name = agents.first { $0.id == runningAgent }?.name ?? String(localized: "Another agent")
        return String(localized: "\(name) is still answering. You can send when it's done.")
    }
    // Keep failed local turns until they are retried, rather than replacing them with remote history.
    private var retryPrompts: [Message.ID: (channel: Channel.ID, prompt: Message.ID)] = [:]
    private var historyRequests: [Channel.ID: UUID] = [:]

    /// The selected conversation. Unchanged for every reader; only the storage moved.
    public var messages: [Message] {
        guard let channel = selectedChannelID else { return [] }
        return messagesByChannel[channel] ?? []
    }

    /// Agents whose reply arrived while you were looking at someone else.
    ///
    /// The rail's dot, and the reason a background turn is worth keeping: an answer that finished
    /// somewhere you were not looking is exactly what a badge is for.
    public private(set) var unreadAgents: Set<Agent.ID> = []

    /// Agents that have stopped and put a question to you, by the question they asked.
    ///
    /// The engine's `ask_person` tool ends a Bot's turn by asking whoever stands behind the work
    /// (`server/src/agents/escalation.ts`), so an outstanding call is exactly "blocked on you" —
    /// the rail's attention badge, which docs/09 calls the important one: an agent waiting on a
    /// person that nobody notices is what makes the product feel unreliable.
    public private(set) var questionsForYou: [Agent.ID: String] = [:]

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
        /*
         * Carrying which kind of degraded, because there are three and they are not the same news.
         *
         * `DegradedReason` exists to keep "the API answering while the computer is down" apart from
         * health flapping after the Mac wakes — its own note says collapsing that into `failed`
         * makes the app cry wolf and collapsing it into `running` makes it lie. This used to be a
         * bare `.reconnecting`, which collapsed all three again one level further down, so an agent
         * whose browser had crashed showed "Reconnecting": nothing was reconnecting, and the reason
         * its screen had gone blank was the one thing the pill could have said.
         */
        case degraded(RuntimeState.DegradedReason)
        case updating

        public var sentence: String {
            switch self {
            case .startingUp: String(localized: "Starting up")
            // The reason's own wording, so there is one source for it rather than two that drift.
            case .degraded(let reason): reason.sentence
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
    /// The agent rail. Toggled from the title bar; hidden state is remembered for the session.
    /// Whether the settings surface is showing in place of the conversation.
    ///
    /// In the window rather than a separate `Settings` scene: xBot's settings are part of using the
    /// app — connecting a model is step four of onboarding, not an afterthought — and a second
    /// floating window puts them somewhere the person has to go and find. It also loses the rail,
    /// so which agent is selected stops being visible while its model is being changed.
    public var isShowingSettings = false

    public var isRailVisible = true
    public var panelSection: PanelSection = .screen {
        didSet { retuneScreen() }
    }
    public var modelBannerDismissed = false

    /// Held in the client for the open conversation, and gone on reload.
    ///
    /// A window, not a record. The record is the audit trail, server-side — the panel says so, and
    /// this property being in-memory is that sentence expressed as a design rather than a caption.
    public private(set) var activity: [ActivityEntry] = []

    public private(set) var screenFrame: ScreenFrame?
    public private(set) var control: ScreenControl = .agent
    public private(set) var models: [ModelSelection] = []

    /// Loopback origin when the engine is running. Used for admin webviews.
    public private(set) var engineBaseURL: URL?

    /// Pinned container image the runtime is using, when known.
    public private(set) var pinnedEngineImage: String?

    /// Result of the last engine update check from Settings → Updates.
    public private(set) var engineUpdateStatus: EngineUpdateStatus?

    public private(set) var isCheckingEngineUpdate = false

    public private(set) var isInstallingEngineUpdate = false

    /// Outcome of the most recent engine update install, if any.
    public private(set) var lastEngineUpgradeOutcome: EngineUpgradeOutcome?

    /// Sparkle when release metadata is bundled; inert in local SwiftPM runs.
    public let appUpdates: any AppUpdateControlling

    /// True when this state owns a `RuntimeController` (production / runtime debug), not a fixed stub.
    public var hasManagedRuntime: Bool { runtime != nil }

    /// Tools and skills granted to the selected agent.
    public private(set) var grantedPlugins: GrantedPlugins?
    public private(set) var grantedPluginsLoading = false

    /// Deployment-wide plugin catalogue and connected servers.
    public private(set) var pluginsPage: PluginsPage?
    public private(set) var pluginsPageLoading = false

    /// Which agents the selected one may hand work to.
    public private(set) var handoffGrants: HandoffGrants?
    public private(set) var handoffGrantsLoading = false

    /// Path under the engine origin for the plugins admin webview.
    public var pluginsAdminDeepLink = "admin/plugins"

    /// Full URL for the plugins admin webview, if the engine is running.
    public var pluginsAdminURL: URL? {
        guard let engineBaseURL else { return nil }
        return engineBaseURL.appending(path: pluginsAdminDeepLink)
    }

    /// Bearer token for admin webviews. Read from the Keychain each time — never stored on state.
    public var pluginsAdminToken: String? {
        try? EngineTokenStore.token()
    }

    private var screenTask: Task<Void, Never>?

    /// The conversation a turn is streaming into, if any.
    private var runningChannel: Channel.ID?
    /// The agent answering it. Held separately because the selection may have moved on.
    private var runningAgent: Agent.ID?

    /// True while a turn is in flight, which is what makes the screen poll fast.
    private var isTurnRunning: Bool { runningChannel != nil }

    /// The agent currently answering, if any. The rail draws its working ring from this.
    ///
    /// The agent that is answering, not the one that is selected. Those were the same thing while a
    /// turn could not outlive the selection; now the ring follows the work.
    public var workingAgentID: Agent.ID? { runningAgent }

    /// Whether a reply is currently streaming. Engine updates must wait for this to finish.
    public var isTurnInFlight: Bool { isTurnRunning }

    public init(
        engine: any EngineClient,
        providers: ProviderConnectionStore = .shared,
        appUpdates: any AppUpdateControlling = DisabledAppUpdateController.shared,
        conversationStore: @escaping @Sendable () -> ConversationStore = { .ready }
    ) {
        self.conversationStore = conversationStore
        self.engine = engine
        self.runtime = nil
        self.environmentFactory = nil
        self.engineFactory = nil
        self.providers = providers
        self.appUpdates = appUpdates
        wireAppUpdateBlocking()
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
        },
        /// Injected so a test gets its own preference domain. See `ProviderConnectionStore`.
        providers: ProviderConnectionStore = .shared,
        appUpdates: any AppUpdateControlling = DisabledAppUpdateController.shared,
        /// Defaults to the real credential, because this initializer is the production one.
        conversationStore: @escaping @Sendable () -> ConversationStore = { EngineBootstrap.conversationStore }
    ) {
        self.conversationStore = conversationStore
        self.engine = UnavailableEngineClient()
        self.runtime = runtime
        self.environmentFactory = environment
        self.engineFactory = engineFactory
        self.providers = providers
        self.appUpdates = appUpdates
        wireAppUpdateBlocking()
    }

    private func wireAppUpdateBlocking() {
        appUpdates.bindUpdateBlockingActivity { [weak self] in
            self?.isTurnInFlight ?? false
        }
    }

    /// Which providers are connected, and whether the composer may send. Held rather than reached
    /// for statically, so this state's behaviour does not depend on the machine it runs on.
    private let providers: ProviderConnectionStore

    /// Endpoints the person added by hand, which the agent picker offers alongside the vendors.
    private let customProviders = CustomProviderStore.shared

    /// Whether the engine can keep a conversation at all.
    ///
    /// Injected rather than read from the Keychain here, for the reason `ProviderConnectionStore`
    /// documents: a state object that reaches for a machine-wide store cannot be asserted without
    /// the machine's contents deciding the answer.
    private let conversationStore: @Sendable () -> ConversationStore

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
            if models.isEmpty {
                let gateway = await runtime?.hostGateway ?? "host.docker.internal"
                models = ModelProviderCatalog.selections(
                    forConnectedProviders: providers.connectedProviderIDs,
                    custom: customProviders.all,
                    hostGateway: gateway
                )
            }
            status = nil
            if runtime != nil, providers.requiresModelForComposer() {
                composerBlock = .noModelConnected
            }
        } catch {
            // Honest degradation: the rail is empty because the engine is down, and the composer
            // says so. Never an empty state that implies there is simply nothing here.
            // The engine stopped answering, which is what `healthLost` names — the same word the
            // runtime uses when its own probe stops coming back.
            status = .degraded(.healthLost)
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

    /// The runtime's own state, mirrored for the surfaces that report on the engine itself.
    ///
    /// `status` and `composerBlock` say what the *conversation* should show, which is a narrower
    /// question — several runtime states collapse into "the engine isn't running" there, and a
    /// settings pane reporting on the engine needs to tell them apart.
    public private(set) var runtimeState: RuntimeState?

    private func apply(_ runtimeState: RuntimeState) async {
        self.runtimeState = runtimeState
        if case .running = runtimeState {} else {
            idleWatch?.cancel()
            idleWatch = nil
        }
        switch runtimeState {
        case .notDetected(let probe):
            engine = UnavailableEngineClient()
            engineBaseURL = nil
            engineHealth = nil
            grantedPlugins = nil
            pluginsPage = nil
            handoffGrants = nil
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
            engineBaseURL = nil
            engineHealth = nil
            grantedPlugins = nil
            pluginsPage = nil
            handoffGrants = nil
            // The app's own pause reads differently from a stop somebody chose or a crash: nothing
            // is wrong, and a message is all it takes to carry on.
            composerBlock = pausedWhenIdle ? .enginePausedWhenIdle : .engineNotRunning
            status = nil
        case .failed(let error):
            engine = UnavailableEngineClient()
            engineBaseURL = nil
            engineHealth = nil
            grantedPlugins = nil
            pluginsPage = nil
            handoffGrants = nil
            composerBlock = .engineFailed(reason: error.sentence)
            status = nil
            pausedWhenIdle = false
            failMessageThatWokeTheEngine(error.sentence)
        case .pulling, .starting:
            status = .startingUp
        case .running(let endpoint):
            guard let engineFactory else { return }
            engine = engineFactory(endpoint)
            engineBaseURL = endpoint.baseURL
            pinnedEngineImage = await runtime?.currentImageReference.full
            engineHealth = await runtime?.checkHealth()
            if providers.requiresModelForComposer() {
                composerBlock = .noModelConnected
            } else {
                /*
                 * The engine is up and may not be able to hold a conversation.
                 *
                 * Without a CopilotKit key it boots into local mode, where the history client
                 * throws past wiring — but it still starts, still answers `/health`, and still
                 * lists agents, so every other signal in the app says everything is fine. Saying so
                 * here is invariant 7: never an empty state that implies all is well.
                 *
                 * Two ways to not have one, and they need opposite sentences: nobody connected a
                 * key, or the Keychain would not hand over the key that is there.
                 */
                composerBlock = switch conversationStore() {
                case .ready: nil
                case .notConnected: .noConversationStore
                case .unreadable: .conversationStoreUnreadable
                }
            }
            pausedWhenIdle = false
            noteEngineActivity()
            // Before the refresh, not after: `run` marks the channel as running, which is what stops
            // a history reload from replacing the bubble that is waiting to be answered.
            dispatchMessageThatWokeTheEngine()
            startIdleWatch()
            await refreshFromEngine()
            await checkForEngineUpdateIfDue()
            appUpdates.scheduleAutomaticCheckIfDue()
        case .degraded(let reason):
            // The conversation stays readable and usable — docs/09-ui-spec.md is explicit that a
            // health blip must not yank away what is already loaded. Only the pill changes, and it
            // says which kind of unwell rather than one word for all three.
            status = .degraded(reason)
        }
    }

    /// Bring the engine up. A no-op without a runtime to ask — `AppState(engine:)` has none, and
    /// its composer is never in the `.engineNotRunning` state that would call this anyway.
    /// Handoff from onboarding: reload the engine and select the first agent if one was created.
    public func completeOnboarding(_ handoff: OnboardingHandoff) async {
        if handoff.modelSkipped {
            providers.markSkipped()
        }
        await load()
        if let id = handoff.firstAgentID {
            selectedAgentID = id
            seedWelcomeMessage(for: id)
            await loadPanel()
        }
    }

    /// Tokens each agent has used since the app started, keyed by agent.
    ///
    /// In memory, not persisted. The engine's audit trail is the durable record; this is the
    /// "what has this agent cost me today" number, and inventing a lifetime total the app cannot
    /// reconcile with the vendor's bill would be worse than showing a session.
    public private(set) var usageByAgent: [Agent.ID: AgentUsage] = [:]

    private func recordUsage(inputTokens: Int, outputTokens: Int, for agent: Agent.ID) {
        var usage = usageByAgent[agent] ?? AgentUsage()
        usage.add(inputTokens: inputTokens, outputTokens: outputTokens)
        usageByAgent[agent] = usage
    }

    /// A page of the audit trail, straight from the engine.
    public func auditEvents(_ query: AuditQuery) async throws -> AuditPage {
        try await engine.auditEvents(query)
    }

    public func routines() async throws -> [Routine] {
        try await engine.routines()
    }

    public func setRoutineEnabled(_ id: String, enabled: Bool) async throws {
        try await engine.setRoutineEnabled(id, enabled: enabled)
    }

    public func deleteRoutine(_ id: String) async throws {
        try await engine.deleteRoutine(id)
    }

    public func dismissModelBanner() {
        modelBannerDismissed = true
    }

    private func seedWelcomeMessage(for agentID: Agent.ID) {
        let intro = String(
            localized:
                "Hi. I'm your first agent.\n\nI have a browser and files of my own, and I'll ask before doing anything that matters.\n\nTry me with something like:\n• \"Find three well-reviewed ramen places near me\"\n• \"Open my calendar and summarise this week\""
        )
        messagesByChannel[selectedChannelID ?? ""] = [
            Message(
                id: "onboarding-welcome",
                author: .agent(agentID),
                text: intro,
                state: .complete
            ),
        ]
    }

    // MARK: - Idle

    /// When somebody last did something that needed the engine. See `EngineIdlePolicy`.
    private var lastEngineActivity = Date()
    /// Set when the app, not the person, stopped the engine — the stopped state reads differently.
    private(set) var pausedWhenIdle = false
    /// The message a paused engine was woken to answer.
    private var messageThatWokeTheEngine: (message: Message, channel: Channel.ID)?
    private var idleWatch: Task<Void, Never>?
    /// Settable so a test is not waiting thirty minutes.
    var idleTimeout: TimeInterval = EngineIdlePolicy.defaultTimeout
    var idleCheckInterval: Duration = .seconds(60)

    private func noteEngineActivity() {
        lastEngineActivity = Date()
    }

    private func startIdleWatch() {
        // Only an engine this app manages. `AppState(engine:)` has none to stop.
        guard runtime != nil else { return }
        idleWatch?.cancel()
        idleWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.idleCheckInterval ?? .seconds(60))
                guard !Task.isCancelled, let self else { return }
                await self.stopIfIdle(now: Date())
            }
        }
    }

    /**
     Stop the engine if nothing needs it.

     Routines are only asked about once everything else already says stop, so a quiet engine is not
     polled every minute for them. A read that fails keeps it running — see `EngineIdlePolicy`.
     */
    func stopIfIdle(now: Date) async {
        guard let runtime, case .running = runtimeState else { return }
        let cheap = EngineIdlePolicy.verdict(
            lastActivity: lastEngineActivity, now: now, timeout: idleTimeout,
            turnRunning: isTurnRunning, humanHoldsControl: control == .human,
            enabledRoutines: 0
        )
        guard cheap == .stop else { return }

        let enabled = (try? await engine.routines())?.filter(\.enabled).count
        // Asked again: a turn or a takeover may have started during that request.
        let verdict = EngineIdlePolicy.verdict(
            lastActivity: lastEngineActivity, now: now, timeout: idleTimeout,
            turnRunning: isTurnRunning, humanHoldsControl: control == .human,
            enabledRoutines: enabled
        )
        guard verdict == .stop else { return }
        pausedWhenIdle = true
        await runtime.stop()
    }

    private func dispatchMessageThatWokeTheEngine() {
        guard let (message, channel) = messageThatWokeTheEngine else { return }
        messageThatWokeTheEngine = nil
        guard composerBlock == nil else {
            // It woke into something that needs the person — no model, no CopilotKit key. The
            // message is kept and made retryable, carrying the same sentence the composer shows.
            let reason = composerBlock?.sentence ?? String(localized: "Couldn't send that message.")
            mark(message.id, as: .failed(reason: reason), in: channel)
            retryPrompts[message.id] = (channel, message.id)
            return
        }
        run(message, in: channel)
    }

    /// A paused engine that failed to come back leaves its waiting message retryable, never lost.
    private func failMessageThatWokeTheEngine(_ reason: String) {
        guard let (message, channel) = messageThatWokeTheEngine else { return }
        messageThatWokeTheEngine = nil
        mark(message.id, as: .failed(reason: reason), in: channel)
        retryPrompts[message.id] = (channel, message.id)
    }

    public func startEngine() {
        guard let runtime, let environmentFactory else { return }
        Task { await runtime.start(environment: environmentFactory) }
    }

    /// Stop the engine, leaving its data where it is.
    ///
    /// Not destructive and so not confirmed: everything the person has is in the volumes, which
    /// this does not touch. Starting again picks up the same conversations.
    public func stopEngine() {
        guard let runtime else { return }
        Task { await runtime.stop() }
    }

    public func restartEngine() {
        guard let runtime, let environmentFactory else { return }
        Task { await runtime.restart(environment: environmentFactory) }
    }

    /// The engine's own account of itself, or nil when nothing is answering.
    public private(set) var engineHealth: EngineHealth?

    /// Whether an engine command is in flight, so the buttons can say so rather than look dead.
    public private(set) var isEngineBusy = false

    /// A redacted report on the clipboard: versions, state history, the last log lines.
    ///
    /// It exists so somebody can send it to us, not so they can read it — docs/06-onboarding.md.
    /// The redaction is `Diagnostics`' own, and it is tested: no keys, no tokens, no conversation.
    public func copyDiagnostics() async {
        guard let runtime else { return }
        DiagnosticsClipboard.copy(await runtime.diagnostics(appVersion: Self.appVersion))
    }

    /// User-initiated Sparkle check from Settings → Updates.
    public func checkForAppUpdate() {
        appUpdates.checkForUpdates(userInitiated: true)
    }

    public func fetchActionPolicy() async throws -> ActionPolicy {
        try await engine.actionPolicy()
    }

    public func saveActionPolicy(_ policy: ActionPolicy) async throws -> ActionPolicy {
        try await engine.saveActionPolicy(policy)
    }

    /// Fetch the published engine manifest and compare it to what is running.
    public func checkForEngineUpdate() async {
        guard runtime != nil else { return }
        isCheckingEngineUpdate = true
        defer { isCheckingEngineUpdate = false }
        let current = await runtime?.currentImageReference.full
        pinnedEngineImage = current
        let resolver = EngineImageResolver()
        engineUpdateStatus = await resolver.checkUpdate(
            currentImage: current,
            appVersion: Self.appVersion
        )
        EngineUpdateCheckStore.markChecked()
    }

    /// Daily, and when the engine reaches running — docs/11-packaging-and-updates.md.
    private func checkForEngineUpdateIfDue() async {
        guard hasManagedRuntime, EngineUpdateCheckStore.shouldCheck() else { return }
        await checkForEngineUpdate()
    }

    /// Pull a published engine update and restart against the same volumes.
    ///
    /// Blocked while a turn is streaming — docs/11: never interrupt mid-conversation.
    public func installEngineUpdate() async {
        guard !isTurnRunning,
              let newImage = engineUpdateStatus?.installableImage,
              let runtime,
              let environmentFactory
        else { return }

        isInstallingEngineUpdate = true
        status = .updating
        composerBlock = .engineNotRunning
        defer {
            isInstallingEngineUpdate = false
            if case .updating = status { status = nil }
        }

        let previousImage = await runtime.currentImageReference
        let outcome = await runtime.upgrade(
            to: newImage,
            rollingBackTo: previousImage,
            environment: environmentFactory
        )
        lastEngineUpgradeOutcome = outcome
        pinnedEngineImage = await runtime.currentImageReference.full
        await checkForEngineUpdate()
        await refreshFromEngine()
    }

    /// Remove everything xBot put on this Mac, in the order that cannot strand anything.
    ///
    /// Containers and volumes first, then the Keychain, then the preferences. The order matters:
    /// the preferences are what tell the app which volumes and containers are its own, so clearing
    /// them first would leave the rest with nothing naming it.
    ///
    /// The container runtime is deliberately left alone — the person may have installed Docker or
    /// Colima for something else, and taking an unrelated tool with us is worse than leaving it.
    ///
    /// Returns when the data is gone. Moving the app itself to the Trash is the person's to do,
    /// and the screen says so.
    public func uninstall() async {
        isEngineBusy = true
        defer { isEngineBusy = false }

        await runtime?.uninstall()

        // Every key this app has ever written. Listed rather than enumerated, because a wildcard
        // sweep of the login keychain is not something this app should ever perform.
        for providerID in ModelProviderCatalog.all.map(\.id) {
            try? ProviderKeyStore.remove(providerID: providerID)
        }
        for provider in CustomProviderStore.shared.all {
            try? ProviderKeyStore.remove(providerID: provider.id)
        }
        try? EngineTokenStore.remove()
        try? KeyEncryptionKeyStore.remove()

        EngineUpdateCheckStore.reset()
        AppUpdateCheckStore.reset()
        AgentDefaultsStore.reset()
        providers.reset()
        RuntimeChoiceStore.reset()
        OnboardingVersion.reset()
        for provider in CustomProviderStore.shared.all {
            CustomProviderStore.shared.remove(id: provider.id)
        }

        agents = []
        channels = []
        messagesByChannel = [:]
        unreadAgents = []
        questionsForYou = [:]
        engineHealth = nil
        engineBaseURL = nil
    }

    public static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// What the composer's inline action button does, keyed by the same reason that put it there.
    public func handleComposerBlockAction() {
        switch composerBlock {
        case .engineNotRunning, .engineFailed, .enginePausedWhenIdle:
            startEngine()
        case .humanHoldsControl:
            setControl(.agent)
        case .noModelConnected, .noConversationStore:
            // Both are fixed in the same place, and settings are in this window now.
            isShowingSettings = true
        case .conversationStoreUnreadable:
            // Nothing to open — the key is already there. Ask the Keychain again, which is what a
            // locked one or a dismissed prompt needs, and let the engine come back up with it.
            startEngine()
        case .runtimeUnavailable, nil:
            // Runtime install is M6.
            break
        }
    }

    /// Create an agent and open it. Optimistic on the rail: the row exists before the channel
    /// round-trip finishes, so the fill never waits on a second request.
    public func createAgent(named name: String) {
        guard !isCreatingAgent else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = AgentDraft(
            name: trimmed.isEmpty ? String(localized: "New agent") : trimmed,
            roleDescription: AgentDefaultsStore.roleDescription(),
            model: AgentDefaultsStore.defaultModel() ?? models.first
        )
        pendingAgentDraft = draft
        createAgent(draft)
    }

    public func retryAgentCreation() {
        guard let draft = pendingAgentDraft, !isCreatingAgent else { return }
        createAgent(draft)
    }

    private func createAgent(_ draft: AgentDraft) {
        isCreatingAgent = true
        creationProblem = nil
        Task { [engine] in
            defer { isCreatingAgent = false }
            do {
                let agent = try await engine.createAgent(draft)
                agents.append(agent)
                pendingAgentDraft = nil
                select(agent.id)
                await createSelectedConversation()
            } catch {
                creationProblem = String(localized: "Couldn't create your agent. Try again when the engine is available.")
            }
        }
    }

    /// Also repairs agents left without a channel by an interrupted first-run setup.
    public func createSelectedConversation() async {
        guard let id = selectedAgentID, needsConversation, !isCreatingConversation else { return }
        isCreatingConversation = true
        conversationCreationProblem = nil
        defer { isCreatingConversation = false }
        do {
            let channel = try await engine.createChannel(agentIds: [id])
            channels.append(channel)
            if selectedAgentID == id { await loadMessages() }
        } catch {
            if selectedAgentID == id {
                conversationCreationProblem = String(localized: "Your agent is saved, but its conversation couldn't be opened. Try again.")
            }
        }
    }

    public func select(_ id: Agent.ID) {
        guard id != selectedAgentID else { return }
        selectedAgentID = id
        agentUpdateProblem = nil
        conversationCreationProblem = nil
        unreadAgents.remove(id)
        /*
         * The turn is deliberately left running.
         *
         * It used to be cancelled here, so glancing at another agent threw away the reply the first
         * one was part-way through writing — silently, with the half-finished bubble going with it.
         * Messages are keyed by channel, so it keeps writing where it started and the rail shows a
         * dot when it lands.
         */
        // The selection does not wait for the conversation. It is applied now; messages catch up.
        activity = []
        grantedPlugins = nil
        pluginsPage = nil
        handoffGrants = nil
        screenFrame = nil
        Task {
            await loadMessages()
            await loadPanel()
        }
    }

    /// Which agent a channel belongs to. One agent per channel in v1; the first is the answer.
    private func agentID(forChannel channel: Channel.ID) -> Agent.ID? {
        channels.first { $0.id == channel }?.agentIds.first
    }

    private func loadPanel() async {
        guard let agent = selectedAgentID else { return }
        activity = (try? await engine.activity(for: agent)) ?? []
        await refreshAgentSettingsData()
        retuneScreen()
    }

    /// Reload the plugin catalogue and this agent's grants together.
    public func refreshPluginsData() async {
        guard let agent = selectedAgentID else {
            grantedPlugins = nil
            pluginsPage = nil
            return
        }
        grantedPluginsLoading = true
        pluginsPageLoading = true
        defer {
            grantedPluginsLoading = false
            pluginsPageLoading = false
        }
        async let page = engine.pluginsPage()
        async let granted = engine.grantedPlugins(for: agent)
        pluginsPage = try? await page
        grantedPlugins = try? await granted
    }

    /// Reload handoff grants for the selected agent.
    public func refreshHandoffGrants() async {
        guard let agent = selectedAgentID else {
            handoffGrants = nil
            return
        }
        handoffGrantsLoading = true
        defer { handoffGrantsLoading = false }
        handoffGrants = try? await engine.handoffGrants(for: agent)
    }

    /// Reload plugin and handoff state shown in agent settings.
    public func refreshAgentSettingsData() async {
        async let plugins: Void = refreshPluginsData()
        async let handoff: Void = refreshHandoffGrants()
        _ = await (plugins, handoff)
    }

    /// Grant or revoke a tool or skill for the selected agent. Refreshes plugin state on completion.
    public func setPluginGrant(kind: PluginGrantKind, ref: String, enabled: Bool) async {
        guard let agent = selectedAgentID else { return }
        if enabled {
            try? await engine.grantPlugin(kind: kind, ref: ref, to: agent)
        } else {
            try? await engine.revokePlugin(kind: kind, ref: ref, from: agent)
        }
        await refreshPluginsData()
    }

    /// Whether this agent may hand work to another. Directional: selected agent asks `target`.
    public func setHandoffGrant(to target: Agent.ID, enabled: Bool) async {
        guard let agent = selectedAgentID, agent != target else { return }
        if enabled {
            try? await engine.grantPlugin(kind: .bot, ref: target, to: agent)
        } else {
            try? await engine.revokePlugin(kind: .bot, ref: target, from: agent)
        }
        await refreshHandoffGrants()
    }

    /// Add an agent to the open conversation by opening a multi-agent channel.
    public func addAgentToCurrentChannel(_ agentID: Agent.ID) {
        guard let selectedAgentID,
              let channel = channels.first(where: { $0.agentIds.contains(selectedAgentID) }),
              !channel.agentIds.contains(agentID)
        else { return }

        Task { [engine] in
            let agentIds = channel.agentIds + [agentID]
            guard let newChannel = try? await engine.createChannel(agentIds: agentIds) else { return }
            channels.removeAll { $0.id == channel.id }
            channels.append(newChannel)
            await loadMessages()
        }
    }

    /// Open the plugins admin webview at a path under the engine origin.
    public func preparePluginsAdmin(path: String = "admin/plugins") {
        pluginsAdminDeepLink = path
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
        noteEngineActivity()
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

    /**
     A change to the selected agent that failed, so the pane can stop showing it as though it took.

     The model picker reads its label straight from the stored agent, so a failed change there simply
     does not appear. The name and label fields do not: they are local editing state, committed on
     blur, and a commit that failed used to leave the typed text sitting in the field while the rail
     two inches away went on showing the old name. Nothing said which one was true, and the edit
     vanished on the next agent switch.
     */
    public private(set) var agentUpdateProblem: String?

    public func updateSelectedAgent(_ patch: AgentPatch) {
        guard let id = selectedAgentID else { return }
        agentUpdateProblem = nil
        Task { [engine] in
            do {
                let updated = try await engine.updateAgent(id, patch)
                if let index = agents.firstIndex(where: { $0.id == id }) {
                    agents[index] = updated
                }
                if selectedAgentID == id { agentUpdateProblem = nil }
            } catch {
                guard selectedAgentID == id else { return }
                agentUpdateProblem = String(
                    localized: "That change couldn't be saved. Is the engine running?"
                )
            }
        }
    }

    /// Called by the pane once it has put the fields back to what is actually stored.
    public func clearAgentUpdateProblem() {
        agentUpdateProblem = nil
    }

    public func retryHistory() async { await loadMessages() }

    private func loadMessages() async {
        // Never over a conversation that is still being written to. A background turn's own
        // messages are newer than anything a reload would fetch.
        guard let channel = selectedChannelID, runningChannel != channel else { return }
        let requestID = UUID()
        historyRequests[channel] = requestID
        do {
            let loaded = try await engine.messages(in: channel)
            guard historyRequests[channel] == requestID, runningChannel != channel else { return }
            // Failed prompts may not exist on the server. Keep the local transcript until recovery.
            if !retryPrompts.values.contains(where: { $0.channel == channel }) {
                messagesByChannel[channel] = loaded
            }
            historyProblems[channel] = nil
        } catch {
            guard historyRequests[channel] == requestID else { return }
            historyProblems[channel] = String(localized: "Couldn't load conversation history. Your loaded messages are still here.")
        }
    }

    /// Send, optimistically.
    ///
    /// The bubble exists before the request does. A send that fails becomes a retryable bubble
    /// holding the same text — the one thing that must never happen is losing what somebody typed.
    public func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if composerBlock == .enginePausedWhenIdle, !trimmed.isEmpty, !isTurnInFlight,
           messageThatWokeTheEngine == nil, let channel = selectedChannelID {
            // docs/07: "starts on demand when the user sends a message". The bubble goes up now,
            // exactly as any optimistic send does, and is answered once the engine is back.
            let sent = Message(id: "local-\(UUID().uuidString)", author: .user, text: trimmed, state: .sending)
            messagesByChannel[channel, default: []].append(sent)
            messageThatWokeTheEngine = (sent, channel)
            startEngine()
            return
        }
        guard !trimmed.isEmpty, canSend, let channel = selectedChannelID else { return }
        let sent = Message(id: "local-\(UUID().uuidString)", author: .user, text: trimmed, state: .sending)
        messagesByChannel[channel, default: []].append(sent)
        run(sent, in: channel)
    }

    public func canRetry(_ message: Message) -> Bool {
        canSend && retryPrompts[message.id]?.channel == selectedChannelID
    }

    public func retry(_ messageID: Message.ID) {
        guard canSend, let failed = retryPrompts[messageID], failed.channel == selectedChannelID,
              let prompt = messagesByChannel[failed.channel]?.first(where: { $0.id == failed.prompt })
        else { return }
        // Reuse the prompt bubble; replace only this failed response, not subsequent messages.
        if messageID != prompt.id {
            messagesByChannel[failed.channel]?.removeAll { $0.id == messageID }
        }
        retryPrompts[messageID] = nil
        mark(prompt.id, as: .sending, in: failed.channel)
        run(prompt, in: failed.channel)
    }

    private func run(_ sent: Message, in channel: Channel.ID) {
        let agentID = selectedAgentID ?? ""
        noteEngineActivity()
        // Answering is what clears the question. The agent asked and you replied; nothing is
        // waiting on you in this conversation any more.
        questionsForYou[agentID] = nil
        historyRequests[channel] = nil // A load started before this send must not overwrite it.
        runningChannel = channel
        runningAgent = agentID
        retuneScreen()
        turn = Task { [engine] in
            defer {
                runningChannel = nil
                runningAgent = nil
                // A long turn ends the quiet period rather than counting towards it.
                noteEngineActivity()
                /*
                 * An answer that finished where nobody was looking.
                 *
                 * The turn no longer dies when the selection moves, so it can land on a channel
                 * that is not on screen. Without the dot that reply is simply invisible until
                 * somebody happens to click back, which is the failure docs/09 calls out: an agent
                 * waiting on a person that nobody notices makes the whole product feel unreliable.
                 */
                if selectedChannelID != channel { unreadAgents.insert(agentID) }
                retuneScreen()
            }
            var replyID: Message.ID?
            var replyIDs: [Message.ID] = []
            @MainActor func fail(_ reason: String) {
                let id = replyID ?? sent.id
                mark(id, as: .failed(reason: reason), in: channel)
                retryPrompts[id] = (channel, sent.id)
            }
            @MainActor func ensureReply(_ id: String) {
                guard !id.isEmpty else { return }
                if !replyIDs.contains(id) {
                    replyIDs.append(id)
                    messagesByChannel[channel, default: []].append(
                        Message(id: id, author: .agent(agentID), text: "", state: .streaming)
                    )
                }
                replyID = id
                mark(sent.id, as: .complete, in: channel)
            }
            do {
                for try await event in engine.send(sent.text, to: channel) {
                    switch event {
                    case .started(let id):
                        ensureReply(id)
                    case .textDelta(let id, let text):
                        ensureReply(id)
                        append(text, to: id, in: channel)
                    case .toolCall(let id, let callId, let name, let target):
                        let targetID = id.isEmpty ? (replyID ?? "tool-\(callId)") : id
                        ensureReply(targetID)
                        recordTool(callId: callId, name: name, target: target, on: targetID, in: channel)
                    case .toolArguments(let callId, let json):
                        applyToolArguments(callId: callId, json: json)
                    case .finished(let id):
                        mark(id, as: .complete, in: channel)
                    case .runFinished:
                        mark(sent.id, as: .complete, in: channel)
                        for id in replyIDs { mark(id, as: .complete, in: channel) }
                        return
                    case .failed(_, let reason):
                        fail(reason)
                        return
                    case .usage(let input, let output):
                        recordUsage(inputTokens: input, outputTokens: output, for: agentID)
                    }
                }
                fail(String(localized: "The reply was interrupted. Try again; any completed actions may run again."))
            } catch {
                fail(String(localized: "Couldn't finish the reply. Check the connection and try again; any completed actions may run again."))
            }
        }
    }

    private func append(_ text: String, to id: Message.ID, in channel: Channel.ID) {
        guard let index = messagesByChannel[channel]?.firstIndex(where: { $0.id == id }) else { return }
        messagesByChannel[channel]?[index].text += text
    }

    /// Where a tool call landed, so its arguments can find it when they arrive separately.
    private var toolCallSites: [String: (message: Message.ID, name: String, channel: Channel.ID)] = [:]

    private func recordTool(
        callId: String,
        name: String,
        target: String,
        on id: Message.ID,
        in channel: Channel.ID
    ) {
        guard let index = messagesByChannel[channel]?.firstIndex(where: { $0.id == id }) else { return }
        let callIndex = messagesByChannel[channel]?[index].toolCalls.count ?? 0
        messagesByChannel[channel]?[index].toolCalls.append(
            Message.ToolCall(id: callId, name: name, target: target)
        )
        toolCallSites[callId] = (message: id, name: name, channel: channel)

        /*
         * The same call, in the Activity panel.
         *
         * It only ever reached the message bubble, and `HTTPEngineClient.activity(for:)` returns an
         * empty list on purpose — the panel is held for the open conversation rather than fetched.
         * So against a live engine it always read "Nothing yet. Commands, files, and pages will show
         * up here", promising something nothing could deliver. An empty state that cannot stop being
         * empty is the dishonest kind (invariant 7).
         *
         * Newest first, which is the order the panel renders and a person reads.
         */
        activity.insert(
            ActivityEntry(
                id: callId,
                kind: .tool(name: name),
                summary: target.isEmpty ? name : "\(name) \(target)"
            ),
            at: 0
        )
    }

    /// Fill in what the call was actually for, once its arguments arrive.
    ///
    /// AG-UI announces a call and sends its arguments as two events, keyed by tool-call id rather
    /// than by message, so only a reader that saw the start can pair them. Until this ran, an
    /// Activity row could say "computer_navigate" and nothing about where — see `ToolArguments` for
    /// what the arguments are allowed to turn into, and what they are not.
    private func applyToolArguments(callId: String, json: String) {
        guard let site = toolCallSites[callId] else { return }

        let target = ToolArguments.summary(toolName: site.name, argumentsJSON: json)
        if let messageIndex = messagesByChannel[site.channel]?.firstIndex(where: { $0.id == site.message }),
           let callIndex = messagesByChannel[site.channel]?[messageIndex].toolCalls
               .firstIndex(where: { $0.id == callId }),
           messagesByChannel[site.channel]?[messageIndex].toolCalls[callIndex].target.isEmpty == true {
            // Only when the stream did not already name one. A target the engine sent is better
            // than one inferred here.
            messagesByChannel[site.channel]?[messageIndex].toolCalls[callIndex].target =
                target == site.name ? "" : String(target.dropFirst(site.name.count + 1))
        }

        if let question = ToolArguments.questionForPerson(
            toolName: site.name,
            argumentsJSON: json
        ), let agent = agentID(forChannel: site.channel) {
            questionsForYou[agent] = question
        }

        guard let entryIndex = activity.firstIndex(where: { $0.id == callId }) else { return }
        let existing = activity[entryIndex]
        activity[entryIndex] = ActivityEntry(
            id: existing.id,
            kind: ToolArguments.kind(toolName: site.name, argumentsJSON: json),
            summary: target,
            detail: existing.detail,
            at: existing.at
        )
    }

    private func mark(_ id: Message.ID, as state: Message.State, in channel: Channel.ID) {
        guard let index = messagesByChannel[channel]?.firstIndex(where: { $0.id == id }) else { return }
        messagesByChannel[channel]?[index].state = state
    }
}
