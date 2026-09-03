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
        /// When set, a container with this name already exists and should be adopted.
        public var existingContainerPort: UInt16?
        /// Whether the existing container starts stopped and needs `docker start`.
        public var existingContainerStopped: Bool

        public init(
            probe: ProbeResult = .ready(version: "27.0.0"),
            imagePresent: Bool = true,
            pullSteps: Int = 4,
            runFails: Bool = false,
            healthAfterPolls: Int = 0,
            existingContainerPort: UInt16? = nil,
            existingContainerStopped: Bool = false
        ) {
            self.probe = probe
            self.imagePresent = imagePresent
            self.pullSteps = pullSteps
            self.runFails = runFails
            self.healthAfterPolls = healthAfterPolls
            self.existingContainerPort = existingContainerPort
            self.existingContainerStopped = existingContainerStopped
        }
    }

    private var script: Script
    private var volumes: Set<String> = []
    private(set) public var startedSpecs: [ContainerSpec] = []
    private(set) public var stopped = false
    private var healthPolls = 0
    private var existingRunning = false

    public init(script: Script = Script()) {
        self.script = script
        self.existingRunning = script.existingContainerPort != nil && !script.existingContainerStopped
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
    public func removeVolume(_ name: String) async throws { volumes.remove(name) }
    /// What survived an uninstall, for the test that says nothing did.
    public var remainingVolumes: Set<String> { volumes }

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
        if handle.id == RuntimeController.engineContainerName,
           script.existingContainerPort != nil
        {
            if existingRunning { return .running }
            return .exited(code: 0)
        }
        return stopped ? .exited(code: 0) : .running
    }

    public func logs(_ handle: ContainerHandle, tail: Int) async throws -> [LogLine] {
        [LogLine(text: "fake engine listening")]
    }

    public func hostGatewayAddress() async throws -> String { "host.docker.internal" }

    public func containerNamed(_ name: String) async -> ContainerHandle? {
        guard name == RuntimeController.engineContainerName,
              script.existingContainerPort != nil
        else { return nil }
        return ContainerHandle(id: name)
    }

    public func loopbackHostPort(for handle: ContainerHandle) async -> UInt16? {
        script.existingContainerPort
    }

    public func startContainer(_ handle: ContainerHandle) async throws {
        existingRunning = true
    }

    /// Drives the health poll the controller waits on.
    public func healthAnswers() -> Bool {
        healthPolls += 1
        return healthPolls > script.healthAfterPolls
    }
}
