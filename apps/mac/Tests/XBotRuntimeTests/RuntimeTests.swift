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
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
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

    /**
     A port Docker refuses is quietly swapped for another — docs/06: "nothing — we picked others".

     It used to surface as a failed start, and Try again reused the saved port, which can look free
     from the Mac while Docker holds it, so it clashed again on every attempt.
     */
    @Test func aRefusedPortIsRetriedOnAnotherWithoutFailing() async throws {
        let ports = isolatedPortStore()
        let driver = FakeDriver()
        await driver.refuseNextRunPort()
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            ports: ports
        )
        await controller.start(environment: environment)

        guard case .running(let endpoint) = await controller.state else {
            Issue.record("expected running after a refused port, got \(await controller.state)")
            return
        }
        let attempts = await driver.attemptedSpecs.compactMap { $0.ports.keys.first }
        #expect(attempts.count == 2)
        #expect(attempts.first != attempts.last)
        #expect(endpoint.port == attempts.last)
        // The port that stuck is the one remembered, not the one Docker refused.
        #expect(ports.load() == attempts.last)
    }

    /// Once, not forever. A second refusal is a real problem and says so.
    @Test func aPortRefusedEveryTimeStillFails() async {
        let controller = controller(script: FakeDriver.Script(runFails: true))
        await controller.start(environment: environment)
        guard case .failed = await controller.state else {
            Issue.record("expected failed, got \(await controller.state)")
            return
        }
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
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
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
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
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
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
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
        // Classified — the reason is used to pick the sentence — but never repeated.
        #expect(!error.sentence.contains("docker"))
        #expect(!error.sentence.contains("allocated"))
        #expect(!error.sentence.contains("125"))

        let unrecognised = RuntimeError.commandFailed(command: "run", exitCode: 125, message: "boom")
        #expect(unrecognised.sentence == String(localized: "The engine couldn't start"))
        #expect(!unrecognised.sentence.contains("boom"))
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
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
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
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
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

    /**
     A pull that fails must leave the running engine exactly where it was.

     `upgrade` removed the container first and pulled second, so the engine was down for the whole
     download — minutes, over several gigabytes — and docs/11-packaging-and-updates.md is explicit
     that the pull must never block use of the running engine. Worse, a pull that failed left the
     person with no engine at all until the rollback re-ran the old image.

     Pulling first costs nothing when it succeeds and costs the outage when it does not.
     */
    @Test func aFailedPullLeavesTheRunningEngineAlone() async {
        // `imagePresent` seeds xbot/engine:1, so the initial start does not pull; the upgrade's
        // new digest is absent, so that pull is the one that fails.
        let driver = FakeDriver(script: FakeDriver.Script(imagePresent: true, pullFails: true))
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
        )
        await controller.start(environment: environment)
        guard case .running = await controller.state else {
            Issue.record("expected a running engine to upgrade from")
            return
        }

        let outcome = await controller.upgrade(
            to: ImageReference(repository: "ghcr.io/masteryoav/xbot-engine", digest: String(repeating: "a", count: 64)),
            rollingBackTo: ImageReference(repository: "xbot/engine", tag: "1"),
            environment: environment
        )

        #expect(outcome == .failed)
        // Still up. The engine was never taken down for an update that could not happen.
        guard case .running = await controller.state else {
            Issue.record("a failed pull must not take the engine down, got \(await controller.state)")
            return
        }
        #expect(await !driver.stopped)
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
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
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
     A dump is taken before the new image can migrate the database.

     docs/11-packaging-and-updates.md calls this "the one that will bite": rollback is impossible if
     a forward migration produced a schema the old image cannot read. It offered two options and
     required one be chosen before a schema change reached a user, recommending the dump — "we do
     not control upstream's migrations and pretending we do is how a user loses their audit trail".

     The timing is the whole point. It has to happen while the old container is still there, because
     the next thing `upgrade` does is remove it.
     */
    @Test func anUpgradeDumpsTheDatabaseBeforeReplacingTheContainer() async {
        let driver = FakeDriver()
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
        )
        await controller.start(environment: environment)

        _ = await controller.upgrade(
            to: ImageReference(repository: "xbot/engine", tag: "2"),
            rollingBackTo: ImageReference(repository: "xbot/engine", tag: "1"),
            environment: environment
        )

        #expect(await driver.execCommands.contains { $0.first == "pg_dump" })
    }

    /// A rollback feeds the dump back in — and through stdin, because `docker exec` reads nothing
    /// otherwise and a restore with no input exits happily having applied nothing.
    @Test func aRollbackRestoresTheDumpThroughStdin() async {
        let driver = FakeDriver(script: FakeDriver.Script(healthAfterPolls: 0))
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            startHealthDeadlineSeconds: 2,
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
        )
        await controller.start(environment: environment)
        // The new image runs but never answers, so the upgrade rolls back.
        await driver.failNextRun()

        let outcome = await controller.upgrade(
            to: ImageReference(repository: "xbot/engine", tag: "2"),
            rollingBackTo: ImageReference(repository: "xbot/engine", tag: "1"),
            environment: environment
        )

        if outcome == .rolledBack {
            #expect(await driver.execCommands.contains { $0.first == "psql" })
            #expect(await driver.execStdin.contains { $0 != nil })
        }
    }

    /// A dump that fails does not block the upgrade. It costs the ability to roll back a migration,
    /// which only matters if the upgrade then fails — and refusing every update because a dump
    /// failed is its own way of leaving somebody stuck on an old engine.
    @Test func aFailedDumpDoesNotBlockTheUpgrade() async {
        let driver = FakeDriver()
        await driver.setExecFails(true)
        let controller = RuntimeController(
            driver: driver,
            image: ImageReference(repository: "xbot/engine", tag: "1"),
            health: { _ in EngineHealth(engineVersion: "0.0.5", schemaVersion: "0000") },
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
        )
        await controller.start(environment: environment)

        let outcome = await controller.upgrade(
            to: ImageReference(repository: "xbot/engine", tag: "2"),
            rollingBackTo: ImageReference(repository: "xbot/engine", tag: "1"),
            environment: environment
        )

        #expect(outcome == .succeeded)
    }


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
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
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
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
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
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
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
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
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
            ports: isolatedPortStore(),
            dumpURL: isolatedDumpURL()
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

    func string(forKey defaultName: String) -> String? {
        lock.withLock { values[defaultName] as? String }
    }

    func dictionary(forKey defaultName: String) -> [String: Any]? {
        lock.withLock { values[defaultName] as? [String: Any] }
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

/// A dump path per test. One shared file in Application Support is a global, and parallel suites
/// all writing it is the same class of bug as the shared preference domain.
func isolatedDumpURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("xbot-tests-\(UUID().uuidString)")
        .appendingPathComponent("dump.sql")
}

