import Foundation
import Testing

@testable import XBotEngine

/// The real engine, over loopback — but stubbed, so these run with no server and no Docker.
///
/// `StubURLProtocol` matches on host + path rather than owning a shared mutable session, which is
/// what lets tests run in parallel without one test's fixtures answering another's request: each
/// test mints its own unique host.
struct HTTPEngineClientTests {
    private func client(
        host: String = "stub-\(UUID().uuidString).test",
        token: String? = nil
    ) -> HTTPEngineClient {
        HTTPEngineClient(
            baseURL: URL(string: "http://\(host)")!,
            token: token,
            session: Self.session()
        )
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    // MARK: - agents / channels / messages

    @Test func agentsDecodesEachRow() async throws {
        let host = "stub-\(UUID().uuidString).test"
        let row: [String: Any] = [
            "id": "orchestrator",
            "name": "Orchestrator",
            "title": "Orchestrate and use the other agents",
            "avatarSeed": "orchestrator",
            // `providerId`, which is what the engine stores — see shared/model-selection.ts. This
            // fixture used to say `provider`, a key the engine has never sent, so it asserted the
            // client's own mistake rather than the engine's shape.
            "modelSelection": [
                "providerId": "anthropic", "model": "claude-sonnet-4.5",
                "capabilities": ["vision", "tools"],
            ],
        ]
        StubURLProtocol.register(
            .init(body: Self.json(["agents": [row]])),
            forHost: host,
            path: "/api/agents"
        )

        let agents = try await client(host: host).agents()

        #expect(agents.count == 1)
        #expect(agents.first?.id == "orchestrator")
        #expect(agents.first?.name == "Orchestrator")
        #expect(agents.first?.model?.providerID == "anthropic")
        // The vendor's name is resolved for display; the id is what routes.
        #expect(agents.first?.model?.provider == "Anthropic")
    }

    @Test func agentsDegradesToEmptyOnAMalformedBody() async throws {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(.init(body: Data("not json".utf8)), forHost: host, path: "/api/agents")

        let agents = try await client(host: host).agents()

        #expect(agents.isEmpty)
    }

    @Test func channelsDecodesEachRow() async throws {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(
            .init(body: Self.json(["channels": [["id": "channel-1", "agentIds": ["orchestrator"]]]])),
            forHost: host,
            path: "/api/channels"
        )

        let channels = try await client(host: host).channels()

        #expect(channels == [Channel(id: "channel-1", agentIds: ["orchestrator"])])
    }

    @Test func messagesFollowsTheChannelToItsThread() async throws {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(
            .init(body: Self.json(["channel": ["threadId": "thread-1"]])),
            forHost: host,
            path: "/api/channels/channel-1"
        )
        StubURLProtocol.register(
            .init(
                body: Self.json([
                    "messages": [
                        ["id": "m1", "role": "user", "content": "Check the flight"],
                        ["id": "m2", "role": "assistant", "agentId": "orchestrator", "content": "It's refundable"],
                    ]
                ])
            ),
            forHost: host,
            path: "/api/copilotkit/threads"
        )

        let messages = try await client(host: host).messages(in: "channel-1")

        #expect(messages.count == 2)
        #expect(messages[0].isFromUser)
        #expect(messages[1].text == "It's refundable")
    }

    @Test func aChannelWithNoThreadIsEmptyRatherThanAnError() async throws {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(.init(body: Self.json(["channel": [:]])), forHost: host, path: "/api/channels/channel-1")

        let messages = try await client(host: host).messages(in: "channel-1")

        #expect(messages.isEmpty)
    }

    @Test func createAgentPostsTheRequiredFields() async throws {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(
            .init(
                status: 201,
                body: Self.json(["agent": ["id": "new-1", "name": "Research", "title": "Research"]])
            ),
            forHost: host,
            path: "/api/agents"
        )

        let agent = try await client(host: host).createAgent(AgentDraft(name: "Research"))

        #expect(agent.id == "new-1")
        #expect(agent.name == "Research")
        #expect(StubURLProtocol.requestedPaths(forHost: host).contains("/api/agents"))
    }

    @Test func createChannelPostsTheAgentIds() async throws {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(
            .init(
                status: 201,
                body: Self.json(["channel": ["id": "ch-9", "agentIds": ["new-1"]]])
            ),
            forHost: host,
            path: "/api/channels"
        )

        let channel = try await client(host: host).createChannel(agentIds: ["new-1"])

        #expect(channel.id == "ch-9")
        #expect(channel.agentIds == ["new-1"])
    }

    // MARK: - updateAgent

    @Test func updateAgentRoundTripsThePatch() async throws {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(
            .init(body: Self.json(["agent": ["id": "orchestrator", "name": "Renamed", "title": "New label"]])),
            forHost: host,
            path: "/api/agents/orchestrator"
        )

        let updated = try await client(host: host).updateAgent(
            "orchestrator",
            AgentPatch(name: "Renamed", label: "New label")
        )

        #expect(updated.name == "Renamed")
        #expect(updated.label == "New label")
    }

    /**
     The engine's PATCH is PUT-shaped: its parser demands name, title, roleDescription and
     visibility and rejects the call when one is missing. This client sent only the changed fields,
     so every edit — renames included — came back 400 while the app showed it as saved.
     */
    @Test func updateAgentSendsACompleteObjectBecauseThePatchIsPutShaped() async throws {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(
            .init(
                body: Self.json([
                    "agent": [
                        "id": "orchestrator",
                        "name": "Orchestrator",
                        "title": "Runs things",
                        "roleDescription": "Orchestrates the other agents.",
                        "visibility": "private",
                    ]
                ])
            ),
            forHost: host,
            path: "/api/agents/orchestrator"
        )

        _ = try await client(host: host).updateAgent("orchestrator", AgentPatch(label: "Renamed"))

        let patch = try #require(
            StubURLProtocol.sentRequests(forHost: host).last { $0.method == "PATCH" }
        )
        // The changed field, and every field the parser requires alongside it.
        #expect(patch.body["title"] == "Renamed")
        #expect(patch.body["name"] == "Orchestrator")
        #expect(patch.body["roleDescription"] == "Orchestrates the other agents.")
        #expect(patch.body["visibility"] == "private")
    }

