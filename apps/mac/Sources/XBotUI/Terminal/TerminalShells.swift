import AppKit
import SwiftTerm
import SwiftUI
import XBotCore

/// The live shells, one SwiftTerm view per terminal window, kept for the window's whole life so
/// hiding, switching tabs and showing again never restart a shell.
@MainActor
@Observable
final class TerminalShells {
    static let shared = TerminalShells()

    /// What each shell calls itself (its folder, or the program running in it).
    private(set) var titles: [UUID: String] = [:]
    @ObservationIgnored private var views: [UUID: LocalProcessTerminalView] = [:]
    @ObservationIgnored private var watchers: [UUID: Watcher] = [:]
    /// Windows already closed. A closing window can be drawn once more after it ended; that must
    /// not start a new shell nobody can see.
    @ObservationIgnored private var ended: Set<UUID> = []
    /// Ends a window whose shell exited on its own (`exit`, ⌃D).
    @ObservationIgnored var closeWindow: (UUID) -> Void = { _ in }

    func view(for window: TerminalWindow) -> LocalProcessTerminalView {
        if let view = views[window.id] { return view }
        let view = LocalProcessTerminalView(frame: CGRect(origin: .zero, size: window.size))
        if ended.contains(window.id) { return view }
        view.font = NSFont.monospacedSystemFont(ofSize: Metrics.terminalFont, weight: .regular)
        view.nativeBackgroundColor = NSColor(Palette.terminalBackground)
        view.nativeForegroundColor = NSColor(Palette.textPrimary)
        view.caretColor = NSColor(Palette.accent)
        view.optionAsMetaKey = false
        let watcher = Watcher(id: window.id, shells: self)
        view.processDelegate = watcher
        watchers[window.id] = watcher
        views[window.id] = view
        let shell = Self.loginShell
        view.startProcess(
            executable: shell, args: [], environment: Self.environment,
            execName: "-" + (shell as NSString).lastPathComponent,
            currentDirectory: window.directory.path
        )
        return view
    }

    /// The window was closed or its chat deleted: stop the shell, forget the view.
    func end(_ id: UUID) {
        ended.insert(id)
        if let view = views.removeValue(forKey: id) {
            view.processDelegate = nil
            // A hang-up, as when a terminal window closes: interactive shells ignore SwiftTerm's
            // SIGTERM, and on SIGHUP the shell also hangs up the jobs it started.
            let pid = view.process.shellPid
            if pid > 0 { kill(pid, SIGHUP) }
            view.terminate()
            view.removeFromSuperview()
        }
        watchers[id] = nil
        titles[id] = nil
    }

    fileprivate func setTitle(_ title: String, for id: UUID) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        titles[id] = trimmed.isEmpty ? nil : trimmed
    }

    fileprivate func exited(_ id: UUID) {
        guard views[id] != nil else { return }
        closeWindow(id)
    }

    /// The person's login shell, from the password database; zsh if that says nothing.
    static var loginShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    /// The app's environment, minus what only made sense for the app, plus what a terminal sets.
    static var environment: [String] {
        var env = ProcessInfo.processInfo.environment
        for key in ["CFFIXED_USER_HOME", "XPC_SERVICE_NAME", "__CFBundleIdentifier"] { env[key] = nil }
        for key in env.keys where key.hasPrefix("XBOT_") { env[key] = nil }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "xBot"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env.map { "\($0.key)=\($0.value)" }
    }

    /// SwiftTerm's delegate for one shell. Its calls arrive on the main thread.
    @MainActor
    private final class Watcher: @preconcurrency LocalProcessTerminalViewDelegate {
        let id: UUID
        weak var shells: TerminalShells?

        init(id: UUID, shells: TerminalShells) {
            self.id = id
            self.shells = shells
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            shells?.setTitle(title, for: id)
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            // After SwiftTerm finishes its own teardown of the view.
            let id = id
            Task { @MainActor [weak shells] in shells?.exited(id) }
        }
    }
}

/// SwiftTerm's view, the same instance every time it's shown. Takes the keyboard when its window
/// becomes the focused one, not on every redraw (that would pull typing away from the composer).
struct ShellView: NSViewRepresentable {
    let window: TerminalWindow
    var focused: Bool

    final class Coordinator { var wasFocused = false }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        update(container, context.coordinator)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        update(container, context.coordinator)
    }

    private func update(_ container: NSView, _ coordinator: Coordinator) {
        let shell = TerminalShells.shared.view(for: window)
        if shell.superview !== container {
            shell.removeFromSuperview()
            shell.frame = container.bounds
            shell.autoresizingMask = [.width, .height]
            container.addSubview(shell)
        }
        defer { coordinator.wasFocused = focused }
        guard focused, !coordinator.wasFocused else { return }
        DispatchQueue.main.async {
            if let host = shell.window, host.firstResponder !== shell { host.makeFirstResponder(shell) }
        }
    }
}
