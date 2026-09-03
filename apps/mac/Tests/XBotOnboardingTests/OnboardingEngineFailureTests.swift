import Testing
import XBotEngine
@testable import XBotOnboarding
@testable import XBotRuntime

struct OnboardingEngineFailureTests {
    @Test func healthTimeoutFailsWithTimedOutError() async {
        let runtime = RuntimeController(
            driver: FakeDriver(),
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in nil },
            startHealthDeadlineSeconds: 2
        )
        await runtime.start(environment: { _, _ in [:] })
        guard case .failed(.healthTimedOut) = await runtime.state else {
            Issue.record("expected health timeout, got \(await runtime.state)")
            return
        }
    }

    @Test func existingContainerIsAdoptedBeforeRun() async {
        let driver = FakeDriver(
            script: FakeDriver.Script(runFails: true, existingContainerPort: 3_001)
        )
        let runtime = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") }
        )
        await runtime.start(environment: { _, _ in [:] })
        guard case .running(let endpoint) = await runtime.state else {
            Issue.record("expected running after adoption")
            return
        }
        #expect(endpoint.port == 3_001)
        #expect(await driver.startedSpecs.isEmpty)
    }

    @Test func runFailureSurfacesAsCommandFailed() async {
        let runtime = RuntimeController(
            driver: FakeDriver(script: FakeDriver.Script(runFails: true)),
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            startHealthDeadlineSeconds: 2
        )
        await runtime.start(environment: { _, _ in [:] })
        guard case .failed(.commandFailed) = await runtime.state else {
            Issue.record("expected command failed")
            return
        }
    }
}
