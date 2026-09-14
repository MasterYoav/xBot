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
        let role = draft.roleDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        var body: [String: Any] = [
            "name": draft.name,
            "title": title,
            "roleDescription": role.isEmpty ? title : role,
            "visibility": "private",
        ]
        if let model = draft.model { body["modelSelection"] = model.wireFormat }
        let (data, _) = try await send(
            request(
                .post,
                "/api/agents",
                body: body
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
        /*
         * The endpoint is NOT sent.
         *
         * It used to be, on the belief that omitting it would drop the agent back to the built-in Bot.
         * The engine does the opposite — `profile-store.update` keeps the stored endpoint whenever an
         * edit carries none — and re-sending it was actively harmful: every agent this app creates
         * lives on the managed Bot at a loopback address, which the engine's own guard refuses as
         * "inside this deployment's own network". So every rename, every relabel and every model
         * change failed, for every agent, the moment it met a real engine. Found by the live tests;
         * no stub could have shown it.
         */
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

    public func actionPolicy() async throws -> ActionPolicy {
        let (data, response) = try await send(request(.get, "/api/computers/policy"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw EngineError.notRunning }
        let wrapper = try JSONDecoder().decode(PolicyResponse.self, from: data)
        return wrapper.policy
    }

    public func saveActionPolicy(_ policy: ActionPolicy) async throws -> ActionPolicy {
        let encoded = try JSONEncoder().encode(policy)
        let body = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
        let (data, response) = try await send(request(.put, "/api/computers/policy", body: body))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw EngineError.notRunning }
        let wrapper = try JSONDecoder().decode(PolicyResponse.self, from: data)
        return wrapper.policy
    }

    private struct PolicyResponse: Decodable {
        let policy: ActionPolicy
    }

    // MARK: - Routines

    public func routines() async throws -> [Routine] {
        let (data, response) = try await send(request(.get, "/api/routines"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw EngineError.notRunning }
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = object["routines"] as? [[String: Any]]
        else { return [] }
        return rows.compactMap(Self.routine(from:))
    }

    public func setRoutineEnabled(_ id: String, enabled: Bool) async throws {
        let path = "/api/routines/\(id)/enabled"
        let (_, response) = try await send(request(.put, path, body: ["enabled": enabled]))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw EngineError.notRunning }
    }

    public func deleteRoutine(_ id: String) async throws {
        let (_, response) = try await send(request(.delete, "/api/routines/\(id)"))
        // 204 on success, and 404 for a routine that is already gone — which is the state the
        // caller wanted. Only a real failure is worth putting in front of somebody.
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 204 || status == 404 else { throw EngineError.notRunning }
    }

    // MARK: - Model keys

    public func liveModelKeys() async throws -> [StoredModelKey] {
        let (data, response) = try await send(request(.get, "/api/admin/credentials"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw EngineError.notRunning }
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = object["credentials"] as? [[String: Any]]
        else { return [] }
        return rows.compactMap { row in
            guard
                row["kind"] as? String == "model",
                row["revokedAt"] == nil || row["revokedAt"] is NSNull,
                let id = row["id"] as? String,
                let provider = row["provider"] as? String,
                let keyId = row["keyId"] as? String,
                // Only what this app wrote. Anything else in the vault is somebody's deliberate
                // choice made elsewhere, and a sync must never revoke it.
                keyId.hasPrefix(ModelKeyIdentity.prefix)
            else { return nil }
            let metadata = row["metadata"] as? [String: Any]
            return StoredModelKey(
                id: id, provider: provider, keyId: keyId,
                fingerprint: metadata?["fingerprint"] as? String
            )
        }
    }

    public func storeModelKey(
        _ plaintext: String, providerId: String, baseURL: String?, fingerprint: String
    ) async throws {
        let body: [String: Any] = [
            "kind": "model",
            "provider": providerId,
            "keyId": ModelKeyIdentity.keyId(providerId: providerId, baseURL: baseURL),
            "plaintext": plaintext,
            "metadata": ["source": "xbot-app", "fingerprint": fingerprint],
        ]
        let (_, response) = try await send(request(.post, "/api/admin/credentials", body: body))
        guard (response as? HTTPURLResponse)?.statusCode == 201 else { throw EngineError.notRunning }
    }

    public func revokeModelKey(credentialId: String) async throws {
        let path = "/api/admin/credentials/\(credentialId)/revoke"
        let (_, response) = try await send(request(.post, path, body: [:]))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw EngineError.notRunning }
    }

    private static func routine(from row: [String: Any]) -> Routine? {
        guard let id = row["id"] as? String, let agentId = row["agentId"] as? String else {
            return nil
        }
        let channel = row["channel"] as? [String: Any]
        let lastRun = row["lastRun"] as? [String: Any]
        return Routine(
            id: id,
            agentId: agentId,
            // Shown, never parsed. The engine's own comment: treat it as opaque display text.
            schedule: row["schedule"] as? String ?? "",
            timezone: row["timezone"] as? String ?? "",
            instruction: row["instruction"] as? String ?? "",
            channelName: channel?["name"] as? String,
            channelIsGone: channel?["gone"] as? Bool ?? false,
            enabled: row["enabled"] as? Bool ?? true,
            nextRunAt: (row["nextRunAt"] as? String).flatMap(auditDate),
            lastRunStatus: lastRun?["status"] as? String,
            lastRunAt: (lastRun?["at"] as? String).flatMap(auditDate)
        )
    }


    public func auditEvents(_ query: AuditQuery) async throws -> AuditPage {
        var components = URLComponents(
            url: URL(string: "/api/admin/audit-events", relativeTo: baseURL)!,
            resolvingAgainstBaseURL: true
        )
        var items = [URLQueryItem(name: "limit", value: "\(query.limit)")]
        if let eventType = query.eventType, !eventType.isEmpty {
            items.append(URLQueryItem(name: "eventType", value: eventType))
        }
        if let targetId = query.targetId, !targetId.isEmpty {
            items.append(URLQueryItem(name: "targetId", value: targetId))
        }
        if let cursor = query.cursor, !cursor.isEmpty {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components?.queryItems = items
        guard let url = components?.url else { return AuditPage(events: []) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await send(request)
        return Self.auditPage(from: data)
    }

    /// Decode a page, dropping rows that cannot be read rather than failing the screen.
    ///
    /// A trail with one unreadable row is still worth showing: this is the screen somebody opens
    /// when they are worried, and an error where the history should be is the least useful thing it
    /// could do.
    static func auditPage(from data: Data) -> AuditPage {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AuditPage(events: [])
        }
        let rows = (object["events"] as? [[String: Any]]) ?? (object["items"] as? [[String: Any]]) ?? []
        return AuditPage(
            events: rows.compactMap(auditEvent(from:)),
            nextCursor: object["nextCursor"] as? String ?? object["cursor"] as? String
        )
    }

    static func auditEvent(from row: [String: Any]) -> AuditEvent? {
        guard let id = row["id"] as? String, let eventType = row["eventType"] as? String else {
            return nil
        }
        return AuditEvent(
            id: id,
            actorUserId: row["actorUserId"] as? String,
            eventType: eventType,
            targetType: row["targetType"] as? String ?? "",
            targetId: row["targetId"] as? String,
            createdAt: auditDate(row["createdAt"] as? String ?? "") ?? Date(),
            summary: auditSummary(row["payload"] as? [String: Any])
        )
    }

    /// The payload's own values, joined — never the raw JSON.
    ///
    /// Upstream records that a secret was supplied and its length rather than the secret, and keys
    /// are dropped here so a payload that gains a field does not put it on screen beside somebody
    /// without anybody deciding to.
    static func auditSummary(_ payload: [String: Any]?) -> String {
        guard let payload, !payload.isEmpty else { return "" }
        return payload.keys.sorted()
            .compactMap { key -> String? in
                guard let value = payload[key] else { return nil }
                if let text = value as? String { return "\(key): \(text)" }
                if let flag = value as? Bool { return flag ? key : nil }
                if let number = value as? NSNumber { return "\(key): \(number)" }
                return nil
            }
            .joined(separator: " · ")
    }

    /// Built per call rather than shared. `ISO8601DateFormatter` is not `Sendable`, and a static
    /// one is a mutable global under strict concurrency — the cost of making one is a rounding
    /// error beside a network request.
    static func auditDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // Postgres timestamps arrive both ways depending on precision, and a row with a whole
        // number of seconds must not fall back to "now" and sort itself to the top.
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    public func availableModels() async throws -> [ModelSelection] {
        // Empty on purpose, and the app's own catalog fills the picker instead (`AppState` falls back
        // to connected vendors plus custom endpoints). The engine has no model list to give: its Bot
        // runs in per-run mode with no provider of its own, and which vendors are usable is decided by
        // which keys the Mac holds — knowledge that lives on this side, not in the container.
        []
    }

    public func setControl(_ control: ScreenControl, for agent: Agent.ID) async throws {
        let path = control == .human ? "take" : "release"
        _ = try await send(request(.post, "/api/computers/\(agent)/control/\(path)", body: [:]))
    }

    public func controlState(for agent: Agent.ID) async throws -> ComputerControlState {
        let (data, response) = try await send(request(.get, "/api/computers/\(agent)/control"))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw EngineError.notRunning }
        return ComputerControlState(
            holder: row["holder"] as? String == "human" ? .human : .agent,
            helpReason: row["requested"] as? Bool == true ? row["reason"] as? String ?? "" : nil,
            secretWanted: row["secretWanted"] as? String
        )
    }

    public func supplySecret(_ text: String, for agent: Agent.ID) async -> String? {
        let fallback = String(localized: "That didn't reach the page. Try again.")
        guard let (data, response) = try? await send(request(.post, "/api/computers/\(agent)/human/secret", body: ["text": text])) else {
            return fallback
        }
        if (response as? HTTPURLResponse)?.statusCode == 200 { return nil }
        // The engine's own sentence, which never contains the value: it names what went wrong.
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? fallback
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

    /// How many times one message may go round the loop of client tools before it is stopped.
    /// CopilotKit's own client caps its follow-ups the same way, so a model that keeps calling the same
    /// tool cannot spin forever.
    static let maxToolRounds = 25

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

        /*
         * The whole conversation, not just this message.
         *
         * The runtime gives the agent exactly the messages a run carries and never adds the thread's
         * history — it only uses history to skip persisting what it already has. Sending the newest
         * message alone meant no agent remembered anything said before it. See `WireTranscript`.
         */
        var transcript = WireTranscript(messages: try await threadMessages(threadId))
        transcript.append(WireMessage(id: UUID().uuidString, role: "user", content: text))

        for _ in 0..<Self.maxToolRounds {
            if Task.isCancelled { break }
            var finished = false
            var failed = false

            var request = request(
                .post,
                "/api/copilotkit/agent/\(agentId)/run",
                body: [
                    "threadId": threadId,
                    "runId": UUID().uuidString,
                    "messages": transcript.messages.map(\.dictionary),
                    "state": [:],
                    // The agent's computer, offered on every run as upstream's client offers it.
                    "tools": ComputerTools.wireTools,
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
                continuation.finish(throwing: EngineError.streamRejected(status: code))
                return
            }

            var parser = ServerSentEventParser()
            for try await line in Self.rawLines(of: bytes) {
                if Task.isCancelled { break }
                guard let event = parser.consume(line) else { continue }
                if let json = try? JSONSerialization.jsonObject(with: Data(event.data.utf8)) as? [String: Any] {
                    transcript.apply(json)
                }
                guard let turn = AGUIDecoder.decode(event) else { continue }
                switch turn {
                case .runFinished:
                    // Held back: a run that ended on client tool calls is not the end of the turn.
                    finished = true
                case .failed:
                    failed = true
                    continuation.yield(turn)
                default:
                    continuation.yield(turn)
                }
            }

            let pending = transcript.pendingClientCalls
            guard finished, !failed, !pending.isEmpty else {
                // Done, failed, or cut off. Only a run that genuinely finished is reported as one; a
                // stream that simply stopped lets the caller say the reply was interrupted.
                if finished, !failed { continuation.yield(.runFinished) }
                continuation.finish()
                return
            }

            // The agent's computer: run each call, then continue the same turn with the results.
            for call in pending {
                if Task.isCancelled { break }
                let content = await executeComputerTool(agentId: agentId, name: call.name, argumentsJSON: call.arguments)
                transcript.appendToolResult(callId: call.id, content: content)
            }
        }

        continuation.yield(.failed(
            messageId: "",
            reason: String(localized: "The agent kept using its computer without finishing, so it was stopped. Try asking again, more specifically.")
        ))
        continuation.finish()
    }

    /// The thread's messages as AG-UI messages, or none for a thread that does not exist yet.
    private func threadMessages(_ threadId: String) async throws -> [WireMessage] {
        let (data, response) = try await send(request(.get, "/api/copilotkit/threads?threadId=\(threadId)"))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let thread = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = thread["messages"] as? [[String: Any]]
        else { return [] }
        return rows.compactMap(WireMessage.init(row:))
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
        case put = "PUT"
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

    // MARK: - The computer, as client tools

    /// How long a secret or help request waits for the person. Upstream's figure: long enough to
    /// come back to the Mac, finite so the run can end.
    static let personWait: Duration = .seconds(600)

    /**
     Run one client tool call against the engine and return the tool result's content.

     Mirrors upstream's handlers in `computer-tools.tsx`, so the Bot sees exactly what it would see in
     OpenBot's own client. A request that cannot reach the engine is a result the Bot can read, not a
     thrown error: the run continues and says what it could not do.
     */
    public func executeComputerTool(
        agentId: Agent.ID, name: String, argumentsJSON: String
    ) async -> String {
        guard let route = ComputerTools.route(name: name, argumentsJSON: argumentsJSON) else {
            return ComputerTools.content(["ok": false, "reason": "This client has no tool called \(name)."])
        }
        let computer = "/api/computers/\(agentId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? agentId)"

        switch route {
        case .computer(let path, let body):
            let outcome = await computerCall(computer + path, body: body)
            return ComputerTools.content(name == "computer_navigate" ? ComputerTools.navigateOutcome(outcome) : outcome)

        case .waitForPerson(let path, let body, let until):
            let asked = await computerCall(computer + path, body: body)
            guard asked["ok"] as? Bool == true else { return ComputerTools.content(asked) }
            let answer = await waitForPerson(control: computer + "/control", until: until, askedSince: asked["since"] as? String)
            return ComputerTools.content(["ok": true, "result": Self.sentence(for: answer, until: until)])

        case .declined(let body):
            let path = "/api/agents/\(agentId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? agentId)/declined"
            let outcome = await computerCall(path, body: body)
            // A plain sentence, as upstream returns: audit bookkeeping must not stop the Bot answering.
            return outcome["ok"] as? Bool == true
                ? "Recorded. Now tell the person what you decided and why."
                : "That could not be recorded. Tell the person what you decided anyway."
        }
    }

    private func computerCall(_ path: String, body: String?) async -> [String: Any] {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)!)
        request.httpMethod = body == nil ? "GET" : "POST"
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }
        // Long enough for a slow page load; the engine bounds its own browser actions.
        request.timeoutInterval = 120
        guard let (data, response) = try? await send(request) else {
            return ["ok": false, "reason": "The assistant's computer could not be reached."]
        }
        return ComputerTools.outcome(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }

    private enum PersonAnswer { case answered, gaveUp, cancelled }

    private func waitForPerson(control: String, until: ComputerTools.PersonWait, askedSince: String?) async -> PersonAnswer {
        let deadline = ContinuousClock.now + Self.personWait
        // The engine drops an unanswered help request after ten minutes; that is nobody coming, not
        // somebody finishing, so handing back only counts once a person actually held the wheel. A take
        // and hand-back can both fall between two polls; `since` moves on each, and expiry leaves it.
        var personDrove = false
        while ContinuousClock.now < deadline {
            if Task.isCancelled { return .cancelled }
            let state = await computerCall(control, body: nil)
            if state["ok"] as? Bool == true {
                switch until {
                case .secretEntered:
                    if state["secretWanted"] == nil || state["secretWanted"] is NSNull { return .answered }
                case .controlReturned:
                    let holder = state["holder"] as? String
                    if holder == "human" || (askedSince != nil && state["since"] as? String != askedSince) {
                        personDrove = true
                    }
                    if holder == "bot", state["requested"] as? Bool != true {
                        return personDrove ? .answered : .gaveUp
                    }
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
        return .gaveUp
    }

    /// Upstream's sentences for how a wait on the person ended.
    private static func sentence(for answer: PersonAnswer, until: ComputerTools.PersonWait) -> String {
        switch (answer, until) {
        case (.answered, .secretEntered(let label)):
            "The person has entered \(label) into the field. It was typed straight into the page and you were not told what it is."
        case (.gaveUp, .secretEntered(let label)):
            "Nobody entered \(label). Do not ask for it another way."
        case (.answered, .controlReturned):
            "The person has finished and handed control back. Take a fresh snapshot: the page may have changed while they were driving."
        case (.gaveUp, .controlReturned):
            "Nobody took control. Say what you still need rather than trying to do it yourself."
        case (.cancelled, _):
            "The request was cancelled."
        }
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
        // A person's words and an agent's, nothing else. A `tool` row is a computer result — JSON the
        // model reads — and the client-tool loop persists one per call; shown, it was a bubble of JSON.
        guard role == "user" || role == "assistant" else { return nil }
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
