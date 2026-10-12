import SwiftTerm
import SwiftUI
import XBotRemote

/// A terminal on the Mac: a login shell in a project's folder (or home), drawn by SwiftTerm here.
struct TerminalScreen: View {
    let client: RemoteClient
    @State var projectID: UUID?
    @State private var session = ShellSession()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea(edges: .bottom)
            ShellView(session: session)
                .padding(.horizontal, 4)
            if session.ended {
                VStack(spacing: 12) {
                    Text(String(localized: "The shell ended.")).foregroundStyle(.white)
                    Button(String(localized: "Start a new one")) { Task { await start() } }.buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 18).fill(.black.opacity(0.75)))
            } else if !session.started {
                ProgressView().tint(.white)
            }
        }
        .navigationTitle(session.directory.map { ($0 as NSString).lastPathComponent } ?? String(localized: "Terminal"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(String(localized: "Folder"), selection: $projectID) {
                        Text(String(localized: "Home")).tag(UUID?.none)
                        ForEach(client.projects) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    Divider()
                    Button { Task { await start() } } label: { Label(String(localized: "New shell"), systemImage: "plus.rectangle") }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel(String(localized: "Terminal actions"))
            }
        }
        .onChange(of: projectID) { Task { await start() } }
        .task { await start() }
        .onDisappear { session.close(client) }
    }

    private func start() async {
        session.close(client)
        await session.open(client, projectID: projectID)
    }
}

/// One shell: the SwiftTerm view and the Mac's process, joined through the client.
@MainActor @Observable
final class ShellSession {
    var id: UUID?
    var directory: String?
    var started = false
    var ended = false
    @ObservationIgnored let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
    @ObservationIgnored private var bridge: Bridge?
    @ObservationIgnored private weak var client: RemoteClient?

    /// Starts a shell in this session's view (a fresh screen each time).
    func open(_ client: RemoteClient, projectID: UUID?) async {
        self.client = client
        started = false
        ended = false
        view.getTerminal().resetToInitialState()
        view.feed(text: "")
        let bridge = Bridge(session: self)
        self.bridge = bridge
        view.terminalDelegate = bridge
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = UIColor(white: 0.92, alpha: 1)
        let terminal = view.getTerminal()
        client.earlyShellOutput = [:]
        guard case .shellOpened(_, let id, let directory) = await client.call({
            .openShell(requestID: $0, projectID: projectID, cols: max(terminal.cols, 20), rows: max(terminal.rows, 5))
        }) else {
            ended = true
            return
        }
        self.id = id
        self.directory = directory
        started = true
        client.shells[id] = (output: { [weak self] data in self?.view.feed(byteArray: ArraySlice([UInt8](data))) },
                             ended: { [weak self] in self?.ended = true })
        // Anything the shell said before the answer arrived.
        if let early = client.earlyShellOutput.removeValue(forKey: id) { view.feed(byteArray: ArraySlice([UInt8](early))) }
        focus()
        focus()
    }

    /// The keyboard comes up once the view is on screen.
    func focus() {
        Task { @MainActor in
            for _ in 0..<20 where view.window == nil { try? await Task.sleep(for: .milliseconds(50)) }
            _ = view.becomeFirstResponder()
        }
    }

    func close(_ client: RemoteClient) {
        guard let id else { return }
        client.shells[id] = nil
        client.post([.closeShell(shellID: id)])
        self.id = nil
    }

    fileprivate func send(_ data: ArraySlice<UInt8>) {
        guard let id, let client else { return }
        client.post([.shellInput(shellID: id, data: Data(data))])
    }

    fileprivate func resized(cols: Int, rows: Int) {
        guard let id, let client else { return }
        client.post([.shellResize(shellID: id, cols: cols, rows: rows)])
    }

    @MainActor private final class Bridge: @preconcurrency TerminalViewDelegate {
        weak var session: ShellSession?
        init(session: ShellSession) { self.session = session }

        func send(source: TerminalView, data: ArraySlice<UInt8>) { session?.send(data) }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { session?.resized(cols: newCols, rows: newRows) }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) { UIApplication.shared.open(url) }
        }
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {
            UIPasteboard.general.string = String(decoding: content, as: UTF8.self)
        }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

private struct ShellView: UIViewRepresentable {
    let session: ShellSession
    func makeUIView(context: Context) -> TerminalView {
        session.view.accessibilityIdentifier = "terminal"
        return session.view
    }
    func updateUIView(_ view: TerminalView, context: Context) {}
}
