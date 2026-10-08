import Foundation
import Testing
@testable import XBotCore

@MainActor @Suite struct PanelsTests {
    func workspace(_ brain: ScriptedBrain = ScriptedBrain([.done])) async -> Workspace {
        let w = Workspace(store: .inMemory(), inbox: FileManager.default.temporaryDirectory,
                          discover: { [.claude: brain] }, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await w.refreshHarnesses()
        return w
    }

    @Test func openingAChatOrGoingHomeLeavesTheProfile() async throws {
        let w = await workspace()
        w.page = .profile
        _ = try #require(w.newChat(in: nil))
        #expect(w.page == .main)
        w.page = .profile
        w.goHome()
        #expect(w.page == .main)
    }

    @Test func askToMergeSendsToTheOpenChat() async throws {
        let brain = ScriptedBrain([.done])
        let w = await workspace(brain)
        let chat = try #require(w.newChat(in: nil))
        w.askToMerge()
        for _ in 0..<200 where w.isRunning(chat.id) { await Task.yield() }
        #expect(brain.requests.withLock { $0.first?.prompt.contains("merge") } == true)
    }

    @Test func askToMergeOnHomeFillsTheDraft() async {
        let w = await workspace()
        w.askToMerge()
        #expect(w.draft.text.contains("merge"))
    }

    @Test func defaultsShapeTheNextDraftAndAreRemembered() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let w = Workspace(store: .inMemory(), inbox: FileManager.default.temporaryDirectory, discover: { [:] }, defaults: defaults)
        w.defaultMode = .readOnly
        w.defaultEffort = .high
        w.defaultHarness = .codex
        #expect(w.draft.mode == .readOnly && w.draft.effort == .high && w.draft.harness == .codex)
        let again = Workspace(store: .inMemory(), inbox: FileManager.default.temporaryDirectory, discover: { [:] }, defaults: defaults)
        #expect(again.draft.mode == .readOnly && again.draft.effort == .high && again.draft.harness == .codex)
    }

    @Test func aSentDraftStartsOverFromTheDefaults() async throws {
        let brain = ScriptedBrain([.done])
        let w = await workspace(brain)
        w.defaultMode = .readOnly
        w.draft.mode = .fullAccess
        w.draft.text = "go"
        #expect(w.sendDraft())
        #expect(w.draft.mode == .readOnly)
    }

    @Test func settingADefaultToWhatItIsLeavesTheDraftAlone() async {
        let w = await workspace()
        w.defaultHarness = .claude
        w.draft.model = "opus"
        w.draft.mode = .fullAccess
        w.defaultHarness = .claude
        w.defaultMode = w.defaultMode
        #expect(w.draft.model == "opus" && w.draft.mode == .fullAccess)
    }
}
