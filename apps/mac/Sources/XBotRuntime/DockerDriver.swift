import Foundation

/// The Docker CLI, driven as a subprocess.
///
/// The CLI rather than the socket API. The socket is a nicer interface and it is also
/// root-equivalent on the host — anything that can talk to it can start a privileged container.
/// Going through the binary keeps the app inside the permission model the user already granted
/// Docker, and means Colima and OrbStack work through the same code because both ship a `docker`.
public actor DockerDriver: ContainerDriver {
    public nonisolated let identifier: RuntimeIdentifier
    private let executable: String

    /// The last commands run, for diagnostics. Bounded, because this lives for the session.
    private var commandLog: [String] = []
    private static let commandLogLimit = 50

    public init(identifier: RuntimeIdentifier = .docker, executable: String? = nil) {
        self.identifier = identifier
        self.executable = executable ?? Self.defaultDockerPath()
    }

    /// Find `docker` without inheriting the user's shell.
    public static func defaultDockerPath() -> String {
        let candidates = [
            RuntimePaths.dockerExecutable.path,
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "\(NSHomeDirectory())/.orbstack/bin/docker",
            "\(NSHomeDirectory())/.docker/bin/docker",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/usr/local/bin/docker"
    }

    // MARK: - Probing

    public func probe() async -> ProbeResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return .absent }
        let version = try? await run(["version", "--format", "{{.Server.Version}}"])
        guard let version, !version.isEmpty else {
            // The binary is here and the daemon is not answering. Recoverable, and a very
            // different sentence from "install Docker" — so it is a different case.
            return .installedNotRunning
        }
        return .ready(version: version.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func ensureDaemonRunning() async throws {
        if case .ready = await probe() { return }
        throw RuntimeError.daemonUnavailable
    }

    // MARK: - Images

    public func imageExists(_ reference: ImageReference) async -> Bool {
        let output = try? await run(["images", "-q", reference.full])
        return !(output ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func pullImage(
        _ reference: ImageReference,
        progress: @Sendable @escaping (PullProgress) -> Void
    ) async throws {
        var complete = 0
        var total = 0
        // Counted here, in the actor, rather than inside a callback the subprocess drives. The
        // compiler rejected the callback shape outright — two tasks mutating a running total is a
        // race whether or not it looks like one — and iterating the lines keeps the count isolated.
        for try await line in lines(of: ["pull", reference.full]) {
            // Docker's plain progress is one line per layer event. Counting "Pull complete"
            // against the number of distinct layers seen is coarse but honest, and it never
            // reports a percentage it cannot back up — `fraction` stays nil until a total exists.
            if line.contains("Pulling fs layer") { total += 1 }
            if line.contains("Pull complete") { complete += 1 }
            progress(
                PullProgress(
                    layersComplete: complete,
                    layersTotal: total,
                    fraction: total > 0 ? min(1, Double(complete) / Double(total)) : nil
                )
            )
        }
    }

    // MARK: - Volumes

    public func createVolume(_ name: String) async throws {
        _ = try await run(["volume", "create", name])
    }

    public func volumeExists(_ name: String) async -> Bool {
        let output = try? await run(["volume", "ls", "-q", "--filter", "name=^\(name)$"])
        return !(output ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Containers

    public func run(_ spec: ContainerSpec) async throws -> ContainerHandle {
        var arguments = ["run", "-d", "--name", spec.name]

        for (host, container) in spec.ports.sorted(by: { $0.key < $1.key }) {
            // 127.0.0.1 explicitly, never a bare -p. A bare mapping binds every interface, and
            // the browser inside this container holds the user's real logins.
            arguments += ["-p", "127.0.0.1:\(host):\(container)"]
        }
        for (volume, path) in spec.volumes.sorted(by: { $0.key < $1.key }) {
            arguments += ["-v", "\(volume):\(path)"]
        }
        for key in spec.environment.keys.sorted() {
            arguments += ["-e", "\(key)=\(spec.environment[key]!)"]
        }
        if let memory = spec.memoryLimitBytes {
            arguments += ["--memory", "\(memory)"]
        }
        arguments += ["--security-opt", "no-new-privileges"]
        arguments += ["--restart", "unless-stopped"]
        arguments.append(spec.image.full)

        let output = try await run(arguments)
        return ContainerHandle(
            id: output.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public func stop(_ handle: ContainerHandle, timeout: Duration) async throws {
        let seconds = Int(timeout.components.seconds)
        _ = try await run(["stop", "-t", "\(seconds)", handle.id])
    }

    public func remove(_ handle: ContainerHandle) async throws {
        _ = try await run(["rm", "-f", handle.id])
    }

    public func inspect(_ handle: ContainerHandle) async throws -> ContainerStatus {
        guard
            let output = try? await run(
                ["inspect", "-f", "{{.State.Running}} {{.State.ExitCode}}", handle.id]
            )
        else { return .notFound }

        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard parts.count == 2 else { return .notFound }
        if parts[0] == "true" { return .running }
        return .exited(code: Int(parts[1]) ?? -1)
    }

    public func logs(_ handle: ContainerHandle, tail: Int) async throws -> [LogLine] {
        let output = try await run(["logs", "--tail", "\(tail)", handle.id])
        return output.split(separator: "\n").map { LogLine(text: String($0)) }
    }

    public func hostGatewayAddress() async throws -> String {
        // Docker Desktop, Colima and OrbStack all resolve this inside a container. Apple's
        // runtime does not, which is why this is on the protocol rather than a constant.
        "host.docker.internal"
    }

    public func containerNamed(_ name: String) async -> ContainerHandle? {
        guard
            let output = try? await run(["inspect", "-f", "{{.Id}}", name]),
            !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return ContainerHandle(id: name)
    }

    public func loopbackHostPort(for handle: ContainerHandle) async -> UInt16? {
        guard let output = try? await run(["port", handle.id]) else { return nil }
        for line in output.split(separator: "\n") {
            guard let arrow = line.range(of: " -> ") else { continue }
            let destination = line[arrow.upperBound...]
            guard destination.hasPrefix("127.0.0.1:") else { continue }
            guard let port = destination.split(separator: ":").last.flatMap({ UInt16($0) }) else {
                continue
            }
            return port
        }
        return nil
    }

    public func startContainer(_ handle: ContainerHandle) async throws {
        _ = try await run(["start", handle.id])
    }

    public func recentCommands() -> [String] { commandLog }

    // MARK: - Process plumbing

    @discardableResult
    private func run(_ arguments: [String]) async throws -> String {
        note(arguments)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe

        try process.run()
        // Read before waiting. A pipe whose buffer fills blocks the child forever, and
        // `waitUntilExit` would then never return — the classic subprocess deadlock.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw RuntimeError.commandFailed(
                command: "docker \(arguments.joined(separator: " "))",
                exitCode: Int(process.terminationStatus),
                message: String(decoding: errorData, as: UTF8.self)
            )
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// A long-running command's output, line by line.
    ///
    /// Returned as a sequence rather than pushed into a callback so the caller's own state stays
    /// where the caller can reason about it. Nothing here is `@Sendable`, which is the point.
    private func lines(of arguments: [String]) -> AsyncThrowingStream<String, Error> {
        note(arguments)
        let executable = executable
        return AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let task = Task {
                do {
                    try process.run()
                    for try await line in pipe.fileHandleForReading.bytes.lines {
                        continuation.yield(line)
                    }
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.finish()
                    } else {
                        continuation.finish(
                            throwing: RuntimeError.commandFailed(
                                command: "docker \(arguments.joined(separator: " "))",
                                exitCode: Int(process.terminationStatus),
                                message: ""
                            )
                        )
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // A cancelled pull must actually stop pulling. Without this the subprocess keeps
            // downloading gigabytes for a screen the user has already left.
            continuation.onTermination = { _ in
                task.cancel()
                if process.isRunning { process.terminate() }
            }
        }
    }

    private func note(_ arguments: [String]) {
        // Arguments only, never the environment: `docker run -e KEY_ENCRYPTION_KEY=…` would put
        // the key in the diagnostics bundle. Redaction runs over this too, but the cheapest
        // secret to redact is the one that was never recorded.
        let safe = arguments.map { $0.contains("=") ? String($0.prefix(while: { $0 != "=" })) + "=…" : $0 }
        commandLog.append("docker \(safe.joined(separator: " "))")
        if commandLog.count > Self.commandLogLimit { commandLog.removeFirst() }
    }
}
