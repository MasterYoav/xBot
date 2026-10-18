import Foundation
import Synchronization

/// `XBot --mcp`: the MCP server over stdio. Reads one JSON-RPC message per line from the CLI,
/// answers each as it finishes (a long `xbot_ask` doesn't hold up a ping), and ends when the CLI
/// closes its stdin. Idle between calls: a blocked read, no timers.
public enum MCPStdio {
    /// Serves until `input` ends and every answer is written.
    public static func serve(_ server: MCPServer, input: FileHandle = .standardInput, output: FileHandle = .standardOutput) async {
        let writer = Mutex(output)
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
                    writer.withLock { try? $0.write(contentsOf: Data((reply + "\n").utf8)) }
                }
            }
        }
    }
}
