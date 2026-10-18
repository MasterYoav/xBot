import Foundation

/// The app's end of the tool socket and the server's: plain POSIX Unix-domain stream sockets, one
/// JSON line each way per call. A socket file is the only door (CLAUDE.md invariant 5): no port.
public enum UnixSocket {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
        init(_ what: String, _ code: Int32 = errno) {
            description = "\(what): \(String(cString: strerror(code)))"
        }
        init(message: String) { description = message }
    }

    /// `sun_path` holds 104 bytes, the last a NUL.
    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw Failure(message: "The socket path is too long: \(path)") }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }

    static func makeSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure("socket") }
        var on: Int32 = 1
        // A peer that went away makes write fail, instead of SIGPIPE ending the process.
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    /// Connected, or thrown (nothing listening: the app isn't running).
    static func connect(to path: String) throws -> Int32 {
        var address = try address(path)
        let fd = try makeSocket()
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            close(fd)
            throw Failure("connect", code)
        }
        return fd
    }

    static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw Failure("write")
                }
                offset += written
            }
        }
    }

    /// The next line (without its "\n"), or nil at the end. `buffer` keeps what came after it.
    static func readLine(_ fd: Int32, buffer: inout Data, limit: Int = 32 << 20) throws -> Data? {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer = Data(buffer[(newline + 1)...])
                return Data(line)
            }
            guard buffer.count <= limit else { throw Failure(message: "A message was too long.") }
            let count = read(fd, &chunk, chunk.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw Failure("read")
            }
            if count == 0 {
                guard !buffer.isEmpty else { return nil }
                defer { buffer.removeAll() }
                return buffer
            }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }

    /// Runs blocking socket work on a thread of its own, so a call waiting ten minutes for an
    /// approval doesn't sit on one of Swift's few cooperative threads.
    static func onThread<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let thread = Thread { continuation.resume(returning: work()) }
            thread.stackSize = 512 * 1024
            thread.start()
        }
    }
}

/// `XBot --mcp`'s side: each tool call to the app, with the turn's token.
public struct ToolClient: ToolForwarding {
    public let socketPath: String
    public let token: String?

    public init(socketPath: String, token: String?) {
        self.socketPath = socketPath
        self.token = token
    }

    /// From the environment the CLI gave the server: the token, and the app's socket.
    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> ToolClient {
        ToolClient(socketPath: environment[ToolEnvironment.socket] ?? ToolEnvironment.defaultSocketPath,
                   token: environment[ToolEnvironment.token].flatMap { $0.isEmpty ? nil : $0 })
    }

    public static let notRunning = "xBot isn't running, so its tools can't be used right now. Ask the person to open xBot on their Mac."

    public func call(_ name: String, arguments: JSONValue) async -> ToolResult {
        await send(ToolCall(token: token ?? "", tool: name, arguments: arguments))
    }

    public func send(_ call: ToolCall) async -> ToolResult {
        guard !call.token.isEmpty else {
            return .error("This xBot tool wasn't started by xBot for a chat, so it can't act. Use it from a chat in xBot.")
        }
        guard let line = try? JSONEncoder().encode(call) else { return .error("xBot couldn't send that call.") }
        let path = socketPath
        return await UnixSocket.onThread {
            let fd: Int32
            do { fd = try UnixSocket.connect(to: path) } catch { return .error(Self.notRunning) }
            defer { close(fd) }
            do {
                try UnixSocket.writeAll(fd, line + Data("\n".utf8))
                var buffer = Data()
                guard let reply = try UnixSocket.readLine(fd, buffer: &buffer) else {
                    return .error("xBot closed before answering (it may have quit).")
                }
                return (try? JSONDecoder().decode(ToolResult.self, from: reply))
                    ?? .error("xBot's answer couldn't be read.")
            } catch {
                return .error("xBot closed before answering (it may have quit).")
            }
        }
    }
}

/// The names the app and the server agree on.
public enum ToolEnvironment {
    /// The per-turn token: which chat and agent are asking.
    public static let token = "XBOT_TOOLS_TOKEN"
    /// The app's socket, passed so a sandboxed or relocated app is still found.
    public static let socket = "XBOT_TOOLS_SOCKET"

    /// `~/Library/Application Support/xBot/xbot.sock`.
    public static var defaultSocketPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "xBot/xbot.sock").path(percentEncoded: false)
    }
}

/// The app's end: accepts the server's connections and answers each call. Only this user's
/// processes can connect (the file is 0600, and each peer's uid is checked again).
public final class ToolSocketListener: @unchecked Sendable {
    public let path: String
    private let answer: @Sendable (ToolCall) async -> ToolResult
    private var source: (any DispatchSourceRead)?
    private let queue = DispatchQueue(label: "xbot.tools.accept")

    public init(path: String, answer: @escaping @Sendable (ToolCall) async -> ToolResult) {
        self.path = path
        self.answer = answer
    }

    public func start() throws {
        var address = try UnixSocket.address(path)
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        // A socket left by a crash would make bind fail.
        unlink(path)
        let fd = try UnixSocket.makeSocket()
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw UnixSocket.Failure("bind", code)
        }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw UnixSocket.Failure("listen", code)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptWaiting(fd) }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }

    /// Stops listening and removes the socket file.
    public func stop() {
        source?.cancel()
        source = nil
        unlink(path)
    }

    deinit { stop() }

    private func acceptWaiting(_ fd: Int32) {
        while true {
            let connection = accept(fd, nil, nil)
            guard connection >= 0 else { return }
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(connection, &uid, &gid) == 0, uid == getuid() else {
                close(connection)
                continue
            }
            var on: Int32 = 1
            setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            // Back to blocking: the connection's own thread waits on it.
            _ = fcntl(connection, F_SETFL, fcntl(connection, F_GETFL) & ~O_NONBLOCK)
            let answer = self.answer
            let thread = Thread { Self.serve(connection, answer: answer) }
            thread.stackSize = 512 * 1024
            thread.start()
        }
    }

    /// Calls, one line each, until the peer closes.
    private static func serve(_ fd: Int32, answer: @escaping @Sendable (ToolCall) async -> ToolResult) {
        defer { close(fd) }
        var buffer = Data()
        while let line = try? UnixSocket.readLine(fd, buffer: &buffer) {
            let result: ToolResult
            if let call = try? JSONDecoder().decode(ToolCall.self, from: line) {
                let box = ResultBox()
                let done = DispatchSemaphore(value: 0)
                Task {
                    box.value = await answer(call)
                    done.signal()
                }
                done.wait()
                result = box.value ?? .error("xBot couldn't answer.")
            } else {
                result = .error("xBot couldn't read that call.")
            }
            guard let data = try? JSONEncoder().encode(result),
                  (try? UnixSocket.writeAll(fd, data + Data("\n".utf8))) != nil else { return }
        }
    }
}

/// Handed from the answering task to the connection's thread, across the semaphore.
private final class ResultBox: @unchecked Sendable {
    var value: ToolResult?
}
