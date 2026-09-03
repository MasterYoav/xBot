import Foundation

/// The real engine, over loopback.
///
/// Routes were read off a running engine rather than guessed — `agent/:agentId/run` in particular
/// is not documented anywhere and is three levels into a vendor bundle. If one 404s after an
/// upstream merge, probe rather than assume; `/api/copilotkit/info` lists what the runtime mounted.
///
/// An actor for the same reason `StubEngineClient` is one: it holds the token and the session, and
/// the UI reaches it from several tasks at once.
public actor HTTPEngineClient: EngineClient {
    private let baseURL: URL
    private let token: String?
    private let session: URLSession

    public init(baseURL: URL, token: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    // MARK: - Health

    /// Whether the engine at this address is *ours*.
    ///
    /// Parses the body rather than accepting any 200. Another process on the port would also
    /// answer 200, and an app that accepted that would happily drive somebody's unrelated dev
    /// server — which is exactly the class of bug port negotiation exists to avoid.
    public func isHealthy() async -> Bool {
        await health() != nil
    }

    /// Parsed `/health` when the body identifies this engine.
    public func health() async -> EngineHealth? {
        guard
            let (data, response) = try? await send(request(.get, "/health")),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["status"] as? String == "ok",
            object["product"] as? String == "xBot",
            let engineVersion = object["engineVersion"] as? String,
            let schemaVersion = object["schemaVersion"] as? String
        else { return nil }
        return EngineHealth(engineVersion: engineVersion, schemaVersion: schemaVersion)
    }

    // MARK: - REST

    public func agents() async throws -> [Agent] {
        let (data, _) = try await send(request(.get, "/api/agents"))
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = object["agents"] as? [[String: Any]]
        else { return [] }

        return rows.compactMap(Self.agent(from:))
    }

    public func createAgent(_ draft: AgentDraft) async throws -> Agent {
        // Name, title and roleDescription are all required by the engine's parser, even when the
        // user only typed a name. Visibility is private: this is a laptop, not a hosted roster.
        let title = draft.label.isEmpty ? draft.name : draft.label
        let (data, _) = try await send(
            request(
                .post,
                "/api/agents",
                body: [
                    "name": draft.name,
                    "title": title,
                    "roleDescription": title,
                    "visibility": "private",
                ]
            )
        )
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let row = object["agent"] as? [String: Any],
            let agent = Self.agent(from: row)
        else { throw EngineError.notRunning }
        return agent
    }

    public func createChannel(agentIds: [Agent.ID]) async throws -> Channel {
        let (data, _) = try await send(
            request(.post, "/api/channels", body: ["agentIds": agentIds])
        )
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let row = object["channel"] as? [String: Any],
            let id = row["id"] as? String
        else { throw EngineError.notRunning }
        return Channel(id: id, agentIds: row["agentIds"] as? [String] ?? agentIds)
    }

    public func channels() async throws -> [Channel] {
        let (data, _) = try await send(request(.get, "/api/channels"))
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = object["channels"] as? [[String: Any]]
        else { return [] }

        return rows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return Channel(id: id, agentIds: row["agentIds"] as? [String] ?? [])
        }
    }

    public func messages(in channel: Channel.ID) async throws -> [Message] {
        // Thread history lives behind the runtime's own thread route, keyed by the channel's
        // thread rather than by the channel. A channel with no thread yet is empty, not an error:
        // it is a conversation nobody has spoken in.
        let (data, _) = try await send(
            request(.get, "/api/channels/\(channel)")
        )
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let threadId = (object["channel"] as? [String: Any])?["threadId"] as? String
        else { return [] }

        let (threadData, response) = try await send(
            request(.get, "/api/copilotkit/threads?threadId=\(threadId)")
        )
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        guard
            let thread = try? JSONSerialization.jsonObject(with: threadData) as? [String: Any],
            let rows = thread["messages"] as? [[String: Any]]
        else { return [] }

        return rows.compactMap(Self.message(from:))
    }

    public func activity(for agent: Agent.ID) async throws -> [ActivityEntry] {
        // Held in the client for the open conversation, per docs/09-ui-spec.md — the durable
        // record is the audit trail, which is a different screen. Nothing to fetch here yet.
        []
    }

    /// Edit one agent.
    ///
    /// The engine's PATCH is PUT-shaped: its parser requires name, title, roleDescription and
    /// visibility on every call and rejects the request outright when one is missing. This used to
    /// send only the changed fields, so **every** edit — renames included, not just the model —
    /// came back 400 while the app showed the change as saved.
    ///
    /// So the current row is read first and the patch applied on top of it. One extra round trip
    /// for an edit a person makes by hand, which is the cheap side of the trade.
    public func updateAgent(_ id: Agent.ID, _ patch: AgentPatch) async throws -> Agent {
        let current = try await agentRow(id)
        var body: [String: Any] = [
            "name": patch.name ?? current["name"] as? String ?? id,
            "title": patch.label ?? current["title"] as? String ?? "",
            "roleDescription": current["roleDescription"] as? String
                ?? current["title"] as? String ?? "",
            "visibility": current["visibility"] as? String ?? "private",
        ]
        // Endpoint is re-sent because omitting it would drop the agent back to the built-in Bot.
        if let endpoint = current["endpoint"] as? String, !endpoint.isEmpty {
            body["endpoint"] = endpoint
        }
        // Only when this edit changed it. Absent means "leave the stored one alone" — the engine's
        // store follows the same rule the vault key does, for the same reason.
        if let model = patch.model { body["modelSelection"] = model.wireFormat }

        let (data, _) = try await send(request(.patch, "/api/agents/\(id)", body: body))
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let row = (object["agent"] as? [String: Any]) ?? object as [String: Any]?,
            let agent = Self.agent(from: row)
        else { throw EngineError.unknownChannel(id) }

        return agent
    }

    /// One agent's row as the engine holds it, for edits that must send a complete object.
    private func agentRow(_ id: Agent.ID) async throws -> [String: Any] {
        let (data, _) = try await send(request(.get, "/api/agents/\(id)"))
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EngineError.unknownChannel(id)
        }
        return (object["agent"] as? [String: Any]) ?? object
    }

    public func availableModels() async throws -> [ModelSelection] {
        // Comes from the router once ADR-0002 lands. Until then the engine has one provider from
        // its environment, and offering a picker over models it cannot actually reach would be a
        // settings screen that lies.
        []
    }

    public func setControl(_ control: ScreenControl, for agent: Agent.ID) async throws {
        let path = control == .human ? "take" : "release"
        _ = try await send(request(.post, "/api/computers/\(agent)/control/\(path)", body: [:]))
    }

    public nonisolated func screen(
        for agent: Agent.ID,
        cadence: ScreenCadence
    ) -> AsyncStream<ScreenFrame> {
        AsyncStream { continuation in
            guard let interval = cadence.interval else {
                continuation.finish()
                return
            }
            let task = Task {
                while !Task.isCancelled {
                    if let frame = await self.screenshot(for: agent) {
                        continuation.yield(frame)
                    }
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func screenshot(for agent: Agent.ID) async -> ScreenFrame? {
        guard
            let (data, response) = try? await send(
                request(.get, "/api/computers/\(agent)/screenshot")
            ),
            (response as? HTTPURLResponse)?.statusCode == 200,
            !data.isEmpty
        else { return nil }
        // Dimensions come from the image itself when the panel decodes it. Carrying the engine's
        // claimed size as well would give two sources of truth for one picture.
        return ScreenFrame(imageData: data, width: 0, height: 0)
    }

    // MARK: - The turn stream

    public nonisolated func send(
        _ text: String,
        to channel: Channel.ID
    ) -> AsyncThrowingStream<TurnEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.stream(text, to: channel, into: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func stream(
        _ text: String,
        to channel: Channel.ID,
        into continuation: AsyncThrowingStream<TurnEvent, Error>.Continuation
    ) async throws {
        let (channelData, _) = try await send(request(.get, "/api/channels/\(channel)"))
        guard
            let object = try? JSONSerialization.jsonObject(with: channelData) as? [String: Any],
            let row = object["channel"] as? [String: Any],
            let threadId = row["threadId"] as? String,
            let agentId = (row["agentIds"] as? [String])?.first
        else {
            continuation.finish(throwing: EngineError.unknownChannel(channel))
            return
        }

        var request = request(
            .post,
            "/api/copilotkit/agent/\(agentId)/run",
            body: [
                "threadId": threadId,
                "runId": UUID().uuidString,
                "messages": [["id": UUID().uuidString, "role": "user", "content": text]],
                "state": [:],
                "tools": [],
                "context": [],
                "forwardedProps": [:],
            ]
        )
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // No timeout on the stream itself. A turn can legitimately take minutes while an agent
        // browses, and a URLSession default would cut it off mid-answer.
        request.timeoutInterval = .infinity

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            continuation.finish(
                throwing: EngineError.streamRejected(status: code)
            )
            return
        }

        var parser = ServerSentEventParser()
        for try await line in Self.rawLines(of: bytes) {
            if Task.isCancelled { break }
            guard let event = parser.consume(line) else { continue }
            guard let turn = AGUIDecoder.decode(event) else { continue }
            continuation.yield(turn)
        }
        continuation.finish()
    }

    /// `AsyncBytes.lines` looked like the obvious way to drive the parser, and is wrong: it omits
    /// empty lines, which is exactly the blank line SSE dispatches an event on. Splitting on `\n`
    /// ourselves, byte by byte, is what keeps that boundary — the parser strips any trailing `\r`
    /// itself, so this only needs to find the `\n`.
    private static func rawLines(of bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var buffer: [UInt8] = []
                do {
                    for try await byte in bytes {
                        guard byte == 0x0A else {
                            buffer.append(byte)
                            continue
                        }
                        continuation.yield(String(decoding: buffer, as: UTF8.self))
                        buffer.removeAll(keepingCapacity: true)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Plumbing

    // MARK: - Plugins

    public func pluginsPage() async throws -> PluginsPage {
        let (data, _) = try await send(request(.get, "/api/plugins"))
        guard let page = PluginDecoding.pluginsPage(from: data) else { throw EngineError.notRunning }
        return page
    }

    public func grantedPlugins(for agent: Agent.ID) async throws -> GrantedPlugins {
        let path = "/api/plugins/for/\(agent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? agent)"
        let (data, _) = try await send(request(.get, path))
        guard let granted = PluginDecoding.grantedPlugins(from: data) else { throw EngineError.notRunning }
        return granted
    }

    public func grantPlugin(kind: PluginGrantKind, ref: String, to agent: Agent.ID) async throws {
        _ = try await send(
            request(
                .post,
                "/api/plugins/grants",
                body: ["kind": kind.rawValue, "ref": ref, "agentId": agent]
            )
        )
    }

    public func revokePlugin(kind: PluginGrantKind, ref: String, from agent: Agent.ID) async throws {
        let encodedRef = ref.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ref
        let path = "/api/plugins/grants?kind=\(kind.rawValue)&ref=\(encodedRef)&agentId=\(agent)"
        _ = try await send(request(.delete, path))
    }

    public func addPluginServer(catalogueKey: String) async throws {
        _ = try await send(
            request(.post, "/api/plugins/servers", body: ["key": catalogueKey])
        )
    }

    public func handoffGrants(for agent: Agent.ID) async throws -> HandoffGrants {
        let path = "/api/agents/\(agent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? agent)/handoff"
        let (data, _) = try await send(request(.get, path))
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let handoff = object["handoff"] as? [String: Any]
        else { throw EngineError.notRunning }
        return HandoffGrants(
            enabled: handoff["enabled"] as? Bool ?? false,
            canGrant: handoff["canGrant"] as? Bool ?? false,
            reachable: handoff["reachable"] as? [String] ?? [],
            grantable: handoff["grantable"] as? Bool ?? false
        )
    }

    private enum Method: String {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    private func request(
        _ method: Method,
        _ path: String,
        body: [String: Any]? = nil
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)!)
        request.httpMethod = method.rawValue
        if let token {
            // Loopback is not a boundary on a shared machine; this token is. Every request
            // carries it, including the ones that look harmless.
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    private static func agent(from row: [String: Any]) -> Agent? {
        guard let id = row["id"] as? String else { return nil }
        return Agent(
            id: id,
            name: row["name"] as? String ?? id,
            // Upstream calls the one-line role `title`.
            label: row["title"] as? String ?? row["roleDescription"] as? String ?? "",
            avatarSeed: row["avatarSeed"] as? String ?? id,
            model: Self.model(from: row["modelSelection"] as? [String: Any])
        )
    }

    private static func model(from row: [String: Any]?) -> ModelSelection? {
        // `providerId`, the engine's spelling — see shared/model-selection.ts. `provider` was what
        // this read before the router existed, and the engine has never sent it.
        guard let row, let providerID = row["providerId"] as? String else { return nil }
        return ModelSelection(
            provider: ModelSelection.displayName(
                providerID: providerID,
                baseURL: row["baseURL"] as? String
            ),
            providerID: providerID,
            model: row["model"] as? String ?? "",
            baseURL: row["baseURL"] as? String,
            capabilities: row["capabilities"] as? [String] ?? []
        )
    }

    private static func message(from row: [String: Any]) -> Message? {
        guard let id = row["id"] as? String, let role = row["role"] as? String else { return nil }
        // Content is a string on a plain message and absent on a tool-call-only assistant row,
        // which is a real shape the engine sends rather than a defensive guess.
        let text = row["content"] as? String ?? ""
        guard !text.isEmpty else { return nil }
        return Message(
            id: id,
            author: role == "user" ? .user : .agent(row["agentId"] as? String ?? ""),
            text: text,
            state: .complete
        )
    }
}
