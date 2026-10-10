import CoreGraphics
import Foundation
import Observation

/// One floating terminal window: a shell in a chat's folder.
public struct TerminalWindow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let chatID: UUID
    /// 1, 2, 3… within its chat, for its title until the shell names itself.
    public let number: Int
    public let directory: URL
    /// From the window's home spot (the chat's top-right corner), as dragged.
    public var offset: CGSize
    public var size: CGSize
}

/// The chats' terminal windows: which exist, where they are, and whether each chat shows them.
/// The shells themselves live in the UI; `onEnd` tells it when one should stop.
@MainActor
@Observable
public final class TerminalDeck {
    public static let defaultSize = CGSize(width: 560, height: 340)
    public static let minimumSize = CGSize(width: 320, height: 180)
    /// How far each new window sits from the last: down and to the left, title bars staggered.
    static let cascade = CGSize(width: -28, height: 32)

    /// Per chat, back to front.
    private var stacks: [UUID: [TerminalWindow]] = [:]
    private var shown: Set<UUID> = []
    private var counters: [UUID: Int] = [:]
    /// A window was closed, or its chat went: end its shell.
    @ObservationIgnored public var onEnd: (UUID) -> Void = { _ in }

    public init() {}

    public func isShown(_ chatID: UUID) -> Bool { shown.contains(chatID) }

    public func windows(in chatID: UUID) -> [TerminalWindow] { stacks[chatID] ?? [] }

    public func window(_ id: UUID) -> TerminalWindow? {
        stacks.values.lazy.compactMap { $0.first { $0.id == id } }.first
    }

    /// Shows the chat's terminals, opening the first if it has none; hides them if shown.
    public func toggle(_ chatID: UUID, in directory: URL) {
        if shown.contains(chatID) {
            shown.remove(chatID)
        } else {
            if windows(in: chatID).isEmpty { open(chatID, in: directory) }
            shown.insert(chatID)
        }
    }

    /// A new window in front, cascaded from the frontmost; the chat's terminals are shown.
    @discardableResult
    public func open(_ chatID: UUID, in directory: URL) -> TerminalWindow {
        let last = windows(in: chatID).last
        let number = (counters[chatID] ?? 0) + 1
        counters[chatID] = number
        let offset = last.map { CGSize(width: $0.offset.width + Self.cascade.width, height: $0.offset.height + Self.cascade.height) }
            ?? .zero
        let window = TerminalWindow(id: UUID(), chatID: chatID, number: number, directory: directory,
                                    offset: offset, size: last?.size ?? Self.defaultSize)
        stacks[chatID, default: []].append(window)
        shown.insert(chatID)
        return window
    }

    /// Ends the window's shell. The last one closing hides the chat's terminals.
    public func close(_ id: UUID) {
        guard let window = window(id) else { return }
        stacks[window.chatID]?.removeAll { $0.id == id }
        if windows(in: window.chatID).isEmpty {
            stacks[window.chatID] = nil
            shown.remove(window.chatID)
        }
        onEnd(id)
    }

    /// The chat is gone: end all its shells.
    public func closeAll(_ chatID: UUID) {
        let ids = windows(in: chatID).map(\.id)
        stacks[chatID] = nil
        shown.remove(chatID)
        counters[chatID] = nil
        ids.forEach(onEnd)
    }

    public func raise(_ id: UUID) {
        guard let window = window(id), var stack = stacks[window.chatID], stack.last?.id != id else { return }
        stack.removeAll { $0.id == id }
        stack.append(window)
        stacks[window.chatID] = stack
    }

    public func move(_ id: UUID, to offset: CGSize) {
        change(id) { $0.offset = offset }
    }

    public func resize(_ id: UUID, to size: CGSize) {
        change(id) {
            $0.size = CGSize(width: max(size.width, Self.minimumSize.width), height: max(size.height, Self.minimumSize.height))
        }
    }

    private func change(_ id: UUID, _ edit: (inout TerminalWindow) -> Void) {
        guard let window = window(id), let index = stacks[window.chatID]?.firstIndex(where: { $0.id == id }) else { return }
        edit(&stacks[window.chatID]![index])
    }
}

extension Workspace {
    /// The chat's terminals: shown (the first opened in its folder) or hidden again.
    public func toggleTerminals(in chatID: UUID) {
        guard let chat = chat(chatID) else { return }
        terminals.toggle(chatID, in: directory(for: chat))
    }

    /// Another terminal for the chat, in its folder.
    public func openTerminal(in chatID: UUID) {
        guard let chat = chat(chatID) else { return }
        terminals.open(chatID, in: directory(for: chat))
    }
}
