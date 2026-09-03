import Testing
import XBotCore
import XBotEngine

@Suite @MainActor struct HandoffStateTests {
    @Test func togglingHandoffUpdatesReachable() async {
        let state = AppState(engine: StubEngineClient())
        await state.load()
        state.select("orchestrator")
        await state.refreshHandoffGrants()

        #expect(state.handoffGrants?.reachable.contains("inbox") == true)

        await state.setHandoffGrant(to: "researcher", enabled: true)
        #expect(state.handoffGrants?.reachable.contains("researcher") == true)

        await state.setHandoffGrant(to: "inbox", enabled: false)
        #expect(state.handoffGrants?.reachable.contains("inbox") == false)
    }
}
