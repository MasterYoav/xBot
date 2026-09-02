import Darwin
import Foundation
import Testing

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
}

/// The state machine, driven against a fake so every failure is reachable on demand.
struct RuntimeControllerTests {
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

    @Test func aDeadDaemonIsNotDetectedRatherThanFailed() async {
        let controller = controller(script: FakeDriver.Script(probe: .installedNotRunning))
        await controller.start(environment: environment)

        // Installed-but-stopped is recoverable without the user installing anything, so it must
        // not present as a failure — the sentence and the button are different.
        guard case .notDetected(let probe) = await controller.state else {
            Issue.record("expected notDetected, got \(await controller.state)")
            return
        }
        #expect(probe == .installedNotRunning)
    }

    @Test func aContainerThatWillNotRunFails() async {
        let controller = controller(script: FakeDriver.Script(runFails: true))
        await controller.start(environment: environment)

        guard case .failed = await controller.state else {
            Issue.record("expected failed, got \(await controller.state)")
            return
        }
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
            health: { _ in true }
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
}
