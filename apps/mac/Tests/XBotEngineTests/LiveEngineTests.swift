import Foundation
import Testing
@testable import XBotEngine

/**
 `HTTPEngineClient` against a real engine, not a stub.

 Skipped unless `XBOT_LIVE_ENGINE_URL` is set, so CI and ordinary runs never need Docker. Every other
 test in this target decodes JSON the client's author wrote down while reading the engine's source;
 a misread route or a DTO nested one level differently passes all of them. This is the one place the
 client meets the engine's actual answers.

 Point it at a **throwaway** engine, never at somebody's own: it creates an agent and a channel.

     XBOT_LIVE_ENGINE_URL=http://127.0.0.1:49390 \
     XBOT_LIVE_ENGINE_TOKEN_FILE=/path/to/token \
     swift test --filter LiveEngine
 */
@Suite(.enabled(if: ProcessInfo.processInfo.environment["XBOT_LIVE_ENGINE_URL"] != nil))
struct LiveEngineTests {
    private var client: HTTPEngineClient {
        let env = ProcessInfo.processInfo.environment
        let url = URL(string: env["XBOT_LIVE_ENGINE_URL"] ?? "http://127.0.0.1:3001")!
        let token = env["XBOT_LIVE_ENGINE_TOKEN_FILE"].flatMap {
            try? String(contentsOfFile: $0, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return HTTPEngineClient(baseURL: url, token: token)
    }

    @Test func healthIdentifiesTheEngine() async {
        let health = await client.health()
        #expect(health != nil)
        #expect(health?.schemaVersion.isEmpty == false)
    }

    @Test func theReadEndpointsAnswerInTheShapeTheClientDecodes() async throws {
        let client = client
        _ = try await client.agents()
        _ = try await client.channels()
        _ = try await client.pluginsPage()
        _ = try await client.availableModels()
        // The three written from reading the engine's source in this pass, never run against it.
        _ = try await client.routines()
        _ = try await client.actionPolicy()
        let audit = try await client.auditEvents(AuditQuery(limit: 5))
        #expect(audit.events.count <= 5)
    }

    @Test func anAgentAndItsConversationRoundTrip() async throws {
        let client = client
        let created = try await client.createAgent(AgentDraft(name: "Live check \(UUID().uuidString.prefix(6))"))
        #expect(try await client.agents().contains { $0.id == created.id })

        let renamed = try await client.updateAgent(created.id, AgentPatch(name: "Renamed live check"))
        #expect(renamed.name == "Renamed live check")

        let channel = try await client.createChannel(agentIds: [created.id])
        #expect(channel.agentIds.contains(created.id))
        _ = try await client.messages(in: channel.id)
        _ = try await client.grantedPlugins(for: created.id)
        _ = try await client.handoffGrants(for: created.id)
    }

    /**
     A key goes from the app, through the vault, onto the run, to the vendor — proven with a key that
     does not work.

     No real key is needed to prove every hop. A deliberately invalid Anthropic key is stored the way
     the app stores one; an agent is pointed at Anthropic; a message is sent. If the key never reached
     the vendor the failure would be the router's "no key" sentence, or no managed Bot at all. Only a
     key that travelled the whole way comes back as Anthropic refusing it.
     */
    // OpenAI, not the Anthropic key the next test stores: Swift Testing runs them at once, and two
    // replaces of one key racing each other is a 500 from the engine's vault, not a client bug.
    @Test func aStoredKeyReachesTheVault() async throws {
        let client = client
        try await client.storeModelKey(
            "sk-xbot-live-check-deliberately-invalid",
            providerId: "openai", baseURL: nil, fingerprint: "live-check"
        )
        let stored = try await client.liveModelKeys().first { $0.keyId == "xbot-model:openai" }
        #expect(stored?.fingerprint == "live-check")

        // Replacing it leaves one live key, not two.
        try await client.storeModelKey("sk-replaced", providerId: "openai", baseURL: nil, fingerprint: "live-check-2")
        let live = try await client.liveModelKeys().filter { $0.keyId == "xbot-model:openai" }
        #expect(live.count == 1)
        #expect(live.first?.fingerprint == "live-check-2")

        if let id = live.first?.id { try await client.revokeModelKey(credentialId: id) }
        #expect(try await client.liveModelKeys().allSatisfy { $0.keyId != "xbot-model:openai" })
    }

    /// Since ADR-0008, `LocalThreadRunner` answers this without an Intelligence key — the throwaway
    /// engine this suite runs against no longer needs `XBOT_LIVE_ENGINE_HAS_INTELLIGENCE` set. The
    /// variable still gates a run against a deployment that configures Intelligence by hand, which is
    /// why the check stays rather than being deleted outright.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["XBOT_LIVE_ENGINE_HAS_INTELLIGENCE"] != "0"))
    func aStoredKeyTravelsAllTheWayToTheVendor() async throws {
        let client = client
        try await client.storeModelKey(
            "sk-ant-api03-xbot-live-check-deliberately-invalid",
            providerId: "anthropic", baseURL: nil, fingerprint: "live-check"
        )

        let agent = try await client.createAgent(AgentDraft(
            name: "Live key check",
            model: ModelSelection(provider: "Anthropic", providerID: "anthropic", model: "claude-sonnet-4-5", baseURL: nil, capabilities: [])
        ))
        let channel = try await client.createChannel(agentIds: [agent.id])

        var outcome = "no failure"
        do {
            for try await event in client.send("hello", to: channel.id) {
                if case .failed(_, let reason) = event { outcome = reason; break }
            }
        } catch {
            outcome = "threw: \(error)"
        }
        print("live key outcome:", outcome)
        #expect(outcome.contains("Anthropic"))
    }

    /**
     A send that cannot be answered ends, and says so.

     A throwaway engine has no CopilotKit key and no model, so no turn can succeed. What matters is
     how it fails: the stream must finish — with a failure event or a thrown error — rather than hang,
     because a hung stream is a bubble spinning forever with the composer locked behind it.
     */
    @Test func aSendThatCannotBeAnsweredEndsRatherThanHanging() async throws {
        let client = client
        let agent = try await client.createAgent(AgentDraft(name: "Live send check"))
        let channel = try await client.createChannel(agentIds: [agent.id])

        let outcome = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var saw = "ended without an event"
                do {
                    for try await event in client.send("hello", to: channel.id) {
                        switch event {
                        case .failed(_, let reason): return "failed: \(reason)"
                        case .runFinished: saw = "finished"
                        default: continue
                        }
                    }
                } catch {
                    return "threw: \(error)"
                }
                return saw
            }
            group.addTask {
                try await Task.sleep(for: .seconds(60))
                return "HUNG"
            }
            let first = try await group.next() ?? "HUNG"
            group.cancelAll()
            return first
        }
        print("live send outcome:", outcome)
        #expect(outcome != "HUNG")
    }
}

