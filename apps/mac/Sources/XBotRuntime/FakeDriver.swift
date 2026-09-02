import Foundation

/// A runtime that does nothing, convincingly.
///
/// Every failure the state machine has to handle is reachable from here by construction, because
/// the alternative is testing the unhappy paths by breaking a real Docker — which is slow, flaky,
/// and cannot produce "the daemon vanished mid-start" on demand.
public actor FakeDriver: ContainerDriver {
    public nonisolated let identifier: RuntimeIdentifier = .fake

    public struct Script: Sendable {
        public var probe: ProbeResult
        public var imagePresent: Bool
        public var pullSteps: Int
        public var runFails: Bool
        /// Health answers only after this many polls. Zero is immediate.
        public var healthAfterPolls: Int

        public init(
            probe: ProbeResult = .ready(version: "27.0.0"),
            imagePresent: Bool = true,
            pullSteps: Int = 4,
            runFails: Bool = false,
            healthAfterPolls: Int = 0
        ) {
            self.probe = probe
            self.imagePresent = imagePresent
            self.pullSteps = pullSteps
            self.runFails = runFails
            self.healthAfterPolls = healthAfterPolls
        }
    }

    private var script: Script
    private var volumes: Set<String> = []
    private(set) public var startedSpecs: [ContainerSpec] = []
    private(set) public var stopped = false
    private var healthPolls = 0

    public init(script: Script = Script()) {
        self.script = script
    }

    public func probe() async -> ProbeResult { script.probe }

    public func ensureDaemonRunning() async throws {
        if case .ready = script.probe { return }
        throw RuntimeError.daemonUnavailable
    }

    public func imageExists(_ reference: ImageReference) async -> Bool { script.imagePresent }

    public func pullImage(
        _ reference: ImageReference,
        progress: @Sendable @escaping (PullProgress) -> Void
    ) async throws {
        for step in 1...max(1, script.pullSteps) {
            progress(
                PullProgress(
                    layersComplete: step,
                    layersTotal: script.pullSteps,
                    fraction: Double(step) / Double(script.pullSteps)
                )
            )
        }
        script.imagePresent = true
    }

    public func createVolume(_ name: String) async throws { volumes.insert(name) }
    public func volumeExists(_ name: String) async -> Bool { volumes.contains(name) }

    public func run(_ spec: ContainerSpec) async throws -> ContainerHandle {
        if script.runFails {
            throw RuntimeError.commandFailed(
                command: "run", exitCode: 125, message: "port is already allocated"
            )
        }
        startedSpecs.append(spec)
        return ContainerHandle(id: "fake-\(spec.name)")
    }

    public func stop(_ handle: ContainerHandle, timeout: Duration) async throws { stopped = true }
    public func remove(_ handle: ContainerHandle) async throws {}

    public func inspect(_ handle: ContainerHandle) async throws -> ContainerStatus {
        stopped ? .exited(code: 0) : .running
    }

    public func logs(_ handle: ContainerHandle, tail: Int) async throws -> [LogLine] {
        [LogLine(text: "fake engine listening")]
    }

    public func hostGatewayAddress() async throws -> String { "host.docker.internal" }

    /// Drives the health poll the controller waits on.
    public func healthAnswers() -> Bool {
        healthPolls += 1
        return healthPolls > script.healthAfterPolls
    }
}
