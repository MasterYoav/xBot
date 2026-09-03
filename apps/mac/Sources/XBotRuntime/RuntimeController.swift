import Foundation
import XBotEngine

/// Owns the container lifecycle, and the state machine the UI renders.
///
/// An actor because it serialises access to one resource — the runtime — and two concurrent starts
/// would race to bind the same port and leave one orphaned container behind.
public actor RuntimeController {
    public private(set) var state: RuntimeState = .stopped {
        didSet {
            guard state != oldValue else { return }
            history.append("\(Date().formatted(.iso8601)) \(label(for: state))")
            if history.count > Self.historyLimit { history.removeFirst() }
            continuations.values.forEach { $0.yield(.stateChanged(state)) }
        }
    }

    private let driver: any ContainerDriver
    private let image: ImageReference
    private let health: @Sendable (EngineEndpoint) async -> EngineHealth?
    private let startHealthDeadlineSeconds: Int

    private var handle: ContainerHandle?
    private var allocatedPort: UInt16?
    private var lastHealth: EngineHealth?
    private var history: [String] = []
    private var continuations: [UUID: AsyncStream<RuntimeEvent>.Continuation] = [:]

    private static let historyLimit = 60

    public static let dataVolume = "xbot-data"
    public static let workspaceVolume = "xbot-workspace"
    public static let profilesVolume = "xbot-profiles"
    public static let engineContainerName = "xbot-engine"

    public init(
        driver: any ContainerDriver,
        image: ImageReference,
        health: @escaping @Sendable (EngineEndpoint) async -> EngineHealth?,
        startHealthDeadlineSeconds: Int = 120,
        /// Injected so a test gets its own storage rather than the one live preference domain.
        ports: EnginePortStore = .shared
    ) {
        self.driver = driver
        self.image = image
        self.health = health
        self.startHealthDeadlineSeconds = startHealthDeadlineSeconds
        self.ports = ports
        self.allocatedPort = ports.load()
    }

    private let ports: EnginePortStore

    public var events: AsyncStream<RuntimeEvent> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(.stateChanged(state))
            continuation.onTermination = { [weak self] _ in
                Task { await self?.forget(id) }
            }
        }
    }

    private func forget(_ id: UUID) { continuations[id] = nil }

    public func detect() async -> ProbeResult {
        let result = await driver.probe()
        if case .ready = result {
            if case .notDetected = state { state = .stopped }
        } else {
            state = .notDetected(result)
        }
        return result
    }

    /// Bring the engine up, reporting every step by name.
    ///
    /// Sequential and explicit rather than one opaque await, because "starting" with no substate is
    /// the thing that makes an app feel hung. Each stage here is a sentence the user can read.
    public func start(environment: (UInt16, String) -> [String: String]) async {
        guard case .ready = await driver.probe() else {
            state = .notDetected(await driver.probe())
            return
        }

        do {
            if await !driver.imageExists(image) {
                state = .pulling(PullProgress(layersComplete: 0, layersTotal: 0, fraction: nil))
                try await driver.pullImage(image) { progress in
                    Task { await self.report(progress) }
                }
            }

            state = .starting(.volumes)
            for volume in [Self.dataVolume, Self.workspaceVolume, Self.profilesVolume]
            where await !driver.volumeExists(volume) {
                try await driver.createVolume(volume)
            }

            if await adoptExistingEngineIfHealthy() {
                return
            }

            state = .starting(.ports)
            // Persisted across launches: a port that moves breaks bookmarks, the CLI, and the
            // admin webview, so the previous choice is preferred over a fresh scan.
            let port = try PortAllocator.allocate(
                preferred: allocatedPort ?? 3001,
                range: 49_152...49_400
            )
            allocatedPort = port
            ports.save(port)
            let endpoint = EngineEndpoint(port: port)

            state = .starting(.container)
            let gateway = try await driver.hostGatewayAddress()
            let spec = ContainerSpec(
                name: Self.engineContainerName,
                image: image,
                ports: [port: port],
                volumes: [
                    Self.dataVolume: "/var/lib/postgresql/data",
                    Self.workspaceVolume: "/workspace",
                    Self.profilesVolume: "/profiles",
                ],
                environment: environment(port, gateway),
                memoryLimitBytes: EngineEnvironment.memoryLimitBytes(
                    forPhysicalMemory: ProcessInfo.processInfo.physicalMemory
                )
            )
            handle = try await driver.run(spec)

            // Migrations run inside the container on start, so the first health answer is also the
            // signal that they finished. That is why the first-run timeout is four times the rest.
            state = .starting(.migrations)
            state = .starting(.health)
            let deadline = startHealthDeadlineSeconds
            guard await waitForHealth(endpoint, seconds: deadline) else {
                state = .failed(.healthTimedOut(seconds: deadline))
                return
            }

            state = .running(endpoint)
        } catch let error as RuntimeError {
            state = .failed(error)
        } catch {
            state = .failed(.commandFailed(command: "start", exitCode: -1, message: "\(error)"))
        }
    }

    private func report(_ progress: PullProgress) {
        guard case .pulling = state else { return }
        state = .pulling(progress)
    }

    /// Poll until the engine answers as xBot, or give up.
    ///
    /// Answering at all is not enough — another process on the port would also answer, and
    /// accepting any 200 is how the app ends up talking to somebody's unrelated dev server. The
    /// health closure is responsible for checking the body identifies this engine.
    private func waitForHealth(_ endpoint: EngineEndpoint, seconds: Int) async -> Bool {
        for _ in 0..<seconds {
            if let health = await health(endpoint) {
                lastHealth = health
                return true
            }
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }

    /// Reconnect to an engine container left over from a previous app launch or dev session.
    ///
    /// Without this, `docker run --name xbot-engine` fails when the container already exists —
    /// which is the common case during onboarding retries and local development.
    private func adoptExistingEngineIfHealthy() async -> Bool {
        guard let existing = await driver.containerNamed(Self.engineContainerName) else {
            return false
        }

        var status = (try? await driver.inspect(existing)) ?? .notFound
        if case .exited = status {
            do {
                try await driver.startContainer(existing)
                status = (try? await driver.inspect(existing)) ?? .notFound
            } catch {
                try? await driver.remove(existing)
                return false
            }
        }

        guard case .running = status else {
            try? await driver.remove(existing)
            return false
        }

        guard let port = await driver.loopbackHostPort(for: existing) else {
            return false
        }

        allocatedPort = port
        ports.save(port)
        handle = existing

        state = .starting(.health)
        let endpoint = EngineEndpoint(port: port)
        let deadline = 30
        guard await waitForHealth(endpoint, seconds: deadline) else {
            handle = nil
            try? await driver.remove(existing)
            return false
        }

        state = .running(endpoint)
        return true
    }

    /// Re-probe while running. Used by diagnostics and the reconnecting pill.
    public func checkHealth() async -> EngineHealth? {
        guard case .running(let endpoint) = state else { return lastHealth }
        if let health = await health(endpoint) {
            lastHealth = health
            return health
        }
        return nil
    }

    public func stop() async {
        guard let handle else {
            state = .stopped
            return
        }
        try? await driver.stop(handle, timeout: .seconds(10))
        self.handle = nil
        state = .stopped
    }

    public func restart(environment: (UInt16, String) -> [String: String]) async {
        await stop()
        await start(environment: environment)
    }

    /// Health was lost while running. Degraded, not failed — the conversation stays readable and
    /// the pill appears. Recovery is automatic and needs no click.
    /// Stop the engine, remove its container, and delete its three volumes.
    ///
    /// This is the one path in the app that destroys the data volume — the conversations, the
    /// agents, and the browser logins their computers hold. It is not undoable, which is why the
    /// caller confirms first and names what goes.
    ///
    /// It does **not** remove the container runtime. The person may well have installed Docker or
    /// Colima for something else, and an uninstaller that takes an unrelated tool with it is worse
    /// than one that leaves something behind. The screen says so.
    ///
    /// Every step tolerates work already done. An uninstall that fails halfway and cannot be run
    /// again leaves exactly the orphaned state it exists to prevent, so a missing container or an
    /// already-deleted volume is not an error.
    public func uninstall() async {
        await stop()
        if let handle = await driver.containerNamed(Self.engineContainerName) {
            try? await driver.remove(handle)
        }
        for volume in [Self.dataVolume, Self.workspaceVolume, Self.profilesVolume] {
            try? await driver.removeVolume(volume)
        }
        // Back to stopped, not notDetected: the runtime is still installed and still working — it
        // is only xBot's own data that is gone.
        state = .stopped
    }

    public func noteHealthLost(_ reason: RuntimeState.DegradedReason) {
        guard case .running = state else { return }
        state = .degraded(reason: reason)
    }

    public func noteHealthRecovered() {
        guard case .degraded = state, let port = allocatedPort else { return }
        state = .running(EngineEndpoint(port: port))
    }

    public func diagnostics(appVersion: String) async -> Diagnostics {
        var status = "none"
        if let handle {
            status = "\(((try? await driver.inspect(handle)) ?? .notFound))"
        }
        var tail: [String] = []
        if let handle {
            tail = ((try? await driver.logs(handle, tail: 200)) ?? []).map(\.text)
        }

        return Diagnostics(
            appVersion: appVersion,
            engineVersion: lastHealth?.engineVersion,
            runtime: driver.identifier.displayName,
            architecture: Self.architecture,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            port: allocatedPort,
            stateHistory: history,
            containerStatus: status,
            engineLogTail: tail,
            driverCommands: await (driver as? DockerDriver)?.recentCommands() ?? []
        )
    }

    private static var architecture: String {
        #if arch(arm64)
            "arm64"
        #else
            "x86_64"
        #endif
    }

    private func label(for state: RuntimeState) -> String {
        switch state {
        case .notDetected: "notDetected"
        case .stopped: "stopped"
        case .pulling(let progress): "pulling \(progress.layersComplete)/\(progress.layersTotal)"
        case .starting(let stage): "starting.\(stage.rawValue)"
        case .running(let endpoint): "running :\(endpoint.port)"
        case .degraded(let reason): "degraded.\(reason.rawValue)"
        case .failed: "failed"
        }
    }
}
