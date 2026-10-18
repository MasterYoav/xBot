import Foundation
import Synchronization

/// `XBot --mcp`: the MCP server over stdio. Reads one JSON-RPC message per line from the CLI,
/// answers each as it finishes (a long `xbot_ask` doesn't hold up a ping), and ends when the CLI
/// closes its stdin. Idle between calls: a blocked read, no timers.
public enum MCPStdio {
    /// Serves until `input` ends and every answer is written.
    public static func serve(_ server: MCPServer, input: FileHandle = .standardInput, output: FileHandle = .standardOutput) async {
        let writer = LineWriter(output)
        let lines = AsyncStream<String> { continuation in
            let thread = Thread {
                var buffer = Data()
                let fd = input.fileDescriptor
                while let line = try? UnixSocket.readLine(fd, buffer: &buffer) {
                    continuation.yield(String(decoding: line, as: UTF8.self))
                }
                continuation.finish()
            }
            thread.stackSize = 512 * 1024
            thread.start()
        }
        await withTaskGroup(of: Void.self) { group in
            for await line in lines {
                group.addTask {
                    guard let reply = await server.handle(line) else { return }
                    writer.write(reply)
                }
            }
        }
    }
}

/// One whole line at a time to the CLI, whichever answer finishes first. A class, not a captured
/// `Mutex` (CI's Swift 6.3 won't send a closure that captures a non-copyable value).
final class LineWriter: Sendable {
    private let output: Mutex<FileHandle>

    init(_ output: FileHandle) { self.output = Mutex(output) }

    func write(_ line: String) {
        output.withLock { try? $0.write(contentsOf: Data((line + "\n").utf8)) }
    }
}
