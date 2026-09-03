import Darwin
import Foundation
import Testing
import XBotEngine

@testable import XBotRuntime

/// Binding is the only honest test of whether a port is free.
struct PortAllocatorTests {
    @Test func takesThePreferredPortWhenItIsFree() throws {
        // A high port nothing standard uses, so the test does not depend on the machine.
        let port = try PortAllocator.allocate(preferred: 49_312, range: 49_300...49_400)
        #expect(port == 49_312)
    }

    @Test func stepsPastAPortSomethingElseHolds() throws {
        // Hold one for real rather than mocking the check: the bug this guards against is the
        // engine connecting to somebody's Homebrew Postgres, and only a real bind reproduces it.
        let held = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(held) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(49_321).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(held, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try #require(bound == 0, "could not hold the port this test needs")
        listen(held, 1)

        #expect(!PortAllocator.isFree(49_321))
        let allocated = try PortAllocator.allocate(preferred: 49_321, range: 49_322...49_400)
        #expect(allocated != 49_321)
    }

    @Test func refusesRatherThanGuessingWhenNothingIsFree() {
        // An empty range has nothing to give. Returning a port anyway would produce a container
        // that fails to start with a message about the wrong thing.
        #expect(throws: RuntimeError.self) {
            _ = try PortAllocator.allocate(preferred: 1, range: 1...1)
        }
    }
}

struct EngineEnvironmentTests {
    private func inputs(
        intelligence: EngineEnvironment.Intelligence? = nil,
        allowPrivateHosts: Bool = false
    ) -> EngineEnvironment.Inputs {
        EngineEnvironment.Inputs(
            port: 49_152,
            keyEncryptionKey: "generated-per-install",
            hostGateway: "host.docker.internal",
            appOrigin: "xbot://app",
            intelligence: intelligence,
            allowPrivateHosts: allowPrivateHosts
        )
    }

    @Test func portAndServerPortAlwaysAgree() {
        // Upstream refuses to start if they disagree, and they are set in two places, so this is
        // exactly the kind of thing that drifts silently and costs an afternoon.
        let environment = EngineEnvironment.compose(inputs())
        #expect(environment["PORT"] == environment["SERVER_PORT"])
        #expect(environment["PORT"] == "49152")
    }

    @Test func browserLimitFollowsPhysicalMemory() {
        #expect(EngineEnvironment.browserLimit(forPhysicalMemory: 8 * 1_073_741_824) == 1)
        #expect(EngineEnvironment.browserLimit(forPhysicalMemory: 16 * 1_073_741_824) == 2)
        #expect(EngineEnvironment.browserLimit(forPhysicalMemory: 32 * 1_073_741_824) == 4)
    }

    @Test func memoryLimitScalesWithHostRAM() {
        let eightGB = EngineEnvironment.memoryLimitBytes(forPhysicalMemory: 8 * 1_073_741_824)
        let sixteenGB = EngineEnvironment.memoryLimitBytes(forPhysicalMemory: 16 * 1_073_741_824)
        #expect(eightGB < sixteenGB)
    }

    @Test func noIntelligenceMeansNoneOfTheFour() {
        let environment = EngineEnvironment.compose(inputs())

        // All four absent selects local history. A partial set is refused by the engine, which is
        // why this is all-or-nothing rather than field by field.
        #expect(environment["INTELLIGENCE_API_URL"] == nil)
        #expect(environment["INTELLIGENCE_GATEWAY_WS_URL"] == nil)
        #expect(environment["INTELLIGENCE_API_KEY"] == nil)
        #expect(environment["COPILOTKIT_LICENSE_TOKEN"] == nil)
    }

