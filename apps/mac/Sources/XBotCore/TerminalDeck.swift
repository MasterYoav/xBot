import CoreGraphics
import Foundation
import Observation

/// One shell in a chat's terminal window.
public struct TerminalTab: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let chatID: UUID
    /// 1, 2, 3… within its chat, for its title until the shell names itself.
    public let number: Int
    public let directory: URL
}

/// A chat's terminal window: its tabs, which is in front, and where it floats.
public struct TerminalPanel: Equatable, Sendable {
    public var tabs: [TerminalTab] = []
    public var selectedTabID: UUID?
    /// From the window's home spot (the chat's top-right corner), as dragged.
    public var offset: CGSize = .zero
    public var size: CGSize = TerminalDeck.defaultSize
}

/// The chats' terminal windows: one per chat, with tabs; whether each chat shows its window.
/// The shells themselves live in the UI; `onEnd` tells it when one should stop.
@MainActor
@Observable
public final class TerminalDeck {
    public nonisolated static let defaultSize = CGSize(width: 600, height: 360)
    public nonisolated static let minimumSize = CGSize(width: 340, height: 200)

    private var panels: [UUID: TerminalPanel] = [:]
    private var shown: Set<UUID> = []
    private var counters: [UUID: Int] = [:]
    /// A tab was closed, or its chat went: end its shell.
    @ObservationIgnored public var onEnd: (UUID) -> Void = { _ in }
    /// Type a command into a tab's shell and press Return.
    @ObservationIgnored public var onRun: (UUID, String) -> Void = { _, _ in }
    /// Whether a tab's shell is running something (not at its prompt).
    @ObservationIgnored public var isBusy: (UUID) -> Bool = { _ in false }

    public init() {}

    public func isShown(_ chatID: UUID) -> Bool { shown.contains(chatID) }

    public func panel(_ chatID: UUID) -> TerminalPanel? { panels[chatID] }

    public func tabs(in chatID: UUID) -> [TerminalTab] { panels[chatID]?.tabs ?? [] }

    public func tab(_ id: UUID) -> TerminalTab? {
        panels.values.lazy.compactMap { $0.tabs.first { $0.id == id } }.first
    }

    /// Shows the chat's terminal window, opening it with one tab if it has none; hides it if shown.
    public func toggle(_ chatID: UUID, in directory: URL) {
        if shown.contains(chatID) {
            shown.remove(chatID)
        } else {
            if tabs(in: chatID).isEmpty { openTab(chatID, in: directory) }
            shown.insert(chatID)
        }
    }

    /// Shows the chat's terminal if it has one; leaves it alone if it doesn't.
    public func showTerminal(_ chatID: UUID) {
        if panels[chatID] != nil { shown.insert(chatID) }
    }

    /// A new tab at the end, selected; the window is shown.
    @discardableResult
    public func openTab(_ chatID: UUID, in directory: URL) -> TerminalTab {
        let number = (counters[chatID] ?? 0) + 1
        counters[chatID] = number
        let tab = TerminalTab(id: UUID(), chatID: chatID, number: number, directory: directory)
        panels[chatID, default: TerminalPanel()].tabs.append(tab)
        panels[chatID]?.selectedTabID = tab.id
        shown.insert(chatID)
        return tab
    }

    public func select(_ id: UUID) {
        guard let tab = tab(id) else { return }
        panels[tab.chatID]?.selectedTabID = id
    }

    /// Ends the tab's shell. The selected one closing selects the tab after it (else before), as
    /// the main tabs do; the last one closing closes the window.
    public func closeTab(_ id: UUID) {
        guard let tab = tab(id), var panel = panels[tab.chatID],
              let index = panel.tabs.firstIndex(where: { $0.id == id }) else { return }
        panel.tabs.remove(at: index)
        if panel.tabs.isEmpty {
            panels[tab.chatID] = nil
            shown.remove(tab.chatID)
        } else {
            if panel.selectedTabID == id { panel.selectedTabID = panel.tabs[min(index, panel.tabs.count - 1)].id }
            panels[tab.chatID] = panel
        }
        onEnd(id)
    }

    /// The chat is gone: end all its shells.
    public func closeAll(_ chatID: UUID) {
        let ids = tabs(in: chatID).map(\.id)
        panels[chatID] = nil
        shown.remove(chatID)
        counters[chatID] = nil
        ids.forEach(onEnd)
    }

    /// Moves a tab to `index` among its window's tabs (clamped to the ends).
    public func moveTab(_ id: UUID, to index: Int) {
        guard let tab = tab(id), var tabs = panels[tab.chatID]?.tabs,
              let from = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: from)
        tabs.insert(tab, at: min(max(index, 0), tabs.count))
        panels[tab.chatID]?.tabs = tabs
    }

    /// Where the window floats and how big it is, as dragged or resized.
    public func setFrame(_ chatID: UUID, offset: CGSize, size: CGSize) {
        guard panels[chatID] != nil else { return }
        panels[chatID]?.offset = offset
        panels[chatID]?.size = CGSize(width: max(size.width, Self.minimumSize.width),
                                      height: max(size.height, Self.minimumSize.height))
    }
}

extension Workspace {
    /// The chat's terminal window: shown (with a first tab in its folder) or hidden again.
    public func toggleTerminals(in chatID: UUID) {
        guard let chat = chat(chatID) else { return }
        terminals.toggle(chatID, in: directory(for: chat))
    }

    /// Another tab in the chat's terminal window, in its folder.
    public func openTerminal(in chatID: UUID) {
        guard let chat = chat(chatID) else { return }
        terminals.openTab(chatID, in: directory(for: chat))
    }
}