/**
 The agent's computer, driven through the client tools against a real engine and a real browser.

 Skipped unless `XBOT_LIVE_ENGINE_URL` is set. These are the calls an agent's model makes through
 `ComputerTools`; before them no xBot agent had ever been offered its computer. The model is not
 needed to prove the computer half — only the executor and the engine's own `/api/computers` routes.
 */
@Suite(.enabled(if: ProcessInfo.processInfo.environment["XBOT_LIVE_ENGINE_URL"] != nil))
struct LiveComputerToolsTests {
    private var client: HTTPEngineClient {
        let env = ProcessInfo.processInfo.environment
        let url = URL(string: env["XBOT_LIVE_ENGINE_URL"] ?? "http://127.0.0.1:3001")!
        let token = env["XBOT_LIVE_ENGINE_TOKEN_FILE"].flatMap {
            try? String(contentsOfFile: $0, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return HTTPEngineClient(baseURL: url, token: token)
    }

    private func outcome(_ content: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any]) ?? [:]
    }

    @Test func anAgentCanUseItsBrowserFilesAndShell() async throws {
        let client = client
        let agent = try await client.createAgent(AgentDraft(name: "Computer check"))

        let navigated = outcome(await client.executeComputerTool(
            agentId: agent.id, name: "computer_navigate", argumentsJSON: #"{"url":"https://example.com"}"#
        ))
        print("navigate:", navigated["ok"] ?? "-", navigated["title"] ?? navigated["reason"] ?? "-")
        #expect(navigated["ok"] as? Bool == true)
        #expect((navigated["title"] as? String)?.contains("Example") == true)

        let snapshot = outcome(await client.executeComputerTool(
            agentId: agent.id, name: "computer_snapshot", argumentsJSON: "{}"
        ))
        print("snapshot:", snapshot["ok"] ?? "-", (snapshot["elements"] as? [Any])?.count ?? -1, snapshot["reason"] ?? "")
        #expect(snapshot["ok"] as? Bool == true)
        #expect(snapshot["snapshotId"] != nil)

        let written = outcome(await client.executeComputerTool(
            agentId: agent.id, name: "computer_write_file", argumentsJSON: #"{"path":"notes/check.md","contents":"hello from the client tools"}"#
        ))
        print("write:", written["ok"] ?? "-", written["bytes"] ?? written["reason"] ?? "-")
        #expect(written["ok"] as? Bool == true)

        let read = outcome(await client.executeComputerTool(
            agentId: agent.id, name: "computer_read_file", argumentsJSON: #"{"path":"notes/check.md"}"#
        ))
        #expect(read["text"] as? String == "hello from the client tools")

        let command = outcome(await client.executeComputerTool(
            agentId: agent.id, name: "computer_run_command", argumentsJSON: #"{"command":"cat notes/check.md | wc -w"}"#
        ))
        print("exec:", command["ok"] ?? "-", command["stdout"] ?? command["reason"] ?? "-")
        #expect(command["ok"] as? Bool == true)
        #expect((command["stdout"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == "5")
    }