    @Test func intelligenceMeansAllFour() {
        let environment = EngineEnvironment.compose(
            inputs(
                intelligence: EngineEnvironment.Intelligence(
                    apiURL: "https://api.example",
                    gatewayWsURL: "wss://realtime.example",
                    apiKey: "key",
                    licenseToken: "token"
                )
            )
        )
        let four = [
            "INTELLIGENCE_API_URL", "INTELLIGENCE_GATEWAY_WS_URL",
            "INTELLIGENCE_API_KEY", "COPILOTKIT_LICENSE_TOKEN",
        ]
        #expect(four.allSatisfy { environment[$0] != nil })
    }

    @Test func privateHostsAreOffUnlessAskedFor() {
        // This removes the whole private-address floor, including reachability of cloud metadata
        // endpoints. A default that drifted to on would be a security regression that no test
        // elsewhere would notice.
        #expect(EngineEnvironment.compose(inputs())["AGENT_COMPUTER_ALLOW_PRIVATE_HOSTS"] == nil)
        #expect(
            EngineEnvironment.compose(inputs(allowPrivateHosts: true))[
                "AGENT_COMPUTER_ALLOW_PRIVATE_HOSTS"
            ] == "true"
        )
    }

    @Test func auditRetentionKeepsEverythingByDefault() {
        // Deleting somebody's audit trail because a default said so is the worse of the two
        // failures, so unset means keep.
        #expect(EngineEnvironment.compose(inputs())["AUDIT_RETENTION_DAYS"] == nil)
    }

    @Test func engineTokenIsPassedThroughWhenPresent() {
        var draft = inputs()
        draft.engineToken = "test-token"
        #expect(EngineEnvironment.compose(draft)["XBOT_ENGINE_TOKEN"] == "test-token")
    }

    @Test func toolURLIncludesTheAgentToolsPath() {
        let env = EngineEnvironment.compose(
            EngineEnvironment.Inputs(
                port: 3001,
                keyEncryptionKey: "k",
                hostGateway: "host.docker.internal",
                appOrigin: "xbot://app"
            )
        )
        #expect(env["OPENBOT_TOOL_URL"] == "http://host.docker.internal:3001/api/agent-tools/call")
    }

    @Test func embeddedPostgresDoesNotSetDatabaseURL() {
        // The container generates the URL with a random password on first boot.
        #expect(EngineEnvironment.compose(inputs())["DATABASE_URL"] == nil)
    }

    @Test(arguments: [
        (UInt64(8) * 1_073_741_824, 1),
        (UInt64(16) * 1_073_741_824, 2),
        (UInt64(64) * 1_073_741_824, 4),
    ])
    func browserLimitFollowsTheMachine(memory: UInt64, expected: Int) {
        #expect(EngineEnvironment.browserLimit(forPhysicalMemory: memory) == expected)
    }

    @Test func enginePortSurvivesRelaunch() {
        let ports = isolatedPortStore()
        ports.save(49_180)
        #expect(ports.load() == 49_180)
    }
}

