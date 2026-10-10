import Foundation
import Testing
@testable import XBotCore

@MainActor @Suite struct TerminalDeckTests {
    let chat = UUID()
    let folder = URL(filePath: "/tmp")

    @Test func theFirstToggleOpensOneAndShowsIt() {
        let deck = TerminalDeck()
        #expect(!deck.isShown(chat))
        deck.toggle(chat, in: folder)
        #expect(deck.isShown(chat))
        #expect(deck.windows(in: chat).count == 1)
        #expect(deck.windows(in: chat).first?.directory == folder)
    }

    /// Hiding keeps the shells: showing again brings back the same windows.
    @Test func theSecondToggleHidesAndKeepsThem() {
        let deck = TerminalDeck()
        deck.toggle(chat, in: folder)
        let first = deck.windows(in: chat)
        deck.toggle(chat, in: folder)
        #expect(!deck.isShown(chat))
        #expect(deck.windows(in: chat) == first)
        deck.toggle(chat, in: folder)
        #expect(deck.windows(in: chat) == first)
    }

    @Test func eachNewWindowCascadesFromTheLast() {
        let deck = TerminalDeck()
        let a = deck.open(chat, in: folder)
        let b = deck.open(chat, in: folder)
        #expect(b.offset.width < a.offset.width && b.offset.height > a.offset.height)
        #expect(deck.windows(in: chat).map(\.id) == [a.id, b.id])
        #expect(b.number == a.number + 1)
    }

    @Test func closingEndsItAndTheLastCloseHides() {
        let deck = TerminalDeck()
        var ended: [UUID] = []
        deck.onEnd = { ended.append($0) }
        let a = deck.open(chat, in: folder)
        let b = deck.open(chat, in: folder)
        deck.close(a.id)
        #expect(ended == [a.id] && deck.isShown(chat))
        deck.close(b.id)
        #expect(ended == [a.id, b.id])
        #expect(!deck.isShown(chat) && deck.windows(in: chat).isEmpty)
        deck.toggle(chat, in: folder)
        #expect(deck.windows(in: chat).count == 1)
    }

    @Test func raisingBringsAWindowToTheFront() {
        let deck = TerminalDeck()
        let a = deck.open(chat, in: folder)
        let b = deck.open(chat, in: folder)
        deck.raise(a.id)
        #expect(deck.windows(in: chat).map(\.id) == [b.id, a.id])
    }

    @Test func movesAndResizesAreKeptWithinLimits() {
        let deck = TerminalDeck()
        let a = deck.open(chat, in: folder)
        deck.move(a.id, to: CGSize(width: -120, height: 40))
        #expect(deck.window(a.id)?.offset == CGSize(width: -120, height: 40))
        deck.resize(a.id, to: CGSize(width: 10, height: 10))
        #expect(deck.window(a.id)?.size == TerminalDeck.minimumSize)
    }

    @Test func aDeletedChatsWindowsAreEnded() {
        let deck = TerminalDeck()
        var ended: [UUID] = []
        deck.onEnd = { ended.append($0) }
        let a = deck.open(chat, in: folder)
        let other = UUID()
        let b = deck.open(other, in: folder)
        deck.closeAll(chat)
        #expect(ended == [a.id])
        #expect(deck.windows(in: other).map(\.id) == [b.id])
        #expect(!deck.isShown(chat))
    }

    @Test func chatsDontSeeEachOthersWindows() {
        let deck = TerminalDeck()
        deck.toggle(chat, in: folder)
        let other = UUID()
        #expect(!deck.isShown(other) && deck.windows(in: other).isEmpty)
    }

    @Test func theWorkspaceOpensTerminalsInTheChatsFolderAndEndsThemWithIt() async throws {
        let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: ScriptedBrain([.done])] })
        await w.refreshHarnesses()
        let project = w.addProject(at: FileManager.default.temporaryDirectory)
        let chat = try #require(w.newChat(in: project.id))
        w.toggleTerminals(in: chat.id)
        #expect(w.terminals.windows(in: chat.id).first?.directory == project.url)
        var ended: [UUID] = []
        w.terminals.onEnd = { ended.append($0) }
        _ = w.deleteChat(chat.id)
        #expect(ended.count == 1)
    }
}
