import Foundation
import Testing
@testable import XBotCore

@MainActor @Suite struct TerminalDeckTests {
    let chat = UUID()
    let folder = URL(filePath: "/tmp")

    @Test func theFirstToggleOpensAWindowWithOneTab() {
        let deck = TerminalDeck()
        #expect(!deck.isShown(chat))
        deck.toggle(chat, in: folder)
        #expect(deck.isShown(chat))
        #expect(deck.tabs(in: chat).count == 1)
        #expect(deck.tabs(in: chat).first?.directory == folder)
        #expect(deck.panel(chat)?.selectedTabID == deck.tabs(in: chat).first?.id)
    }

    /// Hiding keeps the shells: showing again brings back the same tabs.
    @Test func theSecondToggleHidesAndKeepsTheTabs() {
        let deck = TerminalDeck()
        deck.toggle(chat, in: folder)
        deck.openTab(chat, in: folder)
        let tabs = deck.tabs(in: chat)
        deck.toggle(chat, in: folder)
        #expect(!deck.isShown(chat))
        #expect(deck.tabs(in: chat) == tabs)
        deck.toggle(chat, in: folder)
        #expect(deck.tabs(in: chat) == tabs)
    }

    @Test func aNewTabGoesAtTheEndAndIsSelected() {
        let deck = TerminalDeck()
        let a = deck.openTab(chat, in: folder)
        let b = deck.openTab(chat, in: folder)
        #expect(deck.tabs(in: chat).map(\.id) == [a.id, b.id])
        #expect(deck.panel(chat)?.selectedTabID == b.id)
        #expect(b.number == a.number + 1)
        deck.select(a.id)
        #expect(deck.panel(chat)?.selectedTabID == a.id)
    }

    /// Closing the selected tab selects its neighbour, as the main tabs do; the last one closing
    /// closes the window.
    @Test func closingSelectsANeighbourAndTheLastClosesTheWindow() {
        let deck = TerminalDeck()
        var ended: [UUID] = []
        deck.onEnd = { ended.append($0) }
        let a = deck.openTab(chat, in: folder)
        let b = deck.openTab(chat, in: folder)
        let c = deck.openTab(chat, in: folder)
        deck.select(b.id)
        deck.closeTab(b.id)
        #expect(deck.panel(chat)?.selectedTabID == c.id)
        deck.closeTab(c.id)
        #expect(deck.panel(chat)?.selectedTabID == a.id)
        deck.closeTab(a.id)
        #expect(ended == [b.id, c.id, a.id])
        #expect(!deck.isShown(chat) && deck.panel(chat) == nil)
        deck.toggle(chat, in: folder)
        #expect(deck.tabs(in: chat).count == 1)
    }

    @Test func tabsReorderByDrag() {
        let deck = TerminalDeck()
        let a = deck.openTab(chat, in: folder)
        let b = deck.openTab(chat, in: folder)
        let c = deck.openTab(chat, in: folder)
        deck.moveTab(c.id, to: 0)
        #expect(deck.tabs(in: chat).map(\.id) == [c.id, a.id, b.id])
        deck.moveTab(c.id, to: 99)
        #expect(deck.tabs(in: chat).map(\.id) == [a.id, b.id, c.id])
        #expect(deck.panel(chat)?.selectedTabID == c.id)
    }

    @Test func theWindowMovesAndResizesWithinLimits() {
        let deck = TerminalDeck()
        deck.toggle(chat, in: folder)
        deck.setFrame(chat, offset: CGSize(width: -120, height: 40), size: CGSize(width: 700, height: 420))
        #expect(deck.panel(chat)?.offset == CGSize(width: -120, height: 40))
        #expect(deck.panel(chat)?.size == CGSize(width: 700, height: 420))
        deck.setFrame(chat, offset: .zero, size: CGSize(width: 10, height: 10))
        #expect(deck.panel(chat)?.size == TerminalDeck.minimumSize)
    }

    @Test func aDeletedChatsTabsAreEnded() {
        let deck = TerminalDeck()
        var ended: [UUID] = []
        deck.onEnd = { ended.append($0) }
        let a = deck.openTab(chat, in: folder)
        let other = UUID()
        let b = deck.openTab(other, in: folder)
        deck.closeAll(chat)
        #expect(ended == [a.id])
        #expect(deck.tabs(in: other).map(\.id) == [b.id])
        #expect(!deck.isShown(chat))
    }

    @Test func chatsDontSeeEachOthersTerminals() {
        let deck = TerminalDeck()
        deck.toggle(chat, in: folder)
        let other = UUID()
        #expect(!deck.isShown(other) && deck.tabs(in: other).isEmpty)
    }

    @Test func theWorkspaceOpensTerminalsInTheChatsFolderAndEndsThemWithIt() async throws {
        let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: ScriptedBrain([.done])] })
        await w.refreshHarnesses()
        let project = w.addProject(at: FileManager.default.temporaryDirectory)
        let chat = try #require(w.newChat(in: project.id))
        w.toggleTerminals(in: chat.id)
        w.openTerminal(in: chat.id)
        #expect(w.terminals.tabs(in: chat.id).allSatisfy { $0.directory == project.url })
        var ended: [UUID] = []
        w.terminals.onEnd = { ended.append($0) }
        _ = w.deleteChat(chat.id)
        #expect(ended.count == 2)
    }
}