    /// The engine reads `providerId`. This sent `provider`, and a display name in it — so the field
    /// was dropped and picking a model from the settings pane changed nothing.
    @Test func updateAgentSendsTheEngineProviderIdRatherThanTheVendorName() async throws {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(
            .init(body: Self.json(["agent": ["id": "a", "name": "A", "title": "t"]])),
            forHost: host,
            path: "/api/agents/a"
        )

        _ = try await client(host: host).updateAgent(
            "a",
            AgentPatch(
                model: ModelSelection(
                    provider: "xAI",
                    providerID: "openai-compatible",
                    model: "grok-4",
                    baseURL: "https://api.x.ai/v1"
                )
            )
        )

        let patch = try #require(
            StubURLProtocol.sentRequests(forHost: host).last { $0.method == "PATCH" }
        )
        let selection = try #require(patch.body["modelSelection"])
        #expect(selection.contains("openai-compatible"))
        #expect(selection.contains("https://api.x.ai/v1"))
        // The vendor's name is the app's word for it and means nothing to the router.
        #expect(!selection.contains("xAI"))
    }

    /// An edit that did not touch the model must not carry one, or a rename would overwrite it.
    @Test func anEditThatDidNotTouchTheModelSendsNoSelection() async throws {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(
            .init(body: Self.json(["agent": ["id": "a", "name": "A", "title": "t"]])),
            forHost: host,
            path: "/api/agents/a"
        )

        _ = try await client(host: host).updateAgent("a", AgentPatch(name: "Renamed"))

        let patch = try #require(
            StubURLProtocol.sentRequests(forHost: host).last { $0.method == "PATCH" }
        )
        #expect(patch.body["modelSelection"] == nil)
    }

    @Test func updateAgentThrowsOnAMalformedResponse() async throws {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(.init(body: Data("{}".utf8)), forHost: host, path: "/api/agents/orchestrator")

        var thrown: EngineError?
        do {
            _ = try await client(host: host).updateAgent("orchestrator", AgentPatch(name: "x"))
        } catch let error as EngineError {
            thrown = error
        }
        #expect(thrown == .unknownChannel("orchestrator"))
    }

    // MARK: - setControl

    @Test func settingControlToHumanHitsTake() async throws {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(.init(), forHost: host, path: "/api/computers/orchestrator/control/take")
        try await client(host: host).setControl(.human, for: "orchestrator")

        #expect(StubURLProtocol.requestedPaths(forHost: host).contains("/api/computers/orchestrator/control/take"))
    }

    @Test func settingControlToAgentHitsRelease() async throws {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(.init(), forHost: host, path: "/api/computers/orchestrator/control/release")
        try await client(host: host).setControl(.agent, for: "orchestrator")

        #expect(StubURLProtocol.requestedPaths(forHost: host).contains("/api/computers/orchestrator/control/release"))
    }

    // MARK: - the turn stream

    @Test func aTurnDecodesTheWholeStreamInOrder() async throws {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(
            .init(body: Self.json(["channel": ["threadId": "thread-1", "agentIds": ["orchestrator"]]])),
            forHost: host,
            path: "/api/channels/channel-1"
        )
        StubURLProtocol.register(
            .init(body: Self.sse([
                #"{"type":"RUN_STARTED","runId":"r1"}"#,
                #"{"type":"TEXT_MESSAGE_CONTENT","messageId":"m1","delta":"hel"}"#,
                #"{"type":"TEXT_MESSAGE_CONTENT","messageId":"m1","delta":"lo"}"#,
                #"{"type":"RUN_FINISHED","runId":"r1"}"#,
            ])),
            forHost: host,
            path: "/api/copilotkit/agent/orchestrator/run"
        )

        var events: [TurnEvent] = []
        for try await event in client(host: host).send("hi", to: "channel-1") {
            events.append(event)
        }

        var text = ""
        for event in events {
            if case .textDelta(_, let delta) = event { text += delta }
        }
        #expect(text == "hello")
        #expect(events.contains { if case .finished = $0 { true } else { false } })
    }

    @Test func aNonOkStreamResponseSurfacesAsRejected() async throws {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(
            .init(body: Self.json(["channel": ["threadId": "thread-1", "agentIds": ["orchestrator"]]])),
            forHost: host,
            path: "/api/channels/channel-1"
        )
        StubURLProtocol.register(
            .init(status: 500, body: Data("nope".utf8)),
            forHost: host,
            path: "/api/copilotkit/agent/orchestrator/run"
        )

        var thrown: EngineError?
        do {
            for try await _ in client(host: host).send("hi", to: "channel-1") {}
        } catch let error as EngineError {
            thrown = error
        }
        #expect(thrown == .streamRejected(status: 500))
    }

    @Test func anUnknownChannelFailsTheStreamRatherThanHanging() async throws {
        let host = "stub-\(UUID().uuidString).test"
        // No stub registered for the channel lookup: the default 404 with an empty body.

        var thrown: EngineError?
        do {
            for try await _ in client(host: host).send("hi", to: "channel-1") {}
        } catch let error as EngineError {
            thrown = error
        }
        #expect(thrown == .unknownChannel("channel-1"))
    }

    // MARK: - health

    @Test func healthRequiresTheXBotProductField() async {
        let host = "stub-\(UUID().uuidString).test"
        StubURLProtocol.register(
            .init(body: Self.json([
                "status": "ok",
                "product": "xBot",
                "engineVersion": "1.2.3",
                "schemaVersion": "0012",
            ])),
            forHost: host,
            path: "/health"
        )
        let parsed = await client(host: host).health()
        #expect(parsed == EngineHealth(engineVersion: "1.2.3", schemaVersion: "0012"))
        #expect(await client(host: host).isHealthy())

        StubURLProtocol.register(
            .init(body: Self.json(["status": "ok"])),
            forHost: host,
            path: "/health"
        )
        #expect(await client(host: host).health() == nil)
        #expect(await client(host: host).isHealthy() == false)
    }

    // MARK: - fixtures

    private static func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    /// A canned SSE body: one `data:` line per event, each ending the required blank line.
    private static func sse(_ payloads: [String]) -> Data {
        Data(payloads.map { "data: \($0)\n\n" }.joined().utf8)
    }
}

