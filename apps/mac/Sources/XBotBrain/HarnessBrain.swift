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

        // Codex reads its schema from a file; one per turn, removed when the turn ends.
        var schemaFile: URL?
        if kind == .codex, let schema = request.schema {
            let file = FileManager.default.temporaryDirectory.appending(path: "xbot-schema-\(UUID().uuidString).json")
            do {
                try Data(schema.utf8).write(to: file)
                schemaFile = file
            } catch {
                continuation.yield(.failed(String(localized: "xBot couldn't prepare this turn: \(error.localizedDescription)")))
                continuation.finish()
                return stream
            }
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = kind.arguments(for: request, schemaFile: schemaFile)
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
            if let schemaFile { try? FileManager.default.removeItem(at: schemaFile) }
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
        // A CLI that exits without reading its prompt closes the pipe under us, and writing to it
        // raises SIGPIPE, whose default action ends the whole app. With this the write just fails,
        // and the turn reports the CLI's own complaint from stderr.
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        let prompt = Data(request.prompt.utf8)
        Task.detached {
            try? writer.write(contentsOf: prompt)
            try? writer.close()
        }

        let kind = self.kind
        let finishedSchema = schemaFile
        Task.detached {
            var ended = false
            var tail: SchemaTail? = finishedSchema == nil ? nil : SchemaTail()
            func emit(_ line: [UInt8]) {
                for parsed in kind.events(from: String(decoding: line, as: UTF8.self)) {
                    for event in tail?.process(parsed) ?? [parsed] where !ended {
                        continuation.yield(event)
                        ended = event.isTerminal
                    }
                }
            }
            do {
                // Split on "\n" bytes ourselves. `bytes.lines` also breaks at U+2028 and U+2029,
                // which JSON may carry raw inside a string, and half a JSON line is no line at all.
                var line: [UInt8] = []
                for try await byte in output.fileHandleForReading.bytes {
                    guard byte == UInt8(ascii: "\n") else { line.append(byte); continue }
                    emit(line)
                    line.removeAll(keepingCapacity: true)
                }
                emit(line)
            } catch {}
            var status: Int32 = 0
            for await code in exit.stream { status = code }
            _ = await stderrReader.result
            if let finishedSchema { try? FileManager.default.removeItem(at: finishedSchema) }
            if !ended {
                let said = stderr.text.trimmingCharacters(in: .whitespacesAndNewlines)
                // A clean exit with nothing said is the CLI finishing; only its last line went missing.
                if status == 0 && said.isEmpty {
                    continuation.yield(.done)
                    continuation.finish()
                    return
                }
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
