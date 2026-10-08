import Foundation
import Testing
import XBotBrain
@testable import XBotCore

@MainActor @Suite struct HomeTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "home-\(UUID().uuidString)")

    func workspace(_ brain: SequenceBrain = SequenceBrain([], fallback: [.done]), store: Store = .inMemory()) async -> Workspace {
        let w = Workspace(store: store, inbox: inbox, discover: { [.claude: brain, .codex: SequenceBrain([], fallback: [.done])] })
        await w.refreshHarnesses()
        return w
    }

    func settle(_ w: Workspace, _ id: UUID) async { for _ in 0..<2000 where w.isRunning(id) { await Task.yield() } }

    @Test func homeIsWhereNothingIsSelected() async throws {
        let w = await workspace()
        #expect(w.isHome)
        let chat = try #require(w.newChat(in: nil))
        #expect(!w.isHome)
        w.goHome()
        #expect(w.isHome && w.openChatIDs == [chat.id])
    }

    @Test func aDraftBecomesAChatWithItsSettingsAndIsSent() async throws {
        let brain = SequenceBrain([[.textDelta("hi"), .done]])
        let w = await workspace(brain)
        let project = w.addProject(at: FileManager.default.temporaryDirectory)
        w.startDraft(in: project.id)
        w.draft.harness = .claude
        w.draft.model = "opus"
        w.draft.mode = .readOnly
        w.draft.text = "  Explain this  "
        #expect(w.sendDraft())
        let id = try #require(w.selectedChatID)
        let chat = try #require(w.chat(id))
        #expect(chat.projectID == project.id && chat.model == "opus" && chat.mode == .readOnly)
        #expect(w.draft.text.isEmpty)
        await settle(w, id)
        #expect(w.messages(in: id).first?.parts == [.text("Explain this")])
    }

    @Test func anEmptyDraftDoesNotSend() async {
        let w = await workspace()
        w.draft.text = "   "
        #expect(!w.sendDraft())
        #expect(w.chats.isEmpty && w.isHome)
    }

    @Test func aDraftForARemovedProjectGoesToTheInbox() async throws {
        let w = await workspace()
        let project = w.addProject(at: URL(filePath: "/tmp/gone"))
        w.startDraft(in: project.id)
        w.removeProject(project.id)
        w.draft.text = "hi"
        #expect(w.sendDraft())
        #expect(w.chat(try #require(w.selectedChatID))?.projectID == nil)
    }

    @Test func aSuggestionFillsTheDraftAndMayTurnOnPlan() async {
        let w = await workspace()
        w.use(.explain)
        #expect(w.draft.text == Suggestion.explain.prompt && !w.draft.planMode)
        w.use(.plan)
        #expect(w.draft.planMode)
        #expect(w.composerFocusRequest == 2)
    }

    @Test func workedForRunsFromTheQuestionToTheReply() async throws {
        let w = await workspace(SequenceBrain([[.textDelta("ok"), .done]]))
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("go", in: chat.id)
        await settle(w, chat.id)
        let reply = try #require(w.messages(in: chat.id).last)
        let duration = try #require(w.workedFor(reply.id, in: chat.id))
        #expect(duration >= 0 && duration < 5)
        #expect(w.workedFor(w.messages(in: chat.id)[0].id, in: chat.id) == nil)
    }

    @Test func retryAsksTheLastQuestionAgain() async throws {
        let brain = SequenceBrain([[.failed("limit")], [.textDelta("ok"), .done]])
        let w = await workspace(brain)
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("Summarise", in: chat.id)
        await settle(w, chat.id)
        #expect(w.retryLast(in: chat.id))
        await settle(w, chat.id)
        #expect(brain.requests.withLock { $0.map(\.prompt) } == ["Summarise", "Summarise"])
    }

    @Test func deletingAChatOffersUndoWhichBringsItBack() async throws {
        let store = Store.inMemory()
        let w = await workspace(SequenceBrain([[.textDelta("ok"), .done]]), store: store)
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("keep me", in: chat.id)
        await settle(w, chat.id)
        w.deleteChatWithUndo(chat.id)
        #expect(w.chat(chat.id) == nil)
        #expect(w.toasts.current?.text == String(localized: "Chat deleted"))
        w.toasts.performAction()
        #expect(w.chat(chat.id) != nil)
        #expect(w.messages(in: chat.id).count == 2)
        #expect(try store.messages(in: chat.id).count == 2)
    }

    @Test func undoAfterTheProjectIsGoneRestoresToTheInbox() async throws {
        let w = await workspace()
        let project = w.addProject(at: URL(filePath: "/tmp/p"))
        let chat = try #require(w.newChat(in: project.id))
        let deleted = try #require(w.deleteChat(chat.id))
        w.removeProject(project.id)
        w.restoreChat(deleted)
        #expect(w.chat(chat.id)?.projectID == nil)
    }

    @Test func aFinishedPlanSaysSo() async throws {
        let brain = SequenceBrain([[.structured(planJSON(["One", "Two"])), .done]],
                                  fallback: [.structured(stepJSON()), .done])
        let w = await workspace(brain)
        let chat = try #require(w.newChat(in: nil))
        w.setPlanMode(true, for: chat.id)
        w.setReviewPlan(false, for: chat.id)
        _ = w.send("Go", in: chat.id)
        await settle(w, chat.id)
        #expect(w.toasts.current?.text == String(localized: "Plan finished · 2 steps"))
    }

    @Test func branchesFromWorktreesAndDetachedHeads() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repo = root.appending(path: "repo"), tree = root.appending(path: "tree"), plain = root.appending(path: "plain")
        for dir in [repo.appending(path: ".git"), root.appending(path: "gitdirs/tree"), tree, plain] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try "ref: refs/heads/main\n".write(to: repo.appending(path: ".git/HEAD"), atomically: true, encoding: .utf8)
        try "gitdir: \(root.path)/gitdirs/tree\n".write(to: tree.appending(path: ".git"), atomically: true, encoding: .utf8)
        try "ref: refs/heads/feature/plan\n".write(to: root.appending(path: "gitdirs/tree/HEAD"), atomically: true, encoding: .utf8)
        #expect(GitBranch.current(in: repo) == "main")
        #expect(GitBranch.current(in: tree) == "feature/plan")
        #expect(GitBranch.current(in: plain) == nil)
        try "0123abcd\n".write(to: repo.appending(path: ".git/HEAD"), atomically: true, encoding: .utf8)
        #expect(GitBranch.current(in: repo) == nil)
    }

    @Test func toolsFoldTogetherInAReply() {
        let a = ToolPart(id: "a", name: "Read", summary: "x", output: "1", isError: false)
        let b = ToolPart(id: "b", name: "Bash", summary: "y", output: "", isError: false)
        let segments = ReplyLayout.segments([.text("Look"), .tool(a), .tool(b), .text("Done"), .failure("boom")])
        #expect(segments == [.text("Look"), .tools([a, b]), .text("Done"), .failure("boom")])
    }

    /// ⌘1…⌘9: the tab in that place, if there is one.
    @Test func numberedTabsOpenByPosition() async throws {
        let w = await workspace()
        let a = try #require(w.newChat(in: nil)), b = try #require(w.newChat(in: nil))
        w.openTab(at: 0)
        #expect(w.selectedChatID == a.id)
        w.openTab(at: 1)
        #expect(w.selectedChatID == b.id)
        w.openTab(at: 5)
        #expect(w.selectedChatID == b.id)
    }
}
