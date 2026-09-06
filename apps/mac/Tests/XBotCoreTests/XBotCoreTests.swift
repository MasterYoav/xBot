import Testing
import XBotEngine

@testable import XBotCore

/// The send path, which is the only place in `XBotCore` with logic worth breaking.
///
/// Optimistic sending means the bubble exists before the request does, and the one thing that must
/// never happen is losing what somebody typed — so each of these checks the text survives.
@MainActor
struct SendTests {
    private func state() -> AppState {
        AppState(engine: StubEngineClient(tokenDelay: .zero))
    }

    @Test func loadSelectsTheFirstAgent() async {
        let state = state()
        await state.load()

        #expect(state.agents.count == 3)
        #expect(state.selectedAgentID == "orchestrator")
        #expect(state.status == nil)
    }

    @Test func sendingShowsTheMessageBeforeTheReplyArrives() async {
        let state = state()
        await state.load()
        let before = state.messages.count

        state.send("Check the flight")

        // Synchronous with the intent, not after an await: this is the whole point of optimistic
        // send, and a version that appended in the task would still pass a test that awaited first.
        #expect(state.messages.count == before + 1)
        #expect(state.messages.last?.text == "Check the flight")
        #expect(state.messages.last?.state == .sending)
    }

    @Test func aStreamedReplyAccumulatesAndCompletes() async throws {
        let state = state()
        await state.load()

        state.send("Say something")
        try await settle(state)

        let reply = try #require(state.messages.last)
        #expect(!reply.isFromUser)
        #expect(reply.state == .complete)
        #expect(reply.text.contains("stub engine"))
        #expect(reply.toolCalls.isEmpty)
    }

    @Test func aToolCallIsARowNotText() async throws {
        let state = state()
        await state.load()

        state.send("browse the flights")
        try await settle(state)

        let reply = try #require(state.messages.last)
        #expect(reply.toolCalls.contains { $0.name == "browser.navigate" && $0.target == "flights" })
        #expect(!reply.text.contains("browser.navigate"))
    }

    /**
     A tool call reaches the Activity panel, not only the message bubble.

     `recordTool` appended to the message's own tool-call rows and nowhere else, and the HTTP client
     returns an empty list from `activity(for:)` — deliberately, because the panel is described as
     held for the open conversation rather than fetched. So on a live engine the panel always read
     "Nothing yet. Commands, files, and pages will show up here", promising content that nothing
     could ever deliver. An empty state that cannot stop being empty is the dishonest kind.
     */
    @Test func aToolCallAlsoLandsInActivity() async throws {
        let state = state()
        await state.load()

        state.send("browse the flights")
        try await settle(state)

        #expect(state.activity.contains { $0.summary.contains("browser.navigate") })
    }

    /// Newest first, which is the order the panel renders and the order a person reads.
    @Test func activityIsNewestFirst() async throws {
        let state = state()
        await state.load()

        state.send("browse the flights")
        try await settle(state)

        let times = state.activity.map(\.at)
        #expect(times == times.sorted(by: >))
    }

    @Test func aFailedTurnKeepsTheTextAndIsMarkedFailed() async throws {
        let state = state()
        await state.load()

        state.send("fail this one")
        try await settle(state)

        // The typed text is still there. A failure that eats the message is worse than no send.
        #expect(state.messages.contains { $0.text == "fail this one" })
        let failed = state.messages.contains {
            if case .failed = $0.state { return true }
            return false
        }
        #expect(failed)
    }

    @Test func blankInputSendsNothing() async {
        let state = state()
        await state.load()
        let before = state.messages.count

        state.send("   \n ")

        #expect(state.messages.count == before)
    }

    @Test func switchingAgentClearsTheConversation() async {
        let state = state()
        await state.load()
        #expect(!state.messages.isEmpty)

        state.select("inbox")

        // Cleared on the intent. The rail must not wait for a load to show the new selection.
        #expect(state.selectedAgentID == "inbox")
        #expect(state.messages.isEmpty)
    }

    /// Wait for the turn to stop changing the conversation.
    ///
    /// Polling rather than a fixed sleep: the stream is driven by a detached task, and a sleep long
    /// enough to be reliable on a loaded machine makes every run of this file slow for no reason.
    private func settle(_ state: AppState, within: Duration = .seconds(5)) async throws {
        let deadline = ContinuousClock.now + within
        var lastSeen = ""
        while ContinuousClock.now < deadline {
            let now = (state.messages.last?.text ?? "") + String(describing: state.messages.last?.state)
            if now == lastSeen, !now.isEmpty, !now.contains("streaming") { return }
            lastSeen = now
            try await Task.sleep(for: .milliseconds(30))
        }
    }
}
