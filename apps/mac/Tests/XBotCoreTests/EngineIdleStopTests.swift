import Foundation
import Testing
import XBotEngine
import XBotRuntime
@testable import XBotCore

/// Stopping a quiet engine, and waking it by sending — docs/07, against a real `RuntimeController`.
@MainActor
@Suite(.serialized)
struct EngineIdleStopTests {
    private nonisolated func environment(_ port: UInt16, _ hostGateway: String) -> [String: String] {
        EngineEnvironment.compose(
            EngineEnvironment.Inputs(port: port, keyEncryptionKey: "k", hostGateway: hostGateway, appOrigin: "xbot://app")
        )
    }

    /// A running app whose engine is the given stub, so a test can switch its routines off.
    private func running(_ engine: StubEngineClient) async throws -> (AppState, RuntimeController) {
        let runtime = RuntimeController(
            driver: FakeDriver(script: FakeDriver.Script()),
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") }
        )
        let state = AppState(
            runtime: runtime,
            environment: environment,
            engineFactory: { _ in engine },
            providers: isolatedConnectionStore(),
            conversationStore: { .ready }
        )
        await state.load()
        state.startEngine()
        try await until { state.composerBlock == nil && state.agents.isEmpty == false }
        state.idleTimeout = 0
        return (state, runtime)
    }

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for state")
    }

    @Test func aQuietEngineWithNoRoutinesIsPaused() async throws {
        let engine = StubEngineClient(tokenDelay: .zero)
        for routine in try await engine.routines() {
            try await engine.setRoutineEnabled(routine.id, enabled: false)
        }
        let (state, _) = try await running(engine)

        await state.stopIfIdle(now: Date().addingTimeInterval(1))

        try await until { state.composerBlock == .enginePausedWhenIdle }
        #expect(state.pausedWhenIdle)
    }

    /**
     A routine keeps the engine up, however quiet the app has been.

     Routines run inside the engine; pausing it would silently cancel the one the person set up so
     they would not have to be at the Mac. The stub ships with a routine switched on, which is the
     case being checked.
     */
    @Test func aSwitchedOnRoutineKeepsItRunning() async throws {
        let (state, _) = try await running(StubEngineClient(tokenDelay: .zero))

        await state.stopIfIdle(now: Date().addingTimeInterval(1))

        #expect(state.composerBlock == nil)
        #expect(!state.pausedWhenIdle)
        if case .running = state.runtimeState {} else {
            Issue.record("Expected the engine to keep running, got \(String(describing: state.runtimeState))")
        }
    }

    /// Not paused by a person stopping it: that is `engineNotRunning`, and Start is the way back.
    @Test func aStopThePersonChoseIsNotReportedAsAPause() async throws {
        let (state, _) = try await running(StubEngineClient(tokenDelay: .zero))
        state.stopEngine()
        try await until { state.composerBlock == .engineNotRunning }
        #expect(!state.pausedWhenIdle)
    }

    /**
     Sending wakes it and the message is answered — docs/07's "starts on demand when the user sends a
     message". The person does not press Start for an engine they never stopped, and what they typed
     is not lost while it comes back.
     */
    @Test func sendingToAPausedEngineWakesItAndGetsAnAnswer() async throws {
        let engine = StubEngineClient(tokenDelay: .zero)
        for routine in try await engine.routines() {
            try await engine.setRoutineEnabled(routine.id, enabled: false)
        }
        let (state, _) = try await running(engine)
        if let agent = state.agents.first { state.select(agent.id) }
        try await until { state.canSend }

        await state.stopIfIdle(now: Date().addingTimeInterval(1))
        try await until { state.composerBlock == .enginePausedWhenIdle }
        state.idleTimeout = EngineIdlePolicy.defaultTimeout

        state.send("are you there?")

        // The bubble is up before the engine is.
        #expect(state.messages.contains { $0.text == "are you there?" })
        try await until {
            state.messages.contains { $0.text == "are you there?" && $0.state == .complete }
                && state.messages.contains { !$0.isFromUser && $0.state == .complete && !$0.text.isEmpty }
        }
        #expect(!state.pausedWhenIdle)
        #expect(state.composerBlock == nil)
    }
}
