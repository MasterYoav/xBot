import Foundation

public enum RuntimeIdentifier: String, Sendable, CaseIterable {
    case docker
    case colima
    case orbstack
    case appleContainer
    case fake

    public var displayName: String {
        switch self {
        case .docker: "Docker"
        case .colima: "Colima"
        case .orbstack: "OrbStack"
        case .appleContainer: "Apple Containerization"
        case .fake: "Test runtime"
        }
    }
}

/// What a probe found. Every case has something the UI can say and, where possible, do.
public enum ProbeResult: Sendable, Equatable {
    /// Installed and its daemon is answering.
    case ready(version: String)
    /// Installed, but the daemon is not running. Recoverable without the user installing anything.
    case installedNotRunning
    /// Nothing found.
    case absent

    /// What to tell a person about this, and whether it is their problem to solve.
    ///
    /// It lives on the type rather than in the settings pane because the settings pane got it
    /// wrong: it matched on `notDetected` and ignored the probe inside it, so a Mac with a runtime
    /// installed and merely asleep was told it had none. The same window's composer said "the
    /// engine isn't running" at the same moment, which is the honest version — two surfaces
    /// contradicting each other, and the wrong one sending somebody off to install software they
    /// already had.
    public var sentence: String {
        switch self {
        case .ready(let version):
            String(localized: "Ready (\(version))")
        case .installedNotRunning:
            // Recoverable without installing anything, and Start really does wake it — the
            // controller's own start path asks the daemon to come up before giving up.
            String(localized: "The container runtime isn't running — Start will wake it")
        case .absent:
            String(localized: "No container runtime — xBot needs one to run your agents")
        }
    }

    /// Whether this is a wall or a step. A red status for "one click fixes this" is just alarming.
    public var isBlocking: Bool {
        if case .absent = self { return true }
        return false
    }
}

public struct ImageReference: Sendable, Hashable {
    public let repository: String
    /// Set when the reference uses `repository:tag`. Mutually exclusive with `digest`.
    public let tag: String?
    /// Includes the `sha256:` prefix when present.
    public let digest: String?

    public init(repository: String, tag: String) {
        self.repository = repository
        self.tag = tag
        self.digest = nil
    }

    public init(repository: String, digest: String) {
        self.repository = repository
        self.tag = nil
        self.digest = digest.hasPrefix("sha256:") ? digest : "sha256:\(digest)"
    }

    public var full: String {
        if let digest {
            let normalized = digest.hasPrefix("sha256:") ? digest : "sha256:\(digest)"
            return "\(repository)@\(normalized)"
        }
        return "\(repository):\(tag ?? "latest")"
    }

    /// Parses `repository:tag` or `repository@sha256:…` as emitted by the engine manifest.
    public init?(parsing reference: String) {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let digestMarker = trimmed.range(of: "@sha256:") {
            repository = String(trimmed[..<digestMarker.lowerBound])
            digest = String(trimmed[digestMarker.upperBound...])
            tag = nil
            guard !repository.isEmpty, !digest!.isEmpty else { return nil }
            return
        }

        guard let colon = trimmed.lastIndex(of: ":") else { return nil }
        repository = String(trimmed[..<colon])
        tag = String(trimmed[trimmed.index(after: colon)...])
        digest = nil
        guard !repository.isEmpty, let tag, !tag.isEmpty else { return nil }
    }
}

public struct PullProgress: Sendable, Equatable {
    public let layersComplete: Int
    public let layersTotal: Int
    /// Nil while the total is still unknown — which it is for the first seconds of every pull.
    public let fraction: Double?

    public init(layersComplete: Int, layersTotal: Int, fraction: Double?) {
        self.layersComplete = layersComplete
        self.layersTotal = layersTotal
        self.fraction = fraction
    }

    /// How far along, in the best terms currently available. Nil only when there is nothing true to
    /// say yet.
    ///
    /// The engine image is over four gigabytes, which makes this the longest wait in the product,
    /// and `RuntimeState`'s own note is about exactly this: "There is deliberately no 'probably
    /// starting' case. A spinner with no state behind it is how an app ends up force-quit, because
    /// the user has no way to tell waiting from stuck." Onboarding said all this already; the
    /// settings pane said "Downloading the engine" and nothing else for ten minutes.
    ///
    /// Percent when the total is known, layers while it is not — the first seconds of every pull
    /// have no total at all, and "0%" then is a worse answer than counting what has landed.
    public var detail: String? {
        if let fraction {
            return String(localized: "\(Int(fraction * 100))% complete")
        }
        if layersTotal > 0 {
            return String(localized: "\(layersComplete) of \(layersTotal) layers")
        }
        return nil
    }
}