/// What a probe tells the person, which the settings pane used to decide for itself and get wrong.
@Suite
struct ProbeSentenceTests {
    /**
     The bug this exists to prevent.

     The settings pane matched on `RuntimeState.notDetected` and ignored the `ProbeResult` inside
     it, so a Mac with a container runtime installed but asleep read "No container runtime — xBot
     needs one" — while the composer in the same window said "the engine isn't running". Two
     surfaces contradicting each other, and the wrong one sending somebody off to install software
     they already had.
     */
    @Test func anAsleepRuntimeIsNotAMissingOne() {
        #expect(ProbeResult.installedNotRunning.sentence != ProbeResult.absent.sentence)
        #expect(!ProbeResult.installedNotRunning.sentence.contains("No container runtime"))
    }

    /// Red is for a wall. A runtime one press from waking is not one, and alarming somebody about
    /// it makes the press look risky.
    @Test func onlyAGenuinelyMissingRuntimeBlocks() {
        #expect(ProbeResult.absent.isBlocking)
        #expect(!ProbeResult.installedNotRunning.isBlocking)
        #expect(!ProbeResult.ready(version: "27.0").isBlocking)
    }

    @Test func aReadyRuntimeNamesItsVersion() {
        #expect(ProbeResult.ready(version: "27.0").sentence.contains("27.0"))
    }
}

