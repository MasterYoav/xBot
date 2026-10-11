import Foundation

/// Where the agent CLIs live on this Mac.
///
/// An app started from the Dock inherits launchd's bare PATH, which contains none of the places
/// these CLIs install to, and the CLIs themselves need the person's PATH to run their tools. So
/// the PATH comes from the person's login shell, with the usual install folders added in case the
/// shell is slow or strange.
public enum HarnessLocator {
    private static let marker = "__XBOT_PATH__"

    public static func installed() async -> [HarnessKind: any Brain] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let path = searchPath(loginShellPath: await loginShellPath(shell: shell), home: home)
        let env = environment(path: path, base: ProcessInfo.processInfo.environment)
        var found: [HarnessKind: any Brain] = [:]
        for kind in HarnessKind.allCases {
            if let url = find(kind, in: path) {
                found[kind] = HarnessBrain(kind: kind, executable: url, environment: env)
            }
        }
        return found
    }

    public static func searchPath(loginShellPath: String?, home: String) -> String {
        let usual = [
            "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin",
            "\(home)/.bun/bin", "\(home)/.claude/local", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        var seen = Set<String>()
        return ((loginShellPath ?? "").split(separator: ":").map(String.init) + usual)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
    }

    public static func find(_ kind: HarnessKind, in path: String) -> URL? {
        path.split(separator: ":")
            .map { URL(filePath: String($0)).appending(path: kind.executableName) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public static func environment(path: String, base: [String: String]) -> [String: String] {
        var env = base.filter { !$0.key.hasPrefix("CLAUDECODE") && !$0.key.hasPrefix("CLAUDE_CODE_") }
        env["PATH"] = path
        return env
    }

    /// PATH as an interactive login shell sets it, or nil after five seconds. Markers around the
    /// value, because a shell's startup files are allowed to print whatever they like.
    public static func loginShellPath(shell: String) async -> String? {
        let process = Process()
        process.executableURL = URL(filePath: shell)
        process.arguments = ["-l", "-i", "-c", "printf '\(marker)%s\(marker)' \"$PATH\""]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }

        let pid = process.processIdentifier
        let timeout = Task.detached {
            try await Task.sleep(for: .seconds(5))
            kill(pid, SIGKILL)
        }
        let data = await PipeReader.readAll(output.fileHandleForReading)
        timeout.cancel()
        let parts = String(decoding: data, as: UTF8.self).components(separatedBy: marker)
        return parts.count >= 3 && !parts[1].isEmpty ? parts[1] : nil
    }
}
