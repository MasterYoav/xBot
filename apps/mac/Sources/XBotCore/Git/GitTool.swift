import Foundation

public struct ProcessResult: Sendable {
    public var status: Int32
    public var output: String
    public var error: String
    public var succeeded: Bool { status == 0 }
}

/// git (and GitHub's gh, when installed), run as processes in a project's folder.
public struct GitTool: Sendable, Equatable {
    public let git: URL
    public let gh: URL?
    public let environment: [String: String]

    /// The first git on the usual PATH. `/usr/bin/git` is only a stub that offers to install the
    /// Command Line Tools, so it counts only when they (or Xcode) are there.
    /// ponytail: Xcode is looked for at its default path only; a renamed Xcode reads as "not installed".
    public static func find(
        searchPath: String = HarnessLocator.searchPath(loginShellPath: nil, home: NSHomeDirectory()),
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> GitTool? {
        let folders = searchPath.split(separator: ":").map(String.init)
        let developerTools = fileExists("/Library/Developer/CommandLineTools/usr/bin/git")
            || fileExists("/Applications/Xcode.app/Contents/Developer/usr/bin/git")
        guard let git = folders.map({ "\($0)/git" }).first(where: { path in
            fileExists(path) && (path != "/usr/bin/git" || developerTools)
        }) else { return nil }
        let gh = folders.map { "\($0)/gh" }.first(where: fileExists)
        var env = HarnessLocator.environment(path: searchPath, base: ProcessInfo.processInfo.environment)
        // No terminal to type a password into: fail with git's message instead of waiting forever.
        env["GIT_TERMINAL_PROMPT"] = "0"
        if env["GIT_SSH_COMMAND"] == nil { env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes" }
        // `git status` must not rewrite the index: the folder watcher would see that and ask again.
        env["GIT_OPTIONAL_LOCKS"] = "0"
        return GitTool(git: URL(filePath: git), gh: gh.map { URL(filePath: $0) }, environment: env)
    }

    public func git(_ arguments: [String], in directory: URL, input: String? = nil) async -> ProcessResult {
        await run(git, arguments, in: directory, input: input)
    }

    /// Nil when gh is not installed.
    public func gh(_ arguments: [String], in directory: URL) async -> ProcessResult? {
        guard let gh else { return nil }
        return await run(gh, arguments, in: directory, input: nil)
    }

    private func run(_ executable: URL, _ arguments: [String], in directory: URL, input: String?) async -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        let out = Pipe(), err = Pipe(), stdin = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        do { try process.run() } catch {
            return ProcessResult(status: -1, output: "", error: error.localizedDescription)
        }
        if let input {
            // Written from its own task: a long input and a long output would otherwise wait on each other.
            let writer = stdin.fileHandleForWriting
            Task.detached {
                writer.write(Data(input.utf8))
                try? writer.close()
            }
        }
        async let output = Task.detached { out.fileHandleForReading.readDataToEndOfFile() }.value
        async let error = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }.value
        let (o, e) = await (output, error)
        // Both pipes are at end of file, so the process has exited or is about to.
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            output: String(decoding: o, as: UTF8.self),
            error: String(decoding: e, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