/// The state machine, driven against a fake so every failure is reachable on demand.
@Suite(.serialized)
struct RuntimeControllerTests {
    private func controller(
        script: FakeDriver.Script = FakeDriver.Script(),
        healthy: Bool = true
    ) -> RuntimeController {
        RuntimeController(
            driver: FakeDriver(script: script),
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in
                healthy ? EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") : nil
            },
            ports: isolatedPortStore()
        )
    }

    private func environment(_ port: UInt16, _ gateway: String) -> [String: String] {
        EngineEnvironment.compose(
            EngineEnvironment.Inputs(
                port: port,
                keyEncryptionKey: "k",
                hostGateway: gateway,
                appOrigin: "xbot://app"
            )
        )
    }

    @Test func aHealthyStartEndsRunning() async {
        let controller = controller()
        await controller.start(environment: environment)

        guard case .running(let endpoint) = await controller.state else {
            Issue.record("expected running, got \(await controller.state)")
            return
        }
        #expect(endpoint.host == "127.0.0.1")
    }

    @Test func aSavedPortIsPreferredOnTheNextStart() async throws {
        let ports = isolatedPortStore()
        let preferred = try PortAllocator.allocate(preferred: 49_200, range: 49_200...49_200)
        ports.save(preferred)

        let driver = FakeDriver()
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            // The same store the port was saved to. Without this the controller reads the live
            // domain and the test asserts against a port it never wrote.
            ports: ports
        )
        await controller.start(environment: environment)

        let spec = await driver.startedSpecs.first
        #expect(spec?.ports.keys.first == preferred)
    }

    @Test func aMissingImageIsPulledFirst() async {
        let controller = controller(script: FakeDriver.Script(imagePresent: false))
        await controller.start(environment: environment)

        // It got past pulling, which is the assertion: a start that skipped the pull would fail
        // at run, and one that never left pulling would hang.
        guard case .running = await controller.state else {
            Issue.record("expected running after a pull, got \(await controller.state)")
            return
        }
    }

    @Test func aContainerThatWillNotRunFails() async {
        let controller = controller(script: FakeDriver.Script(runFails: true))
        await controller.start(environment: environment)

        guard case .failed = await controller.state else {
            Issue.record("expected failed, got \(await controller.state)")
            return
        }
    }

    @Test func healthTimeoutFailsWithTimedOutError() async {
        let controller = RuntimeController(
            driver: FakeDriver(),
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in nil },
            startHealthDeadlineSeconds: 2,
            ports: isolatedPortStore()
        )
        await controller.start(environment: environment)

        guard case .failed(.healthTimedOut(seconds: 2)) = await controller.state else {
            Issue.record("expected health timeout, got \(await controller.state)")
            return
        }
    }

    @Test func anExistingHealthyContainerIsAdopted() async {
        let driver = FakeDriver(
            script: FakeDriver.Script(runFails: true, existingContainerPort: 3_001)
        )
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            ports: isolatedPortStore()
        )
        await controller.start(environment: environment)

        let state = await controller.state
        guard case .running(let endpoint) = state else {
            Issue.record("expected running, got \(state)")
            return
        }
        #expect(endpoint.port == 3_001)
        #expect(await driver.startedSpecs.isEmpty)
    }

    @Test func aStoppedExistingContainerIsStartedThenAdopted() async {
        let driver = FakeDriver(
            script: FakeDriver.Script(
                runFails: true,
                existingContainerPort: 3_001,
                existingContainerStopped: true
            )
        )
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            ports: isolatedPortStore()
        )
        await controller.start(environment: environment)

        let state = await controller.state
        guard case .running(let endpoint) = state else {
            Issue.record("expected running, got \(state)")
            return
        }
        #expect(endpoint.port == 3_001)
        #expect(await driver.startedSpecs.isEmpty)
    }

    @Test func aFailedStartNeverEchoesTheCommand() {
        // The composer shows this sentence. A raw `docker run` line, or stderr, is diagnostics
        // material and must not become the thing a person reads.
        let error = RuntimeError.commandFailed(
            command: "run", exitCode: 125, message: "port is already allocated"
        )
        #expect(error.sentence == String(localized: "The engine couldn't start"))
        #expect(!error.sentence.contains("run"))
        #expect(!error.sentence.contains("allocated"))
    }

    @Test func healthLostBecomesDegradedAndRecovers() async {
        let controller = controller()
        await controller.start(environment: environment)

        await controller.noteHealthLost(.healthLost)
        guard case .degraded(let reason) = await controller.state else {
            Issue.record("expected degraded, got \(await controller.state)")
            return
        }
        #expect(reason == .healthLost)

        // Recovery is automatic and needs no click.
        await controller.noteHealthRecovered()
        guard case .running = await controller.state else {
            Issue.record("expected running again, got \(await controller.state)")
            return
        }
    }

    @Test func degradedIsIgnoredWhenNotRunning() async {
        // A health blip that arrives while the engine is stopped must not invent a degraded
        // running state out of nothing.
        let controller = controller()
        await controller.noteHealthLost(.healthLost)
        #expect(await controller.state == .stopped)
    }

    @Test func theContainerPublishesOnLoopbackWithThreeVolumes() async throws {
        let driver = FakeDriver()
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            ports: isolatedPortStore()
        )
        await controller.start(environment: environment)

        let spec = try #require(await driver.startedSpecs.first)
        // The browser in this container holds real logins. Three volumes, and the data volume
        // among them, because losing it is losing the audit trail.
        #expect(spec.volumes.count == 3)
        #expect(spec.volumes[RuntimeController.dataVolume] != nil)
        #expect(spec.ports.count == 1)
        #expect(spec.environment["OPENBOT_SINGLE_USER"] == "true")
    }

    @Test func stoppingReturnsToStopped() async {
        let controller = controller()
        await controller.start(environment: environment)
        await controller.stop()
        #expect(await controller.state == .stopped)
    }

    @Test func upgradePullsNewImageAndRecreatesContainer() async {
        let driver = FakeDriver()
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            ports: isolatedPortStore()
        )
        await controller.start(environment: environment)
        #expect(await controller.currentImageReference.full == "xbot/engine:1")
        #expect(await driver.startedSpecs.count == 1)

        let next = ImageReference(
            repository: "ghcr.io/masteryoav/xbot-engine",
            digest: "sha256:abc123def456"
        )
        let previous = ImageReference(repository: "xbot/engine", tag: "1")
        let outcome = await controller.upgrade(
            to: next,
            rollingBackTo: previous,
            environment: environment
        )

        guard case .running = await controller.state else {
            Issue.record("expected running after upgrade, got \(await controller.state)")
            return
        }
        #expect(outcome == .succeeded)
        #expect(await controller.currentImageReference == next)
        #expect(await driver.startedSpecs.count == 2)
        #expect(await driver.startedSpecs.last?.image == next)
        #expect(!(await driver.removedHandles.isEmpty))
    }

    @Test func upgradeRollsBackWhenNewImageFailsHealth() async {
        final class HealthScript: @unchecked Sendable {
            private let lock = NSLock()
            var failNextLaunch = false

            func answer() -> EngineHealth? {
                lock.lock()
                defer { lock.unlock() }
                if failNextLaunch {
                    failNextLaunch = false
                    return nil
                }
                return EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000")
            }
        }

        let healthScript = HealthScript()
        let driver = FakeDriver()
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in healthScript.answer() },
            startHealthDeadlineSeconds: 1,
            ports: isolatedPortStore()
        )
        await controller.start(environment: environment)

        let next = ImageReference(
            repository: "ghcr.io/masteryoav/xbot-engine",
            digest: "sha256:deadbeef"
        )
        let previous = ImageReference(repository: "xbot/engine", tag: "1")
        healthScript.failNextLaunch = true
        let outcome = await controller.upgrade(
            to: next,
            rollingBackTo: previous,
            environment: environment
        )

        guard case .running = await controller.state else {
            Issue.record("expected running after rollback, got \(await controller.state)")
            return
        }
        #expect(outcome == .rolledBack)
        #expect(await controller.currentImageReference == previous)
    }
}