public struct ContainerSpec: Sendable {
    public let name: String
    public let image: ImageReference
    /// Host port to container port. Every entry binds 127.0.0.1 and nothing else.
    public let ports: [UInt16: UInt16]
    public let volumes: [String: String]
    public let environment: [String: String]
    public let memoryLimitBytes: UInt64?

    public init(
        name: String,
        image: ImageReference,
        ports: [UInt16: UInt16],
        volumes: [String: String],
        environment: [String: String],
        memoryLimitBytes: UInt64? = nil
    ) {
        self.name = name
        self.image = image
        self.ports = ports
        self.volumes = volumes
        self.environment = environment
        self.memoryLimitBytes = memoryLimitBytes
    }
}

public struct ContainerHandle: Sendable, Hashable {
    public let id: String
    public init(id: String) { self.id = id }
}

public enum ContainerStatus: Sendable, Equatable {
    case running
    case exited(code: Int)
    case notFound
}

public struct LogLine: Sendable, Equatable {
    public let text: String
    public init(text: String) { self.text = text }
}

public enum RuntimeError: Error, Sendable, Equatable {
    case daemonUnavailable
    case commandFailed(command: String, exitCode: Int, message: String)
    case healthTimedOut(seconds: Int)
    case noFreePort(range: ClosedRange<UInt16>)

    /// A sentence for the composer. Never the command, never stderr — those belong in diagnostics.
    public var sentence: String {
        switch self {
        case .daemonUnavailable:
            String(localized: "Docker isn't running")
        case .commandFailed:
            // The image is not published yet (M3), a port clash, a volume error — all of them
            // look like this from the driver's point of view. The details are in Copy diagnostics.
            String(localized: "The engine couldn't start")
        case .healthTimedOut:
            String(localized: "The engine took too long to become ready")
        case .noFreePort:
            String(localized: "Couldn't find a free port for the engine")
        }
    }
}

/// The whole surface the app needs from a container runtime.
///
/// A protocol, so adding a runtime is a conformance rather than a rewrite, and so the state machine
/// can be tested end to end against `FakeDriver` without a VM.
public protocol ContainerDriver: Sendable {
    var identifier: RuntimeIdentifier { get }

    func probe() async -> ProbeResult
    func ensureDaemonRunning() async throws

    func pullImage(
        _ reference: ImageReference,
        progress: @Sendable @escaping (PullProgress) -> Void
    ) async throws
    func imageExists(_ reference: ImageReference) async -> Bool

    func createVolume(_ name: String) async throws
    func volumeExists(_ name: String) async -> Bool
    /// Delete a volume and everything in it. Only uninstall calls this.
    func removeVolume(_ name: String) async throws

    func run(_ spec: ContainerSpec) async throws -> ContainerHandle
    func stop(_ handle: ContainerHandle, timeout: Duration) async throws
    /// Ask for a stop and return as soon as the request is on its way, without waiting for it.
    ///
    /// For quitting. The app cannot wait out a ten-second graceful shutdown with its window gone, and
    /// it cannot cut the grace period either — that is Postgres being given time to stop cleanly
    /// rather than recovering from a kill on the next start. So the request has to outlive the app.
    func requestStop(_ handle: ContainerHandle, timeout: Duration) async throws
    func remove(_ handle: ContainerHandle) async throws
    func inspect(_ handle: ContainerHandle) async throws -> ContainerStatus
    func logs(_ handle: ContainerHandle, tail: Int) async throws -> [LogLine]

    /// Run a command inside a container, sending its standard output to a file.
    ///
    /// To a file rather than a returned string because the one caller is `pg_dump`, and a database
    /// held in memory to be written out again is the same database twice for no reason.
    /// `stdinFrom` is how a dump gets back in: `docker exec` reads nothing without it.
    func exec(
        _ handle: ContainerHandle,
        command: [String],
        stdoutTo url: URL,
        stdinFrom input: URL?
    ) async throws

    /// An address inside the container that reaches a service on the host.
    ///
    /// Load-bearing and easy to overlook. Two things need it: the agent's tool-call callback, and
    /// the user's local Ollama. Getting it wrong means Ollama silently does not work, which
    /// presents as a model problem and is debugged in the wrong place for an hour.
    func hostGatewayAddress() async throws -> String

    /// A container already on disk from a previous launch, if any.
    func containerNamed(_ name: String) async -> ContainerHandle?
    /// The loopback port Docker published for this container.
    func loopbackHostPort(for handle: ContainerHandle) async -> UInt16?
    /// Start a stopped container without creating a new one.
    func startContainer(_ handle: ContainerHandle) async throws
}

public extension ContainerDriver {
    func containerNamed(_ name: String) async -> ContainerHandle? { nil }
    func loopbackHostPort(for handle: ContainerHandle) async -> UInt16? { nil }
    func startContainer(_ handle: ContainerHandle) async throws {}
}
