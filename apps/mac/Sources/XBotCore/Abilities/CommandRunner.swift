import Foundation

/// The outcome of one CLI command.
public struct CommandResult: Equatable, Sendable {
    public var status: Int32
    public var output: String
    public var error: String

    public init(status: Int32, output: String, error: String = "") {
        self.status = status; self.output = output; self.error = error
    }

    public var succeeded: Bool { status == 0 }

    /// What to tell the person when it failed: the CLI's own last sentence, not a code.
    public var reason: String {
        let text = [error, output].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        return text?.split(whereSeparator: \.isNewline).last.map(String.init)
            ?? String(localized: "It stopped with code \(status).")
    }
}

/// Runs an agent's CLI and waits for it. A protocol so tests can script the answers.
public protocol CommandRunner: Sendable {
    /// `directory` is where it runs: Claude Code's project-scoped settings are keyed by it.
    func run(_ executable: URL, _ arguments: [String], environment: [String: String], directory: URL?,
             timeout: Duration) async -> CommandResult
}

/// The real thing: a process, both pipes read to the end concurrently (a full pipe would otherwise
/// block the child), the exit awaited through `terminationHandler` rather than `waitUntilExit`, and a
/// time limit, since a health check that connects to a dead server can hang.
public struct ProcessRunner: CommandRunner {
    public init() {}

    public func run(_ executable: URL, _ arguments: [String], environment: [String: String], directory: URL?,
                    timeout: Duration) async -> CommandResult {
        let process = Process()
        process.executableURL = executable
        if let directory { process.currentDirectoryURL = directory }
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let exit = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { exit.continuation.yield($0.terminationStatus); exit.continuation.finish() }
        do { try process.run() } catch {
            return CommandResult(status: -1, output: "", error: error.localizedDescription)
        }
        let pid = process.processIdentifier
        let killer = Task.detached {
            try await Task.sleep(for: timeout)
            kill(pid, SIGKILL)
        }
        async let output = Self.read(out)
        async let errors = Self.read(err)
        let (o, e) = await (output, errors)
        var status: Int32 = -1
        for await code in exit.stream { status = code }
        killer.cancel()
        return CommandResult(status: status, output: o, error: e)
    }

    private static func read(_ pipe: Pipe) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
        }
    }
}
