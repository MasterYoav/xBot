import Foundation

/// Everything the app asks of the engine.
///
/// A protocol with two implementations from the start, not one extracted later: `StubEngineClient`
/// here, and the real REST/SSE client. docs/05-mac-app.md calls the stub a first-class deliverable
/// and it is — it is how the UI is built while the engine is somewhere else, how snapshot tests stay
/// deterministic, and how someone with no container runtime can still run the app.
public protocol EngineClient: Sendable {
    func agents() async throws -> [Agent]
    func channels() async throws -> [Channel]
    func messages(in channel: Channel.ID) async throws -> [Message]

    /// Make a new agent. The conversation that belongs to it is a separate `createChannel` —
    /// upstream stores them as two rows, and collapsing that here would hide a 201 that then
    /// left the rail pointing at an agent nobody can talk to.
    func createAgent(_ draft: AgentDraft) async throws -> Agent

    /// Open a conversation that includes these agents. v1 always passes one.
    func createChannel(agentIds: [Agent.ID]) async throws -> Channel

    /// Send, and stream the turn back.
    ///
    /// The stream is the heart of the app. It must be incremental, must survive a truncated
    /// response, and must be orderable per turn while several turns run at once — so it is one
    /// stream per send rather than one shared event bus the caller has to filter.
    func send(
        _ text: String,
        to channel: Channel.ID
    ) -> AsyncThrowingStream<TurnEvent, Error>

    /// What the agent did away from the browser, for the open conversation.
    func activity(for agent: Agent.ID) async throws -> [ActivityEntry]

    /// The live screen, polled.
    ///
    /// A stream rather than a `screenshot()` call the view puts on a timer, so the cadence logic —
    /// fast during a turn, slow when idle, off when hidden — lives here once instead of in every
    /// caller that wants a picture.
    func screen(for agent: Agent.ID, cadence: ScreenCadence) -> AsyncStream<ScreenFrame>

    /// Take the browser, or give it back. Audited by the engine as a first-class event.
    func setControl(_ control: ScreenControl, for agent: Agent.ID) async throws

    /// Change one agent. Saved on blur; there is no Save button anywhere in this product.
    func updateAgent(_ id: Agent.ID, _ patch: AgentPatch) async throws -> Agent

    /// The models this deployment can currently reach.
    func availableModels() async throws -> [ModelSelection]

    /// The plugins admin page: catalogue, connected servers, and skills.
    func pluginsPage() async throws -> PluginsPage

    /// What one agent may use — tools and skills the runtime offers it.
    func grantedPlugins(for agent: Agent.ID) async throws -> GrantedPlugins

    /// Grant a tool or skill to an agent.
    func grantPlugin(kind: PluginGrantKind, ref: String, to agent: Agent.ID) async throws

    /// Revoke a tool or skill from an agent.
    func revokePlugin(kind: PluginGrantKind, ref: String, from agent: Agent.ID) async throws

    /// Add a first-party server from the catalogue.
    func addPluginServer(catalogueKey: String) async throws

    /// Which agents this one may ask via handoff.
    func handoffGrants(for agent: Agent.ID) async throws -> HandoffGrants

    /// Deployment-wide browser action policy.
    func actionPolicy() async throws -> ActionPolicy

    /// Replace the whole policy. The engine normalises and echoes what is in force.
    func saveActionPolicy(_ policy: ActionPolicy) async throws -> ActionPolicy
}

/// What creating an agent needs. The rest of the row is generated — avatar seed, id, defaults.
public struct AgentDraft: Sendable, Hashable {
    public var name: String
    public var label: String
    /// Standing instruction for the agent. Defaults to the title when empty.
    public var roleDescription: String
    /// Applied on create when the engine accepts `modelSelection` on POST.
    public var model: ModelSelection?

    public init(
        name: String,
        label: String = "",
        roleDescription: String = "",
        model: ModelSelection? = nil
    ) {
        self.name = name
        self.label = label
        self.roleDescription = roleDescription
        self.model = model
    }
}

/// A partial change to an agent. Only what was edited travels.
public struct AgentPatch: Sendable, Hashable {
    public var name: String?
    public var label: String?
    public var model: ModelSelection?

    public init(name: String? = nil, label: String? = nil, model: ModelSelection? = nil) {
        self.name = name
        self.label = label
        self.model = model
    }
}

public enum EngineError: Error, Sendable, Equatable {
    case notRunning
    case unknownChannel(Channel.ID)
    /// The run endpoint answered, but not with a stream. Carries the status so the message
    /// can say whether this was auth, a bad request, or the engine falling over.
    case streamRejected(status: Int)
}
