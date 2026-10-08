import Foundation
import Testing
import XBotBrain
@testable import XBotCore

@MainActor @Suite struct EffortSettingsTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "effort-\(UUID().uuidString)")
    let codexModels = [
        ModelOption(id: "gpt-6-luna", name: "GPT-6-Luna", efforts: [.low, .medium, .high, .extra, .max], recommended: .medium),
        ModelOption(id: "gpt-6.1-sol", name: "GPT-6.1-Sol", efforts: Effort.allCases, recommended: .low),
    ]

    func workspace(_ brain: SequenceBrain, store: Store = .inMemory()) async -> Workspace {
        let models = codexModels
        let w = Workspace(store: store, inbox: inbox, discover: { [.claude: brain, .codex: brain] },
                          codexModels: { models })
        await w.refreshHarnesses()
        return w
    }

    func settle(_ w: Workspace, _ id: UUID) async { for _ in 0..<2000 where w.isRunning(id) { await Task.yield() } }

    @Test func aChatsEffortGoesWithEveryTurn() async throws {
        let brain = SequenceBrain([], fallback: [.done])
        let w = await workspace(brain)
        let chat = try #require(w.newChat(in: nil))
        w.setEffort(.extra, for: chat.id)
        _ = w.send("go", in: chat.id)
        await settle(w, chat.id)
        #expect(brain.requests.withLock { $0.last?.effort } == .extra)
    }

    @Test func planTurnsCarryTheEffortToo() async throws {
        let brain = SequenceBrain([[.structured(planJSON(["One"])), .done]], fallback: [.structured(stepJSON()), .done])
        let w = await workspace(brain)
        let chat = try #require(w.newChat(in: nil))
        w.setEffort(.high, for: chat.id)
        w.setPlanMode(true, for: chat.id)
        w.setReviewPlan(false, for: chat.id)
        _ = w.send("go", in: chat.id)
        await settle(w, chat.id)
        #expect(brain.requests.withLock { $0.map(\.effort) }.allSatisfy { $0 == .high })
    }

    @Test func codexGalaxyRunsOnAModelThatCanReasonThatFar() async throws {
        let brain = SequenceBrain([], fallback: [.done])
        let w = await workspace(brain)
        let chat = try #require(w.newChat(in: nil))
        w.setHarness(.codex, for: chat.id)
        w.setModel("gpt-6-luna", for: chat.id)
        w.setEffort(.galaxy, for: chat.id)
        _ = w.send("go", in: chat.id)
        await settle(w, chat.id)
        #expect(brain.requests.withLock { $0.last?.model } == "gpt-6.1-sol")
        #expect(w.chat(chat.id)?.model == "gpt-6-luna")
    }

    @Test func modelsAndRecommendationsPerAgent() async {
        let w = await workspace(SequenceBrain([], fallback: [.done]))
        #expect(w.models(for: .codex).map(\.id) == ["gpt-6-luna", "gpt-6.1-sol"])
        #expect(w.models(for: .claude).map(\.id) == ["opus", "sonnet", "haiku"])
        #expect(w.recommendedEffort(for: .codex, model: "gpt-6.1-sol") == .low)
        #expect(w.recommendedEffort(for: .codex, model: nil) == .medium)
        #expect(w.recommendedEffort(for: .claude, model: "opus") == .medium)
    }

    @Test func theDraftsEffortCarriesIntoItsChat() async throws {
        let w = await workspace(SequenceBrain([], fallback: [.done]))
        w.draft.effort = .max
        w.draft.text = "hi"
        #expect(w.sendDraft())
        #expect(w.chat(try #require(w.selectedChatID))?.effort == .max)
    }

    @Test func effortIsSavedAndALibraryWithoutItMigrates() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/x.sqlite")
        let id = UUID()
        do {
            let old = try Database(url: url)
            try old.execute("""
                CREATE TABLE chats (
                  id TEXT PRIMARY KEY, project_id TEXT, title TEXT NOT NULL, harness TEXT NOT NULL,
                  model TEXT, mode TEXT NOT NULL, session_id TEXT, created_at REAL NOT NULL,
                  updated_at REAL NOT NULL, plan_mode INTEGER NOT NULL DEFAULT 0,
                  review_plan INTEGER NOT NULL DEFAULT 1)
                """)
            try old.execute("PRAGMA user_version = 1")
            try old.execute("INSERT INTO chats (id, title, harness, mode, created_at, updated_at) VALUES (?, 'Old', 'claude', 'editFiles', 0, 0)",
                            [.text(id.uuidString)])
        }
        let store = try Store(database: Database(url: url))
        var chat = try #require(try store.chats().first)
        #expect(chat.id == id && chat.effort == nil)
        chat.effort = .galaxy
        try store.save(chat)
        #expect(try Store(database: Database(url: url)).chats().first?.effort == .galaxy)
    }
}
