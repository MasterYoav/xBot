import AppKit
import SwiftTerm
import SwiftUI
import XBotCore

/// An install or a sign-in, running where the person can see it: the command on top, a real
/// terminal under it (they can type if the CLI asks something), and Cancel. When it ends, xBot
/// looks for the CLI again and says how it went; a failure keeps the terminal's output on screen.
struct InstallSheet: View {
    let run: SetupRun
    let setup: AgentSetup
    let close: () -> Void
    @State private var terminal = InstallTerminal()
    @State private var phase = Phase.running

    enum Phase: Equatable {
        case running
        /// Waiting for xBot to look again.
        case checking
        case ended
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            header
            command
            InstallTerminalView(terminal: terminal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.terminalBackground)
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).strokeBorder(Palette.hairline))
            footer
        }
        .padding(Space.xl)
        .frame(width: Metrics.installSheet.width, height: Metrics.installSheet.height)
        .onAppear {
            terminal.onExit = { code in Task { @MainActor in await ended(code, cancelled: false) } }
            terminal.start(run)
        }
        .onDisappear {
            // Closed some other way while still running: stop it, and look again.
            guard phase == .running else { return }
            terminal.stop()
            Task { await setup.finished(run, exitCode: nil, cancelled: true) }
        }
    }

    private var title: String {
        switch run.purpose {
        case .install: String(localized: "Installing \(run.kind.displayName)")
        case .signIn: String(localized: "Signing in to \(run.kind.displayName)")
        }
    }

    private var subtitle: String {
        switch run.purpose {
        case .install: String(localized: "This is the official installer, run in a terminal so you can see what it does.")
        case .signIn: String(localized: "Your browser opens to sign in. Come back here when it's done.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: run.purpose == .install ? "arrow.down.app" : "person.badge.key")
                .font(Typography.title)
                .foregroundStyle(Palette.accent)
                .frame(width: Space.xxl + Space.xs, height: Space.xxl + Space.xs)
                .background(Palette.accentTint, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title).titleText()
                Text(subtitle).captionText().foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            IconButton("xmark", help: String(localized: "Close"), action: phase == .running ? cancel : close)
        }
    }

    private var command: some View {
        HStack(spacing: Space.s) {
            Text("$").font(Typography.mono).foregroundStyle(Palette.textTertiary)
            Text(run.command).font(Typography.mono).foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
        .accessibilityLabel(String(localized: "Command: \(run.command)"))
    }

    private var footer: some View {
        HStack(spacing: Space.s) {
            outcome
            Spacer()
            switch phase {
            case .running:
                Button(String(localized: "Cancel"), action: cancel)
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                if run.purpose == .signIn {
                    // A CLI whose sign-in is its own session (Antigravity) keeps running after it.
                    Button(String(localized: "I've signed in")) { signedIn() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            case .checking:
                ProgressView().controlSize(.small)
            case .ended:
                Button(String(localized: "Done"), action: close)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(minHeight: Metrics.chipHeight)
    }

    @ViewBuilder private var outcome: some View {
        if phase == .ended {
            switch setup.state(of: run.kind) {
            case .ready:
                Label(String(localized: "\(run.kind.displayName) is ready."), systemImage: "checkmark.circle.fill")
                    .captionText().foregroundStyle(Palette.success)
            case .installed:
                Label(String(localized: "Installed. Now sign in."), systemImage: "checkmark.circle")
                    .captionText().foregroundStyle(Palette.success)
            case .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .captionText().foregroundStyle(Palette.failure)
            default:
                EmptyView()
            }
        }
    }

    private func cancel() {
        phase = .ended
        terminal.stop()
        Task { await setup.finished(run, exitCode: nil, cancelled: true) }
        close()
    }

    private func signedIn() {
        phase = .checking
        terminal.stop()
        Task { await ended(nil, cancelled: false) }
    }

    private func ended(_ code: Int32?, cancelled: Bool) async {
        guard phase != .ended, setup.running?.id == run.id else { return }
        phase = .checking
        await setup.finished(run, exitCode: code, cancelled: cancelled)
        phase = .ended
    }
}

/// The sheet's one shell: the command, in the person's login shell, so their PATH and profile
/// apply as they would in Terminal.
@MainActor
final class InstallTerminal {
    let view = LocalProcessTerminalView(frame: CGRect(origin: .zero, size: Metrics.installSheet))
    var onExit: (Int32?) -> Void = { _ in }
    private var watcher: Watcher?
    private var started = false

    func start(_ run: SetupRun) {
        guard !started else { return }
        started = true
        view.font = NSFont.monospacedSystemFont(ofSize: Metrics.terminalFont, weight: .regular)
        view.nativeBackgroundColor = NSColor(Palette.terminalBackground)
        view.nativeForegroundColor = NSColor(Palette.textPrimary)
        view.caretColor = NSColor(Palette.accent)
        let watcher = Watcher { [weak self] code in self?.onExit(code) }
        self.watcher = watcher
        view.processDelegate = watcher
        let shell = TerminalShells.loginShell
        var environment = TerminalShells.environment.filter { !$0.hasPrefix("PATH=") }
        if !run.path.isEmpty { environment.append("PATH=\(run.path)") }
        view.startProcess(
            executable: shell, args: ["-l", "-c", run.shellCommand], environment: environment,
            execName: "-" + (shell as NSString).lastPathComponent,
            currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    /// A hang-up, as when a terminal window closes, so the command's own children stop too.
    func stop() {
        let pid = view.process.shellPid
        if view.process.running, pid > 0 { kill(pid, SIGHUP) }
        view.processDelegate = nil
        watcher = nil
    }

    private final class Watcher: @preconcurrency LocalProcessTerminalViewDelegate {
        let ended: @MainActor (Int32?) -> Void
        init(ended: @escaping @MainActor (Int32?) -> Void) { self.ended = ended }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        @MainActor func processTerminated(source: TerminalView, exitCode: Int32?) { ended(exitCode) }
    }
}

private struct InstallTerminalView: NSViewRepresentable {
    let terminal: InstallTerminal

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let view = terminal.view
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
