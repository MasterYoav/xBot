import Foundation
import Testing
import XBotEngine
import XBotRuntime
@testable import XBotCore

@MainActor
struct ConversationRecoveryTests {
    @Test func failedHistoryKeepsLoadedMessages() async {
        let engine = RecoveryEngine()
        let state = AppState(engine: engine)
        await state.load()
        let before = state.messages
        #expect(!before.isEmpty)
        await engine.configure(history: true)
        await state.load()
        #expect(state.messages == before)
    }

    @Test func interruptedStreamMarksTheReplyFailed() async throws {
        let engine = RecoveryEngine()
        await engine.configure(events: [.started(messageId: "reply"), .textDelta(messageId: "reply", text: "partial")])
        let state = AppState(engine: engine)
        await state.load()
        state.send("hello")
        try await until { !state.isTurnInFlight }
        guard case .failed = state.messages.last?.state else {
            Issue.record("Interrupted reply must be retryable")
            return
        }
        #expect(state.messages.last?.text == "partial")
    }

    @Test func runErrorTargetsTheReplyRatherThanTheRunID() async throws {
        let engine = RecoveryEngine()
        await engine.configure(events: [.started(messageId: "reply"), .failed(messageId: "run-id", reason: "Unavailable")])
        let state = AppState(engine: engine)
        await state.load()
        state.send("hello")
        try await until { !state.isTurnInFlight }
        #expect(state.messages.last?.state == .failed(reason: "Unavailable"))
    }

    @Test func retryReusesThePromptAndRecovers() async throws {
        let engine = RecoveryEngine()
        await engine.configure(events: [.failed(messageId: "run", reason: "offline")])
        let state = AppState(engine: engine)
        await state.load()
        state.send("original prompt")
        try await until { !state.isTurnInFlight }
        let failed = try #require(state.messages.last)
        await engine.configure(events: [.started(messageId: "answer"), .textDelta(messageId: "answer", text: "done"), .runFinished])
        state.retry(failed.id)
        state.retry(failed.id)
        try await until { !state.isTurnInFlight }
        #expect(state.messages.filter { $0.text == "original prompt" }.count == 1)
        #expect(state.messages.last?.state == .complete)
        #expect(await engine.sentTexts == ["original prompt", "original prompt"])
    }

    @Test func failedChannelCanBeRepairedWithoutAnotherAgent() async throws {
        let engine = RecoveryEngine()
        let state = AppState(engine: engine)
        await state.load()
        let before = state.agents.count
        await engine.configure(channel: true)
        state.createAgent(named: "New")
        try await until { !state.isCreatingAgent }
        #expect(state.agents.count == before + 1)
        #expect(state.conversationCreationProblem != nil)
        #expect(!state.canSend)
        await engine.configure()
        await state.createSelectedConversation()
        #expect(state.canSend)
        #expect(state.agents.count == before + 1)
    }

    @Test func failedAgentCreationRetainsDraftForRetry() async throws {
        let engine = RecoveryEngine()
        let state = AppState(engine: engine)
        await state.load()
        await engine.configure(agent: true)
        state.createAgent(named: "Travel")
        try await until { !state.isCreatingAgent }
        #expect(state.creationProblem != nil)
        await engine.configure()
        state.retryAgentCreation()
        try await until { !state.isCreatingAgent }
        #expect(state.selectedAgent?.name == "Travel")
        #expect(state.canSend)
    }

    @Test func historyRetryClearsTheError() async {
        let engine = RecoveryEngine()
        let state = AppState(engine: engine)
        await state.load()
        await engine.configure(history: true)
        await state.retryHistory()
        #expect(state.historyProblem != nil)
        await engine.configure()
        await state.retryHistory()
        #expect(state.historyProblem == nil)
    }

    @Test func environmentReadsCredentialsOnlyWhenStarting() {
        let reads = CredentialReads()
        let environment = EngineBootstrap.environmentFactory(
            keyEncryptionKey: { "test-encryption-key" },
            engineToken: { "test-token" },
            intelligence: { reads.next() }
        )
        #expect(reads.count == 0)
        #expect(environment(3001, "gateway")["INTELLIGENCE_API_KEY"] == "test-key-1")
        #expect(environment(3001, "gateway")["INTELLIGENCE_API_KEY"] == "test-key-2")
    }

