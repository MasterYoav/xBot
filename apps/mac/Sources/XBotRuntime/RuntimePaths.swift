import Foundation

/// Application Support paths for a bundled Colima + Docker CLI install (ADR-0003).
public enum RuntimePaths: Sendable {
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("xBot/runtime", isDirectory: true)
    }

    public static var binDirectory: URL {
        supportDirectory.appendingPathComponent("bin", isDirectory: true)
    }

    public static var colimaExecutable: URL {
        binDirectory.appendingPathComponent("colima")
    }

    public static var dockerExecutable: URL {
        binDirectory.appendingPathComponent("docker")
    }

    public static func preferredDockerExecutable() -> String {
        if FileManager.default.isExecutableFile(atPath: dockerExecutable.path) {
            return dockerExecutable.path
        }
        return DockerDriver.defaultDockerPath()
    }

    public static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
    }
}