    /// The asks, as the conversation reads them: a help request, a takeover, a hand-back, and a secret
    /// nothing asked for being refused with the engine's own sentence.
    @Test func theAsksReadBackAsTheConversationShowsThem() async throws {
        let client = client
        let agent = try await client.createAgent(AgentDraft(name: "Ask check"))
        _ = await client.executeComputerTool(agentId: agent.id, name: "computer_navigate", argumentsJSON: #"{"url":"https://example.com"}"#)

        let asking = Task {
            await client.executeComputerTool(agentId: agent.id, name: "computer_request_help", argumentsJSON: #"{"reason":"Sign in, please"}"#)
        }
        var state = try await client.controlState(for: agent.id)
        for _ in 0..<20 where state.helpReason == nil {
            try await Task.sleep(for: .milliseconds(250))
            state = try await client.controlState(for: agent.id)
        }
        #expect(state.helpReason == "Sign in, please")

        try await client.setControl(.human, for: agent.id)
        #expect(try await client.controlState(for: agent.id).holder == .human)
        try await client.setControl(.agent, for: agent.id)
        let answer = await asking.value
        print("help:", answer)
        #expect(answer.contains("handed control back"))

        let refused = await client.supplySecret("not asked for", for: agent.id)
        print("unasked secret:", refused ?? "accepted")
        #expect(refused != nil)
    }
}

/**
 A conversation that succeeds, against a real model — a local Ollama, so no key is needed.

 Skipped unless `XBOT_LIVE_OLLAMA_MODEL` is set as well, to a pulled model that can call tools
 (`qwen2.5:7b` works). Everything above proves how a turn fails; this is the one place a turn is
 proven to answer, remember within a conversation, drive its computer through the client-tool loop,
 and leave the thread holding each message once. Launch checklist item 5, the engine half.

 A model is not deterministic, so the prompts ask for things a small one reliably gets right and the
 assertions check for a word, never a sentence.
 */
@Suite(.enabled(if: ProcessInfo.processInfo.environment["XBOT_LIVE_ENGINE_URL"] != nil
    && ProcessInfo.processInfo.environment["XBOT_LIVE_OLLAMA_MODEL"] != nil))
struct LiveConversationTests {
    private let env = ProcessInfo.processInfo.environment

    private var client: HTTPEngineClient {
        let url = URL(string: env["XBOT_LIVE_ENGINE_URL"] ?? "http://127.0.0.1:3001")!
        let token = env["XBOT_LIVE_ENGINE_TOKEN_FILE"].flatMap {
            try? String(contentsOfFile: $0, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return HTTPEngineClient(baseURL: url, token: token)
    }

    private struct Turn {
        var text = ""
        var tools: [String] = []
        var failure: String?
    }

    private func turn(_ text: String, in channel: Channel.ID) async throws -> Turn {
        var turn = Turn()
        for try await event in client.send(text, to: channel) {
            switch event {
            case .textDelta(_, let delta): turn.text += delta
            case .toolCall(_, _, let name, _): turn.tools.append(name)
            case .failed(_, let reason): turn.failure = reason
            default: continue
            }
        }
        print("live turn:", text, "→", turn.tools, turn.failure ?? turn.text)
        return turn
    }

    @Test func aConversationAnswersRemembersUsesItsComputerAndIsKeptOnce() async throws {
        let client = client
        // What `ModelProviderCatalog.engineRouting(for: "ollama")` sends, which lives in XBotCore.
        let agent = try await client.createAgent(AgentDraft(
            name: "Conversation check",
            model: ModelSelection(
                provider: "Ollama", providerID: "openai-compatible", model: env["XBOT_LIVE_OLLAMA_MODEL"]!,
                baseURL: env["XBOT_LIVE_OLLAMA_BASE_URL"] ?? "http://host.docker.internal:11434/v1", capabilities: []
            )
        ))
        let channel = try await client.createChannel(agentIds: [agent.id])

        let told = try await turn("Remember this codeword: tangerine. Reply with just OK.", in: channel.id)
        #expect(told.failure == nil)
        #expect(!told.text.isEmpty)

        // A 7B model sometimes writes the call out as text instead of making it. That is the model's
        // choice, not the loop failing, so it gets one more ask before the loop is judged.
        var sent = 2
        var browsed = try await turn(
            "Use your browser to open https://example.com, then tell me the page's title.", in: channel.id
        )
        if !browsed.tools.contains("computer_navigate") {
            sent += 1
            browsed = try await turn("Call the computer_navigate tool with https://example.com now.", in: channel.id)
        }
        #expect(browsed.failure == nil)
        #expect(browsed.tools.contains("computer_navigate"))
        #expect(browsed.text.localizedCaseInsensitiveContains("example"))

        // Two turns and a tool loop later. Each run carries the whole conversation, so this is memory.
        let asked = try await turn("What was the codeword I gave you? Answer with the word only.", in: channel.id)
        #expect(asked.failure == nil)
        #expect(asked.text.localizedCaseInsensitiveContains("tangerine"))

        // The tool loop resends messages the thread already holds and relies on their ids matching.
        let history = try await client.messages(in: channel.id)
        print("live history:", history.map { "\($0.isFromUser ? "user" : "agent") \($0.id) \($0.text.prefix(40))" })
        #expect(Set(history.map(\.id)).count == history.count)
        #expect(history.filter(\.isFromUser).count == sent + 1)
    }
}
