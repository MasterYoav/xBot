import AppKit
import SwiftUI
import XBotBrain
import XBotCore
import XBotUI

@main
struct XBotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let appUpdates = SparkleAppUpdateController()
    @State private var workspace = Self.makeWorkspace()

    var body: some Scene {
        Window("xBot", id: "main") {
            RootView(workspace: workspace)
                .frame(minWidth: Metrics.minimumWindow.width, minHeight: Metrics.minimumWindow.height)
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
                Button(String(localized: "xBot Documentation")) { NSWorkspace.shared.open(AboutPanel.documentationURL) }
            }
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
        return workspace
    }
}