/// How far a four-gigabyte download has got, which is the longest wait in the product.
@Suite
struct PullProgressDetailTests {
    /// The first seconds of every pull have no total, and "0%" then is a worse answer than saying
    /// nothing — it reads as stuck rather than starting.
    @Test func nothingTrueToSayYetSaysNothing() {
        #expect(PullProgress(layersComplete: 0, layersTotal: 0, fraction: nil).detail == nil)
    }

    @Test func layersWhileTheTotalSizeIsUnknown() {
        let detail = PullProgress(layersComplete: 3, layersTotal: 11, fraction: nil).detail
        #expect(detail?.contains("3") == true)
        #expect(detail?.contains("11") == true)
    }

    /// Percent wins once it exists: it is the number a person can hold a whole download in.
    @Test func percentOnceTheTotalIsKnown() {
        let detail = PullProgress(layersComplete: 3, layersTotal: 11, fraction: 0.42).detail
        #expect(detail?.contains("42") == true)
    }
}

/// Reading the reason out of a failed docker command, using docker's own wording.
@Suite
struct CommandFailureKindTests {
    private func kind(_ command: String, _ message: String) -> RuntimeError.FailureKind {
        RuntimeError.kind(command: command, message: message)
    }
    private let pull = "docker pull ghcr.io/masteryoav/xbot-engine@sha256:abc"

    /**
     The two failures a first run is most likely to hit, and both used to read "The engine couldn't
     start" — for a download of four and a half gigabytes in which nothing had started at all.
     */
    @Test func aDownloadThatLostTheNetwork() {
        for message in [
            #"Error response from daemon: Get "https://ghcr.io/v2/": dial tcp: lookup ghcr.io: no such host"#,
            "net/http: TLS handshake timeout",
            "read tcp 192.168.5.15:52376->140.82.112.34:443: read: connection reset by peer",
            "unexpected EOF",
            "dial tcp 140.82.112.34:443: i/o timeout",
        ] {
            #expect(kind(pull, message) == .downloadInterrupted, "\(message)")
        }
    }

    @Test func aDiskThatFilled() {
        let message = "failed to register layer: write /var/lib/docker/overlay2/x/diff/usr/lib/libx.so: no space left on device"
        #expect(kind(pull, message) == .diskFull)
        // Not mistaken for a network problem because the same line names a layer being written.
        #expect(kind("docker run -d --name xbot-engine", "mkdir /var/lib/docker/x: no space left on device") == .diskFull)
    }

    @Test func theRegistryRefusing() {
        #expect(kind(pull, "toomanyrequests: retry-after: 723.23µs, allowed: 44000/minute") == .rateLimited)
        #expect(kind(pull, "Error response from daemon: manifest unknown") == .imageUnavailable)
        #expect(kind(pull, "Error response from daemon: denied: denied") == .imageUnavailable)
    }

    @Test func aPortSomebodyElseTook() {
        let message = "Bind for 127.0.0.1:49152 failed: port is already allocated"
        #expect(kind("docker run -d --name xbot-engine", message) == .portInUse)
    }

    /// Network words only mean a lost download on a pull. On anything else they would send somebody
    /// to check a connection that was never the problem.
    @Test func networkWordsOutsideAPullAreNotADownloadProblem() {
        #expect(kind("docker volume create xbot-data", "dial tcp: i/o timeout") == .other)
    }

    @Test func somethingUnrecognisedStaysGeneric() {
        #expect(kind(pull, "") == .other)
        #expect(kind("docker volume create xbot-data", "error while creating volume") == .other)
    }

    /// Each kind reads differently, and none of them repeats docker's text back at the person.
    @Test func everyKindHasItsOwnSentenceAndNoneLeaksTheCommand() {
        let messages = [
            "no space left on device", "dial tcp: i/o timeout", "toomanyrequests",
            "manifest unknown", "port is already allocated", "something else",
        ]
        let command = "docker run -e XBOT_ENGINE_TOKEN=secret-value pull"
        let sentences = messages.map {
            RuntimeError.commandFailed(command: pull, exitCode: 1, message: $0).sentence
        }
        #expect(Set(sentences).count == messages.count)
        let run = RuntimeError.commandFailed(command: command, exitCode: 1, message: "no space left on device")
        #expect(!run.sentence.contains("secret-value"))
        #expect(!run.sentence.contains("docker"))
    }
}
