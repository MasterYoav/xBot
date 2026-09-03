import Foundation

/// The engine, faked, well enough to build the whole conversation against.
///
/// An actor because it holds mutable conversation state and the UI hits it from several tasks —
/// the same reason the real client is one. Fixtures deliberately include the awkward cases the
/// happy path hides: a long agent name that has to truncate in the rail, a message that streams in
/// pieces rather than arriving whole, and a turn that fails so the retry state is reachable
/// without unplugging anything.
public actor StubEngineClient: EngineClient {
    private var messagesByChannel: [Channel.ID: [Message]]
    private var fixedAgents: [Agent]
    private var fixedChannels: [Channel]
    private var control: ScreenControl = .agent
    private var pluginCatalogue: [CatalogueItem]
    private var pluginServers: [PluginServer]
    private var pluginSkills: [PluginSkill]
    private var handoffReachable: [Agent.ID: Set<Agent.ID>] = [
        "orchestrator": ["inbox"],
    ]

    /// How long a stubbed token takes to arrive.
    ///
    /// Not zero. A stub that answers instantly hides every scroll-pinning and streaming-layout bug
    /// the real stream will find, which defeats the point of building against it.
    private let tokenDelay: Duration

    public init(tokenDelay: Duration = .milliseconds(28)) {
        self.tokenDelay = tokenDelay

        let agents = [
            Agent(
                id: "orchestrator",
                name: "Orchestrator",
                label: "Orchestrate and use the other agents",
                avatarSeed: "orchestrator",
                model: ModelSelection(
                    provider: "Anthropic",
                    model: "Claude Sonnet 4.5",
                    capabilities: ["vision", "tools"]
                )
            ),
            Agent(
                id: "inbox",
                name: "Inbox",
                label: "Reads and drafts your mail",
                avatarSeed: "inbox",
                model: ModelSelection(
                    provider: "OpenAI",
                    model: "gpt-4.1",
                    capabilities: ["vision", "tools"]
                )
            ),
            Agent(
                id: "researcher",
                name: "Researcher with a long name",
                label: "Reads the web and writes it up",
                avatarSeed: "researcher",
                model: ModelSelection(provider: "Ollama", model: "llama3.1", capabilities: ["tools"])
            ),
        ]
        fixedAgents = agents
        fixedChannels = agents.map { Channel(id: "channel-\($0.id)", agentIds: [$0.id]) }

        pluginCatalogue = [
            CatalogueItem(
                key: "google-drive",
                title: "Google Drive",
                vendor: "Google",
                summary: "Search, read and write files in Drive.",
                docsURL: "https://developers.google.com/drive",
                auth: .userOAuth,
                perInstance: false
            ),
            CatalogueItem(
                key: "notion",
                title: "Notion",
                vendor: "Notion",
                summary: "Search and update pages in Notion.",
                docsURL: "https://developers.notion.com",
                auth: .userOAuth,
                perInstance: false
            ),
        ]
        pluginServers = [
            PluginServer(
                id: "google-drive",
                title: "Google Drive",
                vendor: "Google",
                url: "https://www.googleapis.com/mcp",
                summary: "Search, read and write files in Drive.",
                docsURL: "https://developers.google.com/drive",
                hasCredential: true,
                toolsRefreshedAt: nil,
                lastError: nil,
                dynamicClient: true,
                tools: [
                    PluginTool(
                        serverID: "google-drive",
                        name: "search_files",
                        summary: "Search for files in Drive.",
                        ref: "google-drive/search_files",
                        effect: .read,
                        grantedTo: ["orchestrator"]
                    ),
                    PluginTool(
                        serverID: "google-drive",
                        name: "read_file",
                        summary: "Read a file from Drive.",
                        ref: "google-drive/read_file",
                        effect: .read,
                        grantedTo: []
                    ),
                ]
            ),
        ]
        pluginSkills = []

        messagesByChannel = [
            "channel-orchestrator": [
                Message(
                    id: "m1",
                    author: .user,
                    text: "Check whether the Lisbon flight is still refundable.",
                    sentAt: Date(timeIntervalSinceNow: -420)
                ),
                Message(
                    id: "m2",
                    author: .agent("orchestrator"),
                    text: """
                        It is, until Thursday. After that the fare drops to a 40% refund. \
                        I've left the booking open in the browser if you want to look.
                        """,
                    sentAt: Date(timeIntervalSinceNow: -400)
                ),
                Message(
                    id: "m3",
                    author: .user,
                    text: "Leave it for now, thanks.",
                    sentAt: Date(timeIntervalSinceNow: -380)
                ),
            ],
            "channel-inbox": [],
            "channel-researcher": [],
        ]
    }

    public func agents() async throws -> [Agent] { fixedAgents }

    public func createAgent(_ draft: AgentDraft) async throws -> Agent {
        let id = "agent-\(UUID().uuidString)"
        let agent = Agent(
            id: id,
            name: draft.name,
            label: draft.label,
            avatarSeed: id
        )
        fixedAgents.append(agent)
        return agent
    }

    public func createChannel(agentIds: [Agent.ID]) async throws -> Channel {
        let channel = Channel(id: "channel-\(UUID().uuidString)", agentIds: agentIds)
        fixedChannels.append(channel)
        messagesByChannel[channel.id] = []
        return channel
    }

    public func activity(for agent: Agent.ID) async throws -> [ActivityEntry] {
        guard agent == "orchestrator" else { return [] }
        // Newest first, as the panel renders it.
        return [
            ActivityEntry(
                id: "a3",
                kind: .fileWrite(path: "/workspace/notes/lisbon.md", bytes: 1_284),
                summary: "Wrote lisbon.md",
                at: Date(timeIntervalSinceNow: -395)
            ),
            ActivityEntry(
                id: "a2",
                kind: .command(exitCode: 0),
                summary: "curl -s api.airline.example/booking/8812",
                detail: "{\"refundable\":true,\"until\":\"2026-09-04\"}",
                at: Date(timeIntervalSinceNow: -405)
            ),
            ActivityEntry(
                id: "a1",
                kind: .navigate(url: "https://airline.example/bookings"),
                summary: "Opened airline.example/bookings",
                at: Date(timeIntervalSinceNow: -410)
            ),
        ]
    }

    public nonisolated func screen(
        for agent: Agent.ID,
        cadence: ScreenCadence
    ) -> AsyncStream<ScreenFrame> {
        AsyncStream { continuation in
            guard let interval = cadence.interval else {
                // Stopped is not an empty stream that hangs; it is a stream that ends. A view
                // awaiting frames from a hidden panel must not be left suspended forever.
                continuation.finish()
                return
            }
            let task = Task {
                while !Task.isCancelled {
                    // No pixels from a stub. The panel renders its empty state, which is the
                    // state that actually needs designing.
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func setControl(_ control: ScreenControl, for agent: Agent.ID) async throws {
        self.control = control
    }

    public func updateAgent(_ id: Agent.ID, _ patch: AgentPatch) async throws -> Agent {
        guard let index = fixedAgents.firstIndex(where: { $0.id == id }) else {
            throw EngineError.unknownChannel(id)
        }
        var agent = fixedAgents[index]
        if let name = patch.name { agent.name = name }
        if let label = patch.label { agent.label = label }
        if let model = patch.model { agent.model = model }
        fixedAgents[index] = agent
        return agent
    }

    public func availableModels() async throws -> [ModelSelection] {
        [
            ModelSelection(provider: "Anthropic", model: "Claude Sonnet 4.5", capabilities: ["vision", "tools"]),
            ModelSelection(provider: "Anthropic", model: "Claude Opus 4.1", capabilities: ["vision", "tools"]),
            ModelSelection(provider: "OpenAI", model: "gpt-4.1", capabilities: ["vision", "tools"]),
            ModelSelection(provider: "xAI", model: "grok-4", capabilities: ["tools"]),
            ModelSelection(provider: "Ollama", model: "llama3.1", capabilities: ["tools"]),
        ]
    }

    public func pluginsPage() async throws -> PluginsPage {
        PluginsPage(
            catalogue: pluginCatalogue,
            servers: pluginServers,
            skills: pluginSkills,
            botsMayCallBack: true,
            redirectURI: "http://127.0.0.1:3001/api/plugins/oauth/callback"
        )
    }

    public func grantedPlugins(for agent: Agent.ID) async throws -> GrantedPlugins {
        var tools: [GrantedPlugins.GrantedTool] = []
        var skills: [GrantedPlugins.GrantedSkill] = []
        for server in pluginServers {
            for tool in server.tools where tool.grantedTo.contains(agent) {
                tools.append(
                    GrantedPlugins.GrantedTool(
                        ref: tool.ref,
                        toolName: tool.name,
                        summary: tool.summary
                    )
                )
            }
        }
        for skill in pluginSkills where skill.grantedTo.contains(agent) {
            skills.append(
                GrantedPlugins.GrantedSkill(
                    slug: skill.slug,
                    title: skill.title,
                    summary: skill.summary,
                    instructions: skill.instructions
                )
            )
        }
        return GrantedPlugins(tools: tools, skills: skills)
    }

    public func grantPlugin(kind: PluginGrantKind, ref: String, to agent: Agent.ID) async throws {
        switch kind {
        case .mcp:
            guard let serverIndex = pluginServers.firstIndex(where: { server in
                server.tools.contains { $0.ref == ref }
            }) else { return }
            guard let toolIndex = pluginServers[serverIndex].tools.firstIndex(where: { $0.ref == ref }) else {
                return
            }
            var tool = pluginServers[serverIndex].tools[toolIndex]
            if !tool.grantedTo.contains(agent) {
                tool.grantedTo.append(agent)
                pluginServers[serverIndex].tools[toolIndex] = tool
            }
        case .skill:
            guard let index = pluginSkills.firstIndex(where: { $0.slug == ref }) else { return }
            var skill = pluginSkills[index]
            if !skill.grantedTo.contains(agent) {
                skill.grantedTo.append(agent)
                pluginSkills[index] = skill
            }
        case .bot:
            guard agent != ref else { return }
            var reachable = handoffReachable[agent, default: []]
            reachable.insert(ref)
            handoffReachable[agent] = reachable
        }
    }

    public func revokePlugin(kind: PluginGrantKind, ref: String, from agent: Agent.ID) async throws {
        switch kind {
        case .mcp:
            guard let serverIndex = pluginServers.firstIndex(where: { server in
                server.tools.contains { $0.ref == ref }
            }) else { return }
            guard let toolIndex = pluginServers[serverIndex].tools.firstIndex(where: { $0.ref == ref }) else {
                return
            }
            var tool = pluginServers[serverIndex].tools[toolIndex]
            tool.grantedTo.removeAll { $0 == agent }
            pluginServers[serverIndex].tools[toolIndex] = tool
        case .skill:
            guard let index = pluginSkills.firstIndex(where: { $0.slug == ref }) else { return }
            var skill = pluginSkills[index]
            skill.grantedTo.removeAll { $0 == agent }
            pluginSkills[index] = skill
        case .bot:
            handoffReachable[agent]?.remove(ref)
        }
    }

    public func addPluginServer(catalogueKey: String) async throws {
        guard !pluginServers.contains(where: { $0.id == catalogueKey }) else { return }
        guard let item = pluginCatalogue.first(where: { $0.key == catalogueKey }) else { return }
        pluginServers.append(
            PluginServer(
                id: item.key,
                title: item.title,
                vendor: item.vendor,
                url: "",
                summary: item.summary,
                docsURL: item.docsURL,
                hasCredential: false,
                toolsRefreshedAt: nil,
                lastError: nil,
                dynamicClient: item.auth == .userOAuth,
                tools: []
            )
        )
    }

    public func handoffGrants(for agent: Agent.ID) async throws -> HandoffGrants {
        HandoffGrants(
            enabled: true,
            canGrant: true,
            reachable: Array(handoffReachable[agent] ?? []),
            grantable: true
        )
    }
    public func channels() async throws -> [Channel] { fixedChannels }

    public func messages(in channel: Channel.ID) async throws -> [Message] {
        guard let found = messagesByChannel[channel] else {
            throw EngineError.unknownChannel(channel)
        }
        return found
    }

    public nonisolated func send(
        _ text: String,
        to channel: Channel.ID
    ) -> AsyncThrowingStream<TurnEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else { return }
                await self.stream(text, to: channel, into: continuation)
            }
            // Cancelling the stream must stop the work behind it. Without this a user who switches
            // agents mid-turn leaves a task appending to a conversation nobody is looking at.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func stream(
        _ text: String,
        to channel: Channel.ID,
        into continuation: AsyncThrowingStream<TurnEvent, Error>.Continuation
    ) async {
        let id = "reply-\(UUID().uuidString)"
        messagesByChannel[channel, default: []].append(
            Message(id: "sent-\(UUID().uuidString)", author: .user, text: text, state: .complete)
        )
        continuation.yield(.started(messageId: id))

        // One fixture that fails, reachable on demand rather than by luck: the retry state needs to
        // be buildable without waiting for a real network to misbehave.
        if text.lowercased().hasPrefix("fail") {
            continuation.yield(.failed(messageId: id, reason: "The model didn't respond"))
            continuation.finish()
            return
        }

        if text.lowercased().contains("browse") || text.lowercased().contains("check") {
            continuation.yield(.toolCall(messageId: id, name: "browser.navigate", target: "flights"))
        }

        let reply = Self.reply(to: text)
        var pending = ""
        for word in reply.split(separator: " ", omittingEmptySubsequences: false) {
            if Task.isCancelled {
                continuation.finish()
                return
            }
            pending += (pending.isEmpty ? "" : " ") + word
            continuation.yield(.textDelta(messageId: id, text: pending.isEmpty ? "" : " " + word))
            try? await Task.sleep(for: tokenDelay)
        }

        messagesByChannel[channel, default: []].append(
            Message(id: id, author: .agent("orchestrator"), text: reply, state: .complete)
        )
        continuation.yield(.finished(messageId: id))
        continuation.finish()
    }

    private static func reply(to text: String) -> String {
        """
        I had a look. Nothing here is real yet — this is the stub engine, which exists so the \
        conversation can be built and tested before it is connected to anything. You typed \
        "\(text.prefix(60))".
        """
    }
}
