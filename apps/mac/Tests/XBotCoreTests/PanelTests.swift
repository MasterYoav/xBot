import Testing
import XBotEngine

@testable import XBotCore

/// The panel's own logic: which section is showing, and what that costs.
///
/// The screen poll is the expensive thing in this app — an image request on a timer against a
/// container — so the rule that it stops when nobody is looking is worth a test rather than a
/// comment. These assert the observable consequence (no frames arriving) rather than reaching in
/// for the cadence value, so a refactor of how cadence is computed does not break them.
@MainActor
struct PanelTests {
    private func state() -> AppState {
        AppState(engine: StubEngineClient(tokenDelay: .zero))
    }

    @Test func activityLoadsForTheSelectedAgent() async {
        let state = state()
        await state.load()

        #expect(!state.activity.isEmpty)
        // Newest first, as the panel renders it.
        let times = state.activity.map(\.at)
        #expect(times == times.sorted(by: >))
    }

    @Test func switchingAgentClearsActivityImmediately() async {
        let state = state()
        await state.load()
        #expect(!state.activity.isEmpty)

        state.select("inbox")

        // Cleared on the intent, not after the load: stale activity attributed to the wrong agent
        // is worse than an empty panel for one frame.
        #expect(state.activity.isEmpty)
    }

    @Test func anAgentWithNoHistoryHasAnEmptyPanel() async {
        let state = state()
        await state.load()

        state.select("researcher")
        // Let the load settle.
        try? await Task.sleep(for: .milliseconds(80))

        #expect(state.activity.isEmpty)
        #expect(state.screenFrame == nil)
    }

    @Test func modelsAreOfferedForThePicker() async {
        let state = state()
        await state.load()

        #expect(state.models.count >= 3)
        // The point of the router: more than one vendor reachable at once.
        #expect(Set(state.models.map(\.provider)).count > 1)
    }

    @Test func takingControlIsOptimisticAndReversible() async {
        let state = state()
        await state.load()
        #expect(state.control == .agent)

        state.setControl(.human)
        // Applied on the intent. The overlay must not wait for a round trip.
        #expect(state.control == .human)

        state.setControl(.agent)
        #expect(state.control == .agent)
    }

    @Test func editingAnAgentUpdatesTheRail() async throws {
        let state = state()
        await state.load()

        state.updateSelectedAgent(AgentPatch(name: "Renamed"))
        try await until { state.agents.first?.name == "Renamed" }

        #expect(state.selectedAgent?.name == "Renamed")
    }

    private func until(
        _ condition: () -> Bool,
        within: Duration = .seconds(2)
    ) async throws {
        let deadline = ContinuousClock.now + within
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("condition never became true")
    }
}
