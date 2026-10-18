import AppKit
import SwiftUI
import XBotBrain
import XBotCore
import XBotTools
import XBotUI

/// `XBot --automations-tick` (the background helper's LaunchAgent): run what's due, headless, and
/// quit. `XBot --mcp` (started by an agent CLI for a turn): the xbot MCP server over stdio.
/// `XBot --hook`: Claude Code's PreToolUse hook. Anything else: the app.
@main
enum XBotEntry {
    static func main() {
        // Headless and light: no SwiftUI app, no window, just the server or the hook.
        if CommandLine.arguments.contains(ToolEntry.mcpArgument) { ToolEntry.serve() }
        if CommandLine.arguments.contains(ToolEntry.hookArgument) { ToolEntry.hook() }
        guard CommandLine.arguments.contains(AutomationHelper.tickArgument) else {
            XBotApp.main()
            return
        }
        Task { @MainActor in
            await AutomationTick.run()
            exit(0)
        }
        dispatchMain()
    }
}

/// The xbot MCP server and Claude Code's hook, as the CLIs start them.
enum ToolEntry {
    static let mcpArgument = "--mcp"
    static let hookArgument = "--hook"

    /// Serves MCP on stdio until the CLI closes it, forwarding each call to the app.
    static func serve() -> Never {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let server = MCPServer(tools: ToolCatalog.all, forwarder: ToolClient.fromEnvironment(), version: version)
        Task {
            await MCPStdio.serve(server)
            exit(0)
        }
        dispatchMain()
    }

    /// Reads the hook event on stdin; exit 0 lets the tool run, exit 2 blocks it (stderr says why).
    static func hook() -> Never {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let client = ToolClient.fromEnvironment()
        Task {
            let decision = await ToolHook.decide(input, token: client.token) { call in await client.send(call) }
            if !decision.allow { FileHandle.standardError.write(Data((decision.reason + "\n").utf8)) }
            exit(decision.exitCode)
        }
        dispatchMain()
    }
}

@MainActor
enum AutomationTick {
    static func run() async {
        // The app runs them itself while it's open.
        let me = ProcessInfo.processInfo.processIdentifier
        let appOpen = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.xbot.app")
            .contains { $0.processIdentifier != me }
        guard !appOpen, let store = try? Store.live() else { return }
        let due = (try? store.automations())?.contains { $0.isDue(at: .now) } ?? false
        guard due else { return }
        let inbox = Store.supportDirectory.appending(path: "Inbox", directoryHint: .isDirectory)
        let workspace = Workspace(store: store, inbox: inbox, discover: { await HarnessLocator.installed() })
        await workspace.refreshHarnesses()
        workspace.runDueAutomations()
        await workspace.waitForTurns()
    }
}

