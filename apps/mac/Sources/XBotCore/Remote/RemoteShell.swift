import Foundation
import Synchronization
import SwiftTerm
import XBotRemote

/// A login shell on the Mac for a phone's terminal: a pseudo-terminal with no view. What it
/// writes is gathered for a moment and handed over in one piece, so typing a long command or
/// printing a big file doesn't become a message per byte.
final class RemoteShell: LocalProcessDelegate, @unchecked Sendable {
    let id: UUID
    let directory: URL
    private var process: LocalProcess!
    private let size: Mutex<winsize>
    private let pending = Mutex<Data>(Data())
    private let flushScheduled = Mutex(false)
    private let queue = DispatchQueue(label: "dev.xbot.remote-shell")
    /// On the main actor: output to send, and the end.
    let output: @MainActor @Sendable (Data) -> Void
    let ended: @MainActor @Sendable () -> Void

    init(id: UUID = UUID(), directory: URL, cols: Int, rows: Int, output: @escaping @MainActor @Sendable (Data) -> Void,
         ended: @escaping @MainActor @Sendable () -> Void) {
        self.id = id
        self.directory = directory
        self.output = output
        self.ended = ended
        size = Mutex(winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: cols), ws_xpixel: 0, ws_ypixel: 0))
        process = LocalProcess(delegate: self, dispatchQueue: queue)
    }

    func start() {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        if environment["LANG"] == nil { environment["LANG"] = "en_US.UTF-8" }
        process.startProcess(executable: shell, args: ["-l"], environment: environment.map { "\($0.key)=\($0.value)" },
                             execName: "-" + (shell as NSString).lastPathComponent, currentDirectory: directory.path)
    }

    func send(_ data: Data) { process.send(data: ArraySlice([UInt8](data))) }

    func resize(cols: Int, rows: Int) {
        var new = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: cols), ws_xpixel: 0, ws_ypixel: 0)
        size.withLock { $0 = new }
        if process.childfd >= 0 { _ = ioctl(process.childfd, TIOCSWINSZ, &new) }
    }

    /// Hangs up, as closing a terminal window does (an interactive shell ignores SIGTERM), and
    /// makes sure, a second later, that it's gone.
    func terminate() {
        let pid = process.shellPid
        guard pid > 0 else { return }
        kill(pid, SIGHUP)
        queue.asyncAfter(deadline: .now() + 1) { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
    }

    // MARK: LocalProcessDelegate (on `queue`)

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        flush()
        let ended = self.ended
        Task { @MainActor in ended() }
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        pending.withLock { $0.append(contentsOf: slice) }
        let first = flushScheduled.withLock { scheduled in
            defer { scheduled = true }
            return !scheduled
        }
        if first { queue.asyncAfter(deadline: .now() + .milliseconds(30)) { [weak self] in self?.flush() } }
    }

    func getWindowSize() -> winsize { size.withLock { $0 } }

    private func flush() {
        flushScheduled.withLock { $0 = false }
        let data = pending.withLock { data in
            defer { data = Data() }
            return data
        }
        guard !data.isEmpty else { return }
        let output = self.output
        Task { @MainActor in output(data) }
    }
}

extension RemoteHost {
    var shellCount: Int { shells.count }

    func handleShell(_ message: ClientMessage, client: UUID, link: any RemoteLink) {
        switch message {
        case .openShell(let request, let projectID, let cols, let rows):
            let directory = projectID.flatMap { id in workspace.projects.first { $0.id == id }?.url }
                ?? FileManager.default.homeDirectoryForCurrentUser
            let id = UUID()
            let shell = RemoteShell(id: id, directory: directory, cols: max(cols, 10), rows: max(rows, 4), output: { [weak link] data in
                link?.send([.shellOutput(shellID: id, data: data)])
            }, ended: { [weak self, weak link] in
                guard self?.shells.removeValue(forKey: id) != nil else { return }
                link?.send([.shellEnded(shellID: id)])
            })
            shells[id] = (shell, client)
            shell.start()
            let path = directory.standardizedFileURL.path(percentEncoded: false)
            link.send([.shellOpened(requestID: request, shellID: id, directory: path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path)])
        case .shellInput(let id, let data):
            guard let entry = shells[id], entry.client == client else { return }
            entry.shell.send(data)
        case .shellResize(let id, let cols, let rows):
            guard let entry = shells[id], entry.client == client else { return }
            entry.shell.resize(cols: max(cols, 10), rows: max(rows, 4))
        case .closeShell(let id):
            guard let entry = shells[id], entry.client == client else { return }
            shells[id] = nil
            entry.shell.terminate()
            link.send([.shellEnded(shellID: id)])
        default:
            break
        }
    }

    /// A device left: its shells end.
    func endShells(of client: UUID) {
        for (id, entry) in shells where entry.client == client {
            shells[id] = nil
            entry.shell.terminate()
        }
    }
}
