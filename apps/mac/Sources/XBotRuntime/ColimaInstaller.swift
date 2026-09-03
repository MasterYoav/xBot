import Foundation

public struct RuntimeInstallProgress: Sendable, Equatable {
    public enum Phase: String, Sendable {
        case downloading
        case installing
        case starting
    }

    public var phase: Phase
    public var label: String
    public var fraction: Double?

    public init(phase: Phase, label: String, fraction: Double? = nil) {
        self.phase = phase
        self.label = label
        self.fraction = fraction
    }
}

/// Installs Colima and the Docker CLI into Application Support without a terminal window.
public actor ColimaInstaller {
    public enum Failure: Error, Sendable {
        case downloadFailed
        case installFailed
        case startFailed
    }

    private static let colimaVersion = "v0.8.1"
    private static let dockerVersion = "27.3.1"

    public init() {}

    public func install(
        report: @Sendable @escaping (RuntimeInstallProgress) -> Void
    ) async throws {
        try RuntimePaths.ensureDirectories()

        report(RuntimeInstallProgress(
            phase: .downloading,
            label: String(localized: "Downloading container runtime"),
            fraction: 0
        ))

        let arch = Self.machineArchitecture
        try await downloadColima(architecture: arch, report: report)
        try await downloadDockerCLI(architecture: arch, report: report)

        report(RuntimeInstallProgress(
            phase: .installing,
            label: String(localized: "Installing"),
            fraction: nil
        ))
        try markExecutable(RuntimePaths.colimaExecutable)
        try markExecutable(RuntimePaths.dockerExecutable)

        report(RuntimeInstallProgress(
            phase: .starting,
            label: String(localized: "Starting container runtime"),
            fraction: nil
        ))
        try await startColima()
    }

    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: RuntimePaths.colimaExecutable.path)
            && FileManager.default.isExecutableFile(atPath: RuntimePaths.dockerExecutable.path)
    }

    private func downloadColima(
        architecture: String,
        report: @Sendable @escaping (RuntimeInstallProgress) -> Void
    ) async throws {
        let name = architecture == "arm64" ? "colima-Darwin-arm64" : "colima-Darwin-x86_64"
        let url = URL(
            string: "https://github.com/abiosoft/colima/releases/download/\(Self.colimaVersion)/\(name)"
        )!
        let destination = RuntimePaths.colimaExecutable
        try await download(from: url, to: destination, report: report, baseFraction: 0, span: 0.45)
    }

    private func downloadDockerCLI(
        architecture: String,
        report: @Sendable @escaping (RuntimeInstallProgress) -> Void
    ) async throws {
        let archFolder = architecture == "arm64" ? "aarch64" : "x86_64"
        let url = URL(
            string:
                "https://download.docker.com/mac/static/stable/\(archFolder)/docker-\(Self.dockerVersion).tgz"
        )!
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("xbot-docker.tgz")
        try await download(from: url, to: temporary, report: report, baseFraction: 0.45, span: 0.45)
        try extractDockerBinary(from: temporary, to: RuntimePaths.dockerExecutable)
        try? FileManager.default.removeItem(at: temporary)
    }

    private func download(
        from url: URL,
        to destination: URL,
        report: @Sendable @escaping (RuntimeInstallProgress) -> Void,
        baseFraction: Double,
        span: Double
    ) async throws {
        report(RuntimeInstallProgress(
            phase: .downloading,
            label: String(localized: "Downloading container runtime"),
            fraction: baseFraction
        ))
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure.downloadFailed
        }
        try data.write(to: destination, options: .atomic)
        report(RuntimeInstallProgress(
            phase: .downloading,
            label: String(localized: "Downloading container runtime"),
            fraction: baseFraction + span
        ))
    }

    private func extractDockerBinary(from archive: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        let folder = archive.deletingLastPathComponent()
        process.arguments = ["-xzf", archive.path, "-C", folder.path, "docker"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.installFailed }

        let extracted = folder.appendingPathComponent("docker")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: extracted, to: destination)
    }

    private func markExecutable(_ url: URL) throws {
        var attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        attributes[.posixPermissions] = 0o755
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
    }

    private func startColima() async throws {
        let colima = RuntimePaths.colimaExecutable.path
        guard FileManager.default.isExecutableFile(atPath: colima) else {
            throw Failure.startFailed
        }

        let start = Process()
        start.executableURL = URL(fileURLWithPath: colima)
        start.arguments = ["start", "--mount-type", "virtiofs", "--cpu", "2", "--memory", "4"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(RuntimePaths.binDirectory.path):\(environment["PATH"] ?? "")"
        start.environment = environment
        start.standardOutput = FileHandle.nullDevice
        start.standardError = FileHandle.nullDevice
        try start.run()
        start.waitUntilExit()
        guard start.terminationStatus == 0 else { throw Failure.startFailed }

        // Colima needs a moment before the Docker socket answers.
        for _ in 0..<30 {
            let driver = DockerDriver(
                identifier: .colima,
                executable: RuntimePaths.preferredDockerExecutable()
            )
            if case .ready = await driver.probe() { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw Failure.startFailed
    }

    private static var machineArchitecture: String {
        #if arch(arm64)
            "arm64"
        #else
            "x86_64"
        #endif
    }
}