    @Test func retryOfPartialReplyKeepsOnePromptAndOneNewAnswer() async throws {
        let engine = RecoveryEngine()
        await engine.configure(events: [.started(messageId: "partial"), .textDelta(messageId: "partial", text: "unfinished")])
        let state = AppState(engine: engine)
        await state.load()
        state.send("retry this")
        try await until { !state.isTurnInFlight }
        await state.retryHistory()
        #expect(state.messages.contains { $0.id == "partial" })
        await engine.configure(events: [.started(messageId: "new"), .textDelta(messageId: "new", text: "answer"), .runFinished])
        state.retry("partial")
        try await until { !state.isTurnInFlight }
        #expect(!state.messages.contains { $0.id == "partial" })
        #expect(state.messages.filter { $0.text == "retry this" }.count == 1)
        #expect(state.messages.last?.text == "answer")
    }

    @Test func staleHistoryDoesNotOverwriteANewTurn() async throws {
        let engine = RecoveryEngine()
        let state = AppState(engine: engine)
        await state.load()
        await engine.delayNextHistory()
        let load = Task { await state.retryHistory() }
        for _ in 0..<200 {
            if await engine.waitingForHistory { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await engine.waitingForHistory)
        await engine.configure(events: [.started(messageId: "new"), .textDelta(messageId: "new", text: "new answer"), .runFinished])
        state.send("new prompt")
        try await until { !state.isTurnInFlight }
        await engine.releaseHistory()
        await load.value
        #expect(state.messages.last?.text == "new answer")
    }

    @Test func runStaysWithItsAgentAndCannotBeCancelledByAnotherSend() async throws {
        let engine = RecoveryEngine()
        await engine.configure(events: [.started(messageId: "answer"), .textDelta(messageId: "answer", text: "first answer"), .runFinished])
        let state = AppState(engine: engine)
        await state.load()
        let first = try #require(state.selectedAgentID)
        state.send("first prompt")
        state.select("inbox")
        state.send("second prompt")
        try await until { !state.isTurnInFlight }
        #expect(await engine.sentTexts == ["first prompt"])
        #expect(!state.messages.contains { $0.text == "first answer" })
        // Make reloading fail so this verifies the local response's channel, not the stub's history.
        await engine.configure(history: true)
        state.select(first)
        #expect(state.messages.last?.text == "first answer")
    }

    @Test func repeatedSettingsFailuresAreScopedToTheSelectedAgent() async throws {
        let engine = RecoveryEngine()
        let state = AppState(engine: engine)
        await state.load()
        state.updateSelectedAgent(AgentPatch(name: "unsaved"))
        try await until { state.agentUpdateProblem != nil }
        state.updateSelectedAgent(AgentPatch(name: "still unsaved"))
        #expect(state.agentUpdateProblem == nil)
        try await until { state.agentUpdateProblem != nil }
        state.select("inbox")
        #expect(state.agentUpdateProblem == nil)
    }

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for state")
    }
}