struct XBotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let appUpdates = SparkleAppUpdateController()
    @State private var workspace = Self.makeWorkspace()

    init() {
        // Bound to the turns and scheduled once launch finishes (AppDelegate).
        AppDelegate.appUpdates = appUpdates
    }
    @AppStorage("inspectorShown") private var inspectorShown = false

    var body: some Scene {
        Window("xBot", id: "main") {
            RootView(workspace: workspace)
                .motionGate()
                .frame(minWidth: Metrics.minimumWindow.width, minHeight: Metrics.minimumWindow.height)
                .followsAppearanceSetting()
                .windowMovesOnlyFromDragAreas()
                .followsAppIconSetting()
        }
        .defaultSize(Metrics.defaultWindow)
        // Content runs to the top edge, the traffic lights float over the sidebar, and the top bar
        // is the drag area — the way the apps this one sits beside are built.
        .windowStyle(.hiddenTitleBar)
        // A compact title bar row with the traffic lights centred in it — the height of the tab strip.
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "About xBot")) { AboutPanel.show() }
            }
            CommandGroup(after: .appInfo) {
                Button(String(localized: "Check for Updates…")) { appUpdates.checkForUpdates(userInitiated: true) }
            }
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "New Chat")) { workspace.startDraft(in: nil) }
                    .keyboardShortcut("n", modifiers: .command)
                Button(String(localized: "Close Tab")) {
                    if let id = workspace.selectedChatID { workspace.close(id) }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(workspace.selectedChatID == nil)
            }
            CommandGroup(after: .sidebar) {
                Button(String(localized: "Files and Changes")) { inspectorShown.toggle() }
                    .keyboardShortcut("0", modifiers: [.command, .option])
            }
            CommandGroup(after: .windowArrangement) {
                ForEach(1...9, id: \.self) { number in
                    Button(String(localized: "Tab \(number)")) { workspace.openTab(at: number - 1) }
                        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                }
            }
            CommandGroup(after: .textEditing) {
                Button(String(localized: "Search Chats")) { workspace.requestSearchFocus() }
                    .keyboardShortcut("k", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button(String(localized: "Welcome Tour")) { workspace.onboarding?.reopen() }
                Button(String(localized: "xBot Documentation")) { NSWorkspace.shared.open(AboutPanel.documentationURL) }
            }
        }

        Settings {
            SettingsView(workspace: workspace)
        }
    }

    /// The library on disk, or — if it cannot be opened — one in memory with the reason on screen,
    /// so the app still works and says plainly that nothing will be kept.
    @MainActor
    private static func makeWorkspace() -> Workspace {
        let inbox = Store.supportDirectory.appending(path: "Inbox", directoryHint: .isDirectory)
        let discover: @Sendable () async -> [HarnessKind: any Brain] = { await HarnessLocator.installed() }
        let workspace: Workspace
        do {
            workspace = Workspace(store: try Store.live(), inbox: inbox, discover: discover, indexer: try? .live())
        } catch {
            workspace = Workspace(store: .inMemory(), inbox: inbox, discover: discover, indexer: try? .live())
            workspace.problem = String(
                localized: "xBot couldn't open its library, so this session won't be saved. \(String(describing: error))"
            )
        }
        AppDelegate.workspace = workspace
        // Read after the library: someone upgrading with chats or projects isn't sent through it.
        workspace.onboarding = OnboardingModel(hasLibrary: workspace.hasLibrary)
        workspace.startAutomationClock()
        var secrets: any PairingSecrets = KeychainPairingSecrets()
        #if DEBUG
        if let file = ProcessInfo.processInfo.environment["XBOT_PAIRING_SECRETS_FILE"] {
            secrets = FilePairingSecrets(url: URL(filePath: file))
        }
        #endif
        let remote = RemoteService(workspace: workspace, secrets: secrets)
        workspace.remote = remote
        remote.wantsPushes = { NSApplication.shared.registerForRemoteNotifications() }
        remote.host.drawAvatar = { AvatarPicture.png($0) }
        remote.start()
        startTools(for: workspace, remote: remote)
        return workspace
    }

    /// xBot's own tools for agents: the socket the CLIs' `XBot --mcp` reach the app on.
    @MainActor
    private static func startTools(for workspace: Workspace, remote: RemoteService) {
        guard let executable = Bundle.main.executableURL else { return }
        let host = ToolHost(workspace: workspace, mac: LiveMac(guide: { MacPermissionGuide.show($0) }), executable: executable)
        host.phoneAttached = { !remote.attached.isEmpty }
        // No phone to show the card: bring the chat with it forward and bounce the Dock icon.
        host.alertMac = { _, chatID in
            workspace.open(chatID)
            NSApp.requestUserAttention(.criticalRequest)
        }
        do {
            try host.start()
            workspace.toolHost = host
        } catch {
            // Turns run without xBot's tools; the agents still work.
            workspace.toasts.show(String(localized: "xBot's tools for agents couldn't start: \(String(describing: error))"))
        }
        #if DEBUG
        DebugAgenticTurn.startIfAsked(workspace)
        #endif
    }
}
