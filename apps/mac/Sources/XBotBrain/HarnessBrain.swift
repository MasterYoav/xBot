import Foundation
import Synchronization

/// One turn of an installed agent CLI, as a stream of `BrainEvent`s.
///
/// A fresh process per turn, resumed by the CLI's own session id. That is how monocode drives the
/// same CLIs, and it means a crashed turn cannot leave a wedged process behind for the next one.
public struct HarnessBrain: Brain {
    public let kind: HarnessKind
    public let executable: URL
    public let environment: [String: String]

    public init(kind: HarnessKind, executable: URL, environment: [String: String]) {
        self.kind = kind
        self.executable = executable
        self.environment = environment
    }

    public func run(_ request: TurnRequest) -> AsyncStream<BrainEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: BrainEvent.self)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: request.directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            continuation.yield(.failed(String(
                localized: "This chat's folder is no longer at \(request.directory.path). Move it back, or start a new chat."
            )))
            continuation.finish()
            return stream
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = kind.arguments(for: request)
        process.currentDirectoryURL = request.directory
        process.environment = environment
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        // Read as async bytes, not with a readabilityHandler: that handler fires again and again
        // with empty data once the pipe reaches end-of-file, spinning a core until someone clears it.
        let stderr = Tail()
        let stderrReader = Task.detached {
            var buffer = Data()
            for try await byte in errors.fileHandleForReading.bytes {
                buffer.append(byte)
                if buffer.count >= 512 { stderr.append(buffer); buffer.removeAll(keepingCapacity: true) }
            }
            stderr.append(buffer)
        }
        let exit = AsyncStream.makeStream(of: Int32.self)
        let exited = Atomic(false)
        process.terminationHandler = { finished in
            exited.store(true, ordering: .sequentiallyConsistent)
            exit.continuation.yield(finished.terminationStatus)
            exit.continuation.finish()
        }

        do {
            try process.run()
        } catch {
            continuation.yield(.failed(String(
                localized: "\(kind.displayName) could not start: \(error.localizedDescription)"
            )))
            continuation.finish()
            return stream
        }

        let pid = process.processIdentifier
        // ponytail: SIGTERM to the CLI only; it tears down its own tool processes. Kill the process
        // group instead if one is ever seen surviving.
        continuation.onTermination = { _ in
            if !exited.load(ordering: .sequentiallyConsistent) { kill(pid, SIGTERM) }
        }

        // The prompt goes on stdin, never argv. Written off this thread so a huge prompt cannot
        // block the caller while the CLI is busy printing.
        let writer = input.fileHandleForWriting
        let prompt = Data(request.prompt.utf8)
        Task.detached {
            try? writer.write(contentsOf: prompt)
            try? writer.close()
        }

        let kind = self.kind
        Task.detached {
            var ended = false
            do {
                for try await line in output.fileHandleForReading.bytes.lines {
                    for event in kind.events(from: line) where !ended {
                        continuation.yield(event)
                        ended = event.isTerminal
                    }
                }
            } catch {}
            var status: Int32 = 0
            for await code in exit.stream { status = code }
            _ = await stderrReader.result
            if !ended {
                let said = stderr.text.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.yield(.failed(said.isEmpty
                    ? String(localized: "\(kind.displayName) stopped before finishing (exit code \(status)).")
                    : said))
            }
            continuation.finish()
        }
        return stream
    }
}

/// The last few kilobytes a process wrote to stderr: where a CLI explains why it gave up.
private final class Tail: Sendable {
    private let data = Mutex(Data())
    private let limit = 4096

    func append(_ chunk: Data) {
        data.withLock { data in
            data.append(chunk)
            if data.count > limit { data.removeFirst(data.count - limit) }
        }
    }

    var text: String { data.withLock { String(decoding: $0, as: UTF8.self) } }
}