/// Matches on host + path rather than a single shared handler, so unrelated tests running in
/// parallel never see each other's fixtures — every test mints its own unique host.
final class StubURLProtocol: URLProtocol {
    struct Stub: Sendable {
        var status: Int = 200
        var body: Data = Data()

        init(status: Int = 200, body: Data = Data()) {
            self.status = status
            self.body = body
        }
    }

    /// One request as it was actually sent, so a test can assert the body rather than trusting it.
    struct Sent: Sendable {
        var method: String
        var path: String
        var body: [String: String]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [String: Stub] = [:]
    nonisolated(unsafe) private static var seenPaths: [String: [String]] = [:]
    nonisolated(unsafe) private static var sent: [String: [Sent]] = [:]

    /// What reached this host, in order. Values are stringified: these tests assert which fields
    /// were sent and what they said, not the JSON types, and `[String: Any]` is not `Sendable`.
    static func sentRequests(forHost host: String) -> [Sent] {
        lock.lock()
        defer { lock.unlock() }
        return sent[host] ?? []
    }

    private static func record(_ request: URLRequest) {
        guard let url = request.url, let host = url.host else { return }
        // URLProtocol moves a body to the stream when the request is sent, so read both.
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            var collected = Data()
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                collected.append(contentsOf: buffer[0..<read])
            }
            stream.close()
            data = collected
        }
        let object = data.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        } ?? [:]
        let body = object.mapValues { String(describing: $0) }
        lock.lock()
        sent[host, default: []].append(
            Sent(method: request.httpMethod ?? "", path: url.path, body: body)
        )
        lock.unlock()
    }

    static func register(_ stub: Stub, forHost host: String, path: String) {
        lock.lock()
        stubs["\(host)\(path)"] = stub
        lock.unlock()
    }

    static func requestedPaths(forHost host: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return seenPaths[host] ?? []
    }

    private static func stub(for request: URLRequest) -> Stub? {
        guard let url = request.url, let host = url.host else { return nil }
        lock.lock()
        defer { lock.unlock() }
        seenPaths[host, default: []].append(url.path)
        return stubs["\(host)\(url.path)"]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.record(request)
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        // No fixture registered is a real case the client must survive — the default 404 with an
        // empty body is what an unknown route or a torn-down engine actually answers.
        let stub = Self.stub(for: request) ?? Stub(status: 404, body: Data())
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !stub.body.isEmpty {
            client?.urlProtocol(self, didLoad: stub.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
