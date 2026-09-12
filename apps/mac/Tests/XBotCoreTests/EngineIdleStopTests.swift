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

/// Opening the app, once onboarding is done.
@MainActor
@Suite(.serialized)
struct EngineLaunchTests {
    private nonisolated func environment(_ port: UInt16, _ hostGateway: String) -> [String: String] {
        EngineEnvironment.compose(
            EngineEnvironment.Inputs(port: port, keyEncryptionKey: "k", hostGateway: hostGateway, appOrigin: "xbot://app")
        )
    }

    private func app(startsOnLaunch: Bool) -> AppState {
        AppState(
            runtime: RuntimeController(
                driver: FakeDriver(script: FakeDriver.Script()),
                image: ImageReference(repository: "xbot/engine", tag: "1"),
                health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") }
            ),
            environment: environment,
            engineFactory: { _ in StubEngineClient(tokenDelay: .zero) },
            providers: isolatedConnectionStore(),
            conversationStore: { .ready },
            startsEngineOnLaunch: { startsOnLaunch }
        )
    }

    /**
     Launch brings the engine up, with no Start button on every open.

     It used to detect and stop, so every relaunch read "The engine isn't running" — false, when the
     container had been up the whole time, because only `start()` adopts one.
     */
    @Test func launchingAfterOnboardingStartsTheEngine() async throws {
        let state = app(startsOnLaunch: true)
        await state.load()
        for _ in 0..<300 {
            if case .running = state.runtimeState { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .running = state.runtimeState else {
            Issue.record("Expected the engine to be started on launch, got \(String(describing: state.runtimeState))")
            return
        }
        #expect(state.composerBlock == nil)
    }

    /// Before onboarding finishes, onboarding drives the start with its own progress screen.
    @Test func notBeforeOnboardingIsDone() async throws {
        let state = app(startsOnLaunch: false)
        await state.load()
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.composerBlock == .engineNotRunning)
    }
}

/// What quitting does to the engine.
@MainActor
@Suite(.serialized)
struct EngineQuitTests {
    private nonisolated func environment(_ port: UInt16, _ hostGateway: String) -> [String: String] {
        EngineEnvironment.compose(
            EngineEnvironment.Inputs(port: port, keyEncryptionKey: "k", hostGateway: hostGateway, appOrigin: "xbot://app")
        )
    }

    private func running(_ engine: any EngineClient) async throws -> AppState {
        let state = AppState(
            runtime: RuntimeController(
                driver: FakeDriver(script: FakeDriver.Script()),
                image: ImageReference(repository: "xbot/engine", tag: "1"),
                health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") }
            ),
            environment: environment,
            engineFactory: { _ in engine },
            providers: isolatedConnectionStore(),
            conversationStore: { .ready }
        )
        await state.load()
        state.startEngine()
        for _ in 0..<300 {
            if case .running = state.runtimeState { return state }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Engine never reached running")
        return state
    }

    private func isRunning(_ state: AppState) -> Bool {
        if case .running = state.runtimeState { return true }
        return false
    }

    /**
     Quitting stops an engine nothing else needs.

     Left running it outlived even a reboot — the container is `--restart unless-stopped` — holding a
     couple of gigabytes for an app nobody had open.
     */
    @Test func quittingStopsAnEngineNothingNeeds() async throws {
        let engine = StubEngineClient(tokenDelay: .zero)
        for routine in try await engine.routines() {
            try await engine.setRoutineEnabled(routine.id, enabled: false)
        }
        let state = try await running(engine)
        await state.prepareToQuit()
        // The controller has stopped; `AppState` hears about it through the runtime's event stream.
        for _ in 0..<300 where isRunning(state) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!isRunning(state))
    }

    /// A routine is the one thing that needs the engine with the app closed.
    @Test func aSwitchedOnRoutineKeepsItUpAfterQuit() async throws {
        let state = try await running(StubEngineClient(tokenDelay: .zero))
        await state.prepareToQuit()
        // Long enough for a stop to have reached `AppState` if one had been sent — otherwise this
        // would pass on a stop that simply had not been heard about yet.
        try await Task.sleep(for: .milliseconds(200))
        #expect(isRunning(state))
    }

    /// Could not ask is not "none". An engine that will not answer keeps running rather than risk a
    /// routine the person set up — and the quit is not held hostage waiting for it.
    @Test func anUnreadableRoutineListKeepsItUp() async throws {
        let state = try await running(UnavailableEngineClient())
        let started = ContinuousClock.now
        await state.prepareToQuit()
        #expect(ContinuousClock.now - started < .seconds(3))
        try await Task.sleep(for: .milliseconds(200))
        #expect(isRunning(state))
    }
}

/// The app noticing a crash on its own, through the health watch.
@MainActor
@Suite(.serialized)
struct EngineCrashNoticedTests {
    actor Pulse {
        var beating = true
        func stop() { beating = false }
    }

    private nonisolated func environment(_ port: UInt16, _ hostGateway: String) -> [String: String] {
        EngineEnvironment.compose(
            EngineEnvironment.Inputs(port: port, keyEncryptionKey: "k", hostGateway: hostGateway, appOrigin: "xbot://app")
        )
    }

    /**
     A container that dies mid-session shows up in the composer without anybody doing anything.

     Before the watch existed the app went on reporting Running indefinitely, and the first sign of
     trouble was a message failing against an engine it still believed in.
     */
    @Test func aCrashedEngineReachesTheComposerOnItsOwn() async throws {
        let driver = FakeDriver()
        let pulse = Pulse()
        let state = AppState(
            runtime: RuntimeController(
                driver: driver,
                image: ImageReference(repository: "xbot/engine", tag: "1"),
                health: { _ in
                    await pulse.beating ? EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") : nil
                }
            ),
            environment: environment,
            engineFactory: { _ in StubEngineClient(tokenDelay: .zero) },
            providers: isolatedConnectionStore(),
            conversationStore: { .ready }
        )
        state.healthCheckInterval = .milliseconds(20)
        await state.load()
        state.startEngine()
        for _ in 0..<300 where state.composerBlock != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(state.composerBlock == nil)

        await driver.killContainer()
        await pulse.stop()

        for _ in 0..<300 {
            if case .engineFailed = state.composerBlock { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(state.composerBlock == .engineFailed(reason: RuntimeError.engineStoppedUnexpectedly.sentence))
    }
}