private actor RecoveryEngine: EngineClient {
    init() {}

    let stub = StubEngineClient(tokenDelay: .zero)
    var failHistory = false
    var failChannel = false
    var failAgent = false
    var events: [TurnEvent] = []
    var sentTexts: [String] = []
    var delayedHistory = false
    var historyWait: CheckedContinuation<Void, Never>?
    var waitingForHistory: Bool { historyWait != nil }
    func delayNextHistory() { delayedHistory = true }
    func releaseHistory() { historyWait?.resume(); historyWait = nil }
    func configure(history: Bool = false, channel: Bool = false, agent: Bool = false, events: [TurnEvent] = []) {
        failHistory = history; failChannel = channel; failAgent = agent; self.events = events
    }
    func agents() async throws -> [Agent] { try await stub.agents() }
    func channels() async throws -> [Channel] { try await stub.channels() }
    func createAgent(_ draft: AgentDraft) async throws -> Agent {
        if failAgent { throw EngineError.notRunning }
        return try await stub.createAgent(draft)
    }
    func createChannel(agentIds: [Agent.ID]) async throws -> Channel {
        if failChannel { throw EngineError.notRunning }
        return try await stub.createChannel(agentIds: agentIds)
    }
    func messages(in channel: Channel.ID) async throws -> [Message] {
        if failHistory { throw EngineError.notRunning }
        let loaded = try await stub.messages(in: channel)
        if delayedHistory {
            delayedHistory = false
            await withCheckedContinuation { historyWait = $0 }
        }
        return loaded
    }
    func activity(for agent: Agent.ID) async throws -> [ActivityEntry] {
        throw EngineError.notRunning
    }
    func updateAgent(_ id: Agent.ID, _ patch: AgentPatch) async throws -> Agent {
        throw EngineError.notRunning
    }
    /// Throws like everything else here. An empty trail would read as "nothing has happened",
    /// which is the one thing an audit screen must never say when it simply cannot ask.
    func auditEvents(_ query: AuditQuery) async throws -> AuditPage {
        throw EngineError.notRunning
    }

    func availableModels() async throws -> [ModelSelection] { throw EngineError.notRunning }
    func setControl(_ control: ScreenControl, for agent: Agent.ID) async throws {
        throw EngineError.notRunning
    }

    nonisolated func send(_ text: String, to channel: Channel.ID) -> AsyncThrowingStream<TurnEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for event in await response(text) { continuation.yield(event) }
                continuation.finish()
            }
        }
    }
    func response(_ text: String) -> [TurnEvent] { sentTexts.append(text); return events }

    nonisolated func screen(for agent: Agent.ID, cadence: ScreenCadence) -> AsyncStream<ScreenFrame> {
        // Finishes rather than hangs, for the same reason the stub's stopped-cadence stream does:
        // a view awaiting frames that will never come must not be left suspended forever.
        AsyncStream { $0.finish() }
    }

    func pluginsPage() async throws -> PluginsPage { throw EngineError.notRunning }
    func grantedPlugins(for agent: Agent.ID) async throws -> GrantedPlugins {
        throw EngineError.notRunning
    }
    func grantPlugin(kind: PluginGrantKind, ref: String, to agent: Agent.ID) async throws {
        throw EngineError.notRunning
    }
    func revokePlugin(kind: PluginGrantKind, ref: String, from agent: Agent.ID) async throws {
        throw EngineError.notRunning
    }
    func addPluginServer(catalogueKey: String) async throws {
        throw EngineError.notRunning
    }

    func handoffGrants(for agent: Agent.ID) async throws -> HandoffGrants {
        throw EngineError.notRunning
    }

    func actionPolicy() async throws -> ActionPolicy { throw EngineError.notRunning }

    func saveActionPolicy(_ policy: ActionPolicy) async throws -> ActionPolicy {
        throw EngineError.notRunning
    }

    func routines() async throws -> [Routine] {
        // Throwing rather than answering with none: an empty list here would read as "you have no
        // routines", which is the opposite of "I could not ask".
        throw EngineError.notRunning
    }

    func setRoutineEnabled(_ id: String, enabled: Bool) async throws {
        throw EngineError.notRunning
    }

    func deleteRoutine(_ id: String) async throws {
        throw EngineError.notRunning
    }
}

private final class CredentialReads: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func next() -> EngineEnvironment.Intelligence {
        lock.withLock {
            value += 1
            return .init(apiURL: "https://example.invalid", gatewayWsURL: "wss://example.invalid", apiKey: "test-key-\(value)", licenseToken: "test-license")
        }
    }
}

/// What the composer says when a send has to wait.
@MainActor
@Suite
struct SendBlockedReasonTests {
    /**
     A composer that will not send must say why.

     One turn runs at a time across the app. That limit greyed out every conversation's field while
     any agent answered, with nothing on screen to explain it — switch to a second agent mid-reply
     and its composer was just dead. docs/09: disabled with a reason, inline, never a silent no-op.
     */
    @Test func thereIsAlwaysAReasonWhenSendingIsBlocked() async {
        let state = AppState(engine: StubEngineClient())
        await state.load()
        if !state.canSend {
            #expect(state.composerBlock != nil || state.sendBlockedReason != nil)
        }
    }

    @Test func noReasonWhenNothingIsBlocking() async throws {
        let state = AppState(engine: StubEngineClient())
        await state.load()
        guard let agent = state.agents.first else { return }
        state.select(agent.id)
        for _ in 0..<200 where !state.canSend {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard state.canSend else { return }
        #expect(state.sendBlockedReason == nil)
    }

    /// Without a conversation there is nothing to send into, and the field says so.
    @Test func noConversationIsAReason() {
        let state = AppState(engine: StubEngineClient())
        state.selectedAgentID = "orchestrator"
        #expect(state.needsConversation)
        #expect(state.sendBlockedReason != nil)
    }
}
