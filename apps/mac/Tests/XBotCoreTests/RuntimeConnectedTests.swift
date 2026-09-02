import Testing
import XBotEngine
import XBotRuntime

@testable import XBotCore

/// `AppState` driven by a real `RuntimeController` instead of a fixed `EngineClient` — the M5
/// wiring. `FakeDriver` stands in for Docker, the same way it does in `RuntimeControllerTests`, so
/// every state the container's state machine can reach is exercised without one.
@MainActor
struct RuntimeConnectedTests {
    private func controller(
        script: FakeDriver.Script = FakeDriver.Script(),
        healthy: Bool = true
    ) -> RuntimeController {
        RuntimeController(
            driver: FakeDriver(script: script),
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in healthy }
        )
    }

    private nonisolated func environment(_ port: UInt16, _ hostGateway: String) -> [String: String] {
        EngineEnvironment.compose(
            EngineEnvironment.Inputs(
                port: port,
                keyEncryptionKey: "k",
                hostGateway: hostGateway,
                appOrigin: "xbot://app"
            )
        )
    }

    private func state(
        script: FakeDriver.Script = FakeDriver.Script(),
        healthy: Bool = true
    ) -> (AppState, RuntimeController) {
        let runtime = controller(script: script, healthy: healthy)
        let state = AppState(
            runtime: runtime,
            environment: environment,
            engineFactory: { _ in StubEngineClient(tokenDelay: .zero) }
        )
        return (state, runtime)
    }

    @Test func aStoppedEngineBlocksTheComposer() async {
        let (state, _) = state()
        await state.load()

        #expect(state.composerBlock == .engineNotRunning)
    }

    @Test func noRuntimeFoundAtAllStillReadsAsUnavailable() async {
        // `.absent` and `.stopped` are different sentences: one needs an install (M6), the other
        // is a Start. Collapsing them into one button that cannot possibly work is a lie.
        let (state, _) = state(script: FakeDriver.Script(probe: .absent))
        await state.load()

        #expect(state.composerBlock == .runtimeUnavailable)
    }

    @Test func aFailedStartSaysSoRatherThanPretendingTheEngineIsMerelyOff() async throws {
        let (state, _) = state(script: FakeDriver.Script(runFails: true))
        await state.load()
        state.startEngine()

        try await until {
            if case .engineFailed = state.composerBlock { return true }
            return false
        }
        guard case .engineFailed(let reason) = state.composerBlock else { return }
        #expect(reason == String(localized: "The engine couldn't start"))
    }

    @Test func startingTheEngineEventuallyUnblocksTheComposer() async throws {
        let (state, _) = state()
        await state.load()

        state.startEngine()

        try await until { state.composerBlock == nil }
        #expect(!state.agents.isEmpty)
        #expect(state.status == nil)
    }

    @Test func aDegradedRuntimeKeepsTheConversationReadable() async throws {
        let (state, runtime) = state()
        await state.load()
        state.startEngine()
        try await until { state.composerBlock == nil }
        let agentsBeforeDegrading = state.agents

        await runtime.noteHealthLost(.healthLost)

        try await until { state.status == .reconnecting }
        // The pill changes; nothing else does. A health blip must not yank away what is already
        // loaded, per docs/09-ui-spec.md.
        #expect(state.composerBlock == nil)
        #expect(state.agents == agentsBeforeDegrading)
    }

    @Test func theBlockActionStartsTheEngineWhenThatIsWhyItIsBlocked() async throws {
        let (state, _) = state()
        await state.load()
        #expect(state.composerBlock == .engineNotRunning)

        state.handleComposerBlockAction()

        try await until { state.composerBlock == nil }
    }

    @Test func theBlockActionHandsTheBrowserBack() async throws {
        let (state, _) = state()
        await state.load()
        state.startEngine()
        try await until { state.composerBlock == nil }

        state.setControl(.human)
        #expect(state.control == .human)
        #expect(state.composerBlock == .humanHoldsControl)

        state.handleComposerBlockAction()
        #expect(state.control == .agent)
        #expect(state.composerBlock == nil)
    }

    @Test func aClientConstructedWithAFixedEngineNeverObservesARuntime() async {
        // The other initializer — `AppState(engine:)` — has no runtime to ask, so its
        // load() must take the original stub path rather than hang waiting for events nobody
        // will send.
        let state = AppState(engine: StubEngineClient(tokenDelay: .zero))
        await state.load()

        #expect(state.composerBlock == nil)
        state.startEngine()  // a no-op without a runtime; must not crash
        state.handleComposerBlockAction()  // ditto
    }

    @Test func creatingAnAgentSelectsIt() async throws {
        let state = AppState(engine: StubEngineClient(tokenDelay: .zero))
        await state.load()
        let before = state.agents.count

        state.createAgent(named: "Travel")
        try await until { state.agents.count == before + 1 }

        #expect(state.selectedAgent?.name == "Travel")
        #expect(state.channels.contains { $0.agentIds.contains(state.selectedAgentID ?? "") })
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
