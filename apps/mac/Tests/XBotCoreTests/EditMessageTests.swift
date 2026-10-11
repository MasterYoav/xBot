import Foundation
import Testing
import XBotBrain
@testable import XBotCore

/// Editing a prompt that was already sent, and sending it again: what Hermes and ChatGPT do.
@MainActor @Suite struct EditMessageTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "edit-\(UUID().uuidString)")

    func workspace(_ brain: SequenceBrain, store: Store = .inMemory()) async -> Workspace {
        let w = Workspace(store: store, inbox: inbox, discover: { [.claude: brain] })
        await w.refreshHarnesses()
        return w
    }

    func settle(_ w: Workspace, _ id: UUID) async { for _ in 0..<2000 where w.isRunning(id) { await Task.yield() } }

    func texts(_ w: Workspace, _ id: UUID) -> [String] {
        w.messages(in: id).map { $0.parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined() }
    }

    /// Two finished turns: "one" → "first answer", "two" → "second answer", session s1.
    func twoTurns(_ brain: SequenceBrain, store: Store = .inMemory()) async throws -> (Workspace, UUID) {
        let w = await workspace(brain, store: store)
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("one", in: chat.id); await settle(w, chat.id)
        _ = w.send("two", in: chat.id); await settle(w, chat.id)
        return (w, chat.id)
    }

    @Test func editingTheLastPromptReplacesItAndItsReply() async throws {
        let brain = SequenceBrain([
            [.session("s1"), .textDelta("first answer"), .done],
            [.session("s1"), .textDelta("second answer"), .done],
            [.session("s2"), .textDelta("better answer"), .done],
        ])
        let store = Store.inMemory()
        let (w, id) = try await twoTurns(brain, store: store)
        let second = try #require(w.messages(in: id).filter { $0.role == .user }.last)

        #expect(w.resend(second.id, as: "  two, but better  ", in: id))
        await settle(w, id)

        #expect(texts(w, id) == ["one", "first answer", "two, but better", "better answer"])
        // The library holds what the window shows, not the replaced turn as well.
        #expect(try store.messages(in: id).map(\.id) == w.messages(in: id).map(\.id))
        #expect(w.chat(id)?.sessionID == "s2")
    }

    /*
     The agent's own session remembers the turn being replaced. Resuming it would answer the edit
     with the old question and answer still in its context — so the edit starts a new session, and
     carries the conversation before it, which is all the agent should know.
     */
    @Test func anEditStartsAFreshSessionCarryingWhatCameBefore() async throws {
        let brain = SequenceBrain([
            [.session("s1"), .textDelta("first answer"), .done],
            [.session("s1"), .textDelta("second answer"), .done],
            [.done],
        ])
        let (w, id) = try await twoTurns(brain)
        let second = try #require(w.messages(in: id).filter { $0.role == .user }.last)

        _ = w.resend(second.id, as: "two, but better", in: id)
        await settle(w, id)

        let request = try #require(brain.requests.withLock { $0.last })
        #expect(request.resumeID == nil)
        #expect(request.prompt.contains("one"))
        #expect(request.prompt.contains("first answer"))
        #expect(request.prompt.hasSuffix("two, but better"))
        #expect(!request.prompt.contains("second answer"))
    }

    @Test func editingTheFirstPromptSendsJustTheEdit() async throws {
        let brain = SequenceBrain([
            [.session("s1"), .textDelta("first answer"), .done],
            [.session("s1"), .textDelta("second answer"), .done],
            [.done],
        ])
        let (w, id) = try await twoTurns(brain)
        let first = try #require(w.messages(in: id).first)

        _ = w.resend(first.id, as: "uno", in: id)
        await settle(w, id)

        #expect(brain.requests.withLock { $0.last?.prompt } == "uno")
        #expect(brain.requests.withLock { $0.last?.resumeID } == nil)
        #expect(texts(w, id) == ["uno"])
    }

    /// Destructive actions are undoable (CLAUDE.md): Undo stops the new turn and puts back the
    /// conversation, and the session, as they were.
    @Test func undoPutsTheConversationBack() async throws {
        let brain = SequenceBrain([
            [.session("s1"), .textDelta("first answer"), .done],
            [.session("s1"), .textDelta("second answer"), .done],
            [.session("s2"), .textDelta("better answer"), .done],
        ])
        let store = Store.inMemory()
        let (w, id) = try await twoTurns(brain, store: store)
        let before = w.messages(in: id)
        let second = try #require(before.filter { $0.role == .user }.last)

        _ = w.resend(second.id, as: "two, but better", in: id)
        await settle(w, id)
        #expect(w.toasts.current?.text == String(localized: "Message edited"))
        w.toasts.performAction()

        #expect(w.messages(in: id) == before)
        #expect(try store.messages(in: id).map(\.id) == before.map(\.id))
        #expect(w.chat(id)?.sessionID == "s1")
    }

    @Test func anEditIsRefusedWhileTheChatIsRunningOrWhenEmpty() async throws {
        let w = await workspace(SequenceBrain([[.session("s1"), .done]]))
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("one", in: chat.id); await settle(w, chat.id)
        let first = try #require(w.messages(in: chat.id).first)

        #expect(!w.resend(first.id, as: "   ", in: chat.id))
        #expect(!w.resend(UUID(), as: "nope", in: chat.id))
        // Only a person's own message can be edited.
        let reply = w.messages(in: chat.id).first { $0.role == .assistant }
        if let reply { #expect(!w.resend(reply.id, as: "nope", in: chat.id)) }
        #expect(texts(w, chat.id).first == "one")
    }
}