extension RuntimeControllerTests {
    /**
     An installed-but-stopped runtime is woken, not reported and abandoned.

     `start()` used to probe once and return `.notDetected` for anything that was not ready. So a
     person with Docker installed but not running pressed the one button the app offered, nothing
     happened, and they were left on the same screen with the same button — the dead end invariant 7
     exists to prevent. Nothing in the codebase called `ensureDaemonRunning` at all.
     */
    @Test func aStoppedDaemonIsStartedRatherThanReportedAsMissing() async {
        let driver = FakeDriver(script: FakeDriver.Script(probe: .installedNotRunning))
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            ports: isolatedPortStore()
        )

        await controller.start(environment: environment)

        #expect(await driver.daemonStartRequested)
        guard case .running = await controller.state else {
            Issue.record("expected the engine to come up, got \(await controller.state)")
            return
        }
    }

    /// A runtime that will not come up still reports honestly, and does not pretend to be absent:
    /// "install Docker" is the wrong sentence for somebody who already has it.
    ///
    /// This supersedes `aDeadDaemonIsNotDetectedRatherThanFailed`, which asserted that an
    /// installed-but-stopped daemon *stays* not-detected — the bug itself, written down as an
    /// expectation. Its actual point survives here: installed-but-stopped is recoverable and must
    /// never present as `.failed`, because the sentence and the button are different.
    @Test func aDaemonThatWillNotStartIsStillInstalled() async {
        let driver = FakeDriver(
            script: FakeDriver.Script(probe: .installedNotRunning, daemonStartSucceeds: false)
        )
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            ports: isolatedPortStore()
        )

        await controller.start(environment: environment)

        #expect(await driver.daemonStartRequested)
        #expect(await controller.state == .notDetected(.installedNotRunning))
    }

    /// Nothing installed is a different case, and must not sit waiting for a daemon that cannot
    /// exist — the honest answer is immediate.
    @Test func anAbsentRuntimeIsNotWaitedFor() async {
        let driver = FakeDriver(script: FakeDriver.Script(probe: .absent))
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            ports: isolatedPortStore()
        )

        await controller.start(environment: environment)

        #expect(!(await driver.daemonStartRequested))
        #expect(await controller.state == .notDetected(.absent))
    }


    /**
     Uninstall removes the container and all three volumes.

     docs/11-packaging-and-updates.md: an app that manages containers and leaves gigabytes of
     volumes behind after being dragged to the Trash is a bad citizen with a reputation problem.
     The volumes are the whole point — the conversations, the agents, and the browser logins their
     computers hold live in them, and nothing else on the machine names them.
     */
    @Test func uninstallRemovesTheContainerAndEveryVolume() async {
        let driver = FakeDriver()
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            ports: isolatedPortStore()
        )
        await controller.start(environment: environment)
        #expect(!(await driver.remainingVolumes.isEmpty))

        await controller.uninstall()

        #expect(await driver.remainingVolumes.isEmpty)
        // Stopped, not notDetected: the runtime is still installed and still works. Only xBot's
        // own data is gone, and saying otherwise would send somebody to reinstall Docker.
        #expect(await controller.state == .stopped)
    }

    /// Uninstall runs once and cannot ask the person to try again, so a step whose work is already
    /// done must not stop the rest. Without this, a half-uninstalled machine keeps its volumes.
    @Test func uninstallSurvivesAnythingAlreadyGone() async {
        let driver = FakeDriver()
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            ports: isolatedPortStore()
        )

        // Never started: no container, no volumes, nothing to remove.
        await controller.uninstall()

        #expect(await driver.remainingVolumes.isEmpty)
        #expect(await controller.state == .stopped)
    }
}

/// Defaults that live and die with the test, so no two share the one live domain.
///
/// Three tests wrote `dev.xbot.enginePort` and Swift Testing runs their suites in parallel: a port
/// saved by one landed in the middle of another's read, and the assertion failed with a port it had
/// never written.
final class MemoryDefaults: KeyValueDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    func stringArray(forKey defaultName: String) -> [String]? {
        lock.withLock { values[defaultName] as? [String] }
    }

    func bool(forKey defaultName: String) -> Bool {
        lock.withLock { values[defaultName] as? Bool ?? false }
    }

    func integer(forKey defaultName: String) -> Int {
        lock.withLock { values[defaultName] as? Int ?? 0 }
    }

    func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { values[defaultName] = value }
    }

    func removeObject(forKey defaultName: String) {
        lock.withLock { values[defaultName] = nil }
    }
}

func isolatedPortStore() -> EnginePortStore {
    EnginePortStore(defaults: MemoryDefaults())
}
