import Foundation
import Testing
import XBotBrain
@testable import XBotCore

/// "Let Jev choose" in the composer's agent menu: each message asks Jev for the CLI, model and
/// effort, from the message itself, before it runs.
@MainActor @Suite struct JevChoiceTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "jev-choice-\(UUID().uuidString)")

    func workspace(_ brains: [HarnessKind: any Brain], jev: ScriptedJev?, enabled: Bool = true) async -> Workspace {
        let defaults = freshDefaults()
        let settings = JevSettings(defaults: defaults, keys: MemoryJevKeys("k"))
        settings.workflowsEnabled = enabled
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { brains }, codexModels: { [] }, defaults: defaults,
                          jev: settings, jevDecider: jev)
        await w.refreshHarnesses()
        return w
    }

    func settle(_ w: Workspace, _ id: UUID) async {
        for _ in 0..<5000 where w.isRunning(id) { try? await Task.sleep(for: .milliseconds(2)) }
    }

    func codexPick(_ confidence: Double = 0.82) -> Result<JevResponse, JevError> {
        let options = JevPick.options(installed: [.claude, .codex], models: { $0 == .claude ? Workspace.claudeModels : [] })
        let key = options.first { $0.choice.harness == .codex }!.key
        return .success(JevResponse(model: "jev", answers: [
            "brain": .choice(key, probabilities: [:], confidence: confidence),
            "effort": .score(1, legend: [:], probabilities: [:], confidence: 0.7),
        ]))
    }

    @Test func eachMessageRunsOnWhatJevChose() async throws {
        let claude = SequenceBrain([], fallback: [.text("claude"), .done])
        let codex = SequenceBrain([], fallback: [.text("codex"), .done])
        let scripted = ScriptedJev([codexPick()])
        let w = await workspace([.claude: claude, .codex: codex], jev: scripted)
        let chat = try #require(w.newChat(in: nil))
        w.setJevChooses(true, for: chat.id)
        #expect(w.send("Rename foo to bar", in: chat.id))
        await settle(w, chat.id)
        #expect(claude.requests.withLock { $0.isEmpty })
        #expect(codex.requests.withLock { $0.first?.prompt } == "Rename foo to bar")
        #expect(codex.requests.withLock { $0.first?.effort } == .medium)
        #expect(w.chat(chat.id)?.harness == .codex)
        #expect(scripted.asked.withLock { $0.first?.state } == "Rename foo to bar")
        let reply = try #require(w.messages(in: chat.id).last)
        #expect(reply.parts.first == .notice("Jev chose Codex, medium effort (0.82)"))
        #expect(reply.parts.contains(.text("codex")))
    }

    @Test func theChoiceIsRememberedOnTheChat() async throws {
        let w = await workspace([.claude: SequenceBrain([], fallback: [.done])], jev: ScriptedJev([]))
        let chat = try #require(w.newChat(in: nil))
        w.setJevChooses(true, for: chat.id)
        #expect(w.chat(chat.id)?.jevChooses == true)
        // Picking an agent by hand turns it off.
        w.setHarness(.claude, for: chat.id)
        #expect(w.chat(chat.id)?.jevChooses == false)
    }

    @Test func offWhileTheToggleIsOff() async throws {
        let claude = SequenceBrain([], fallback: [.text("claude"), .done])
        let scripted = ScriptedJev([codexPick()])
        let w = await workspace([.claude: claude, .codex: SequenceBrain([], fallback: [.done])], jev: scripted, enabled: false)
        let chat = try #require(w.newChat(in: nil))
        w.setJevChooses(true, for: chat.id)
        #expect(!w.jevChoosesActive(chat.id))
        #expect(w.send("hi", in: chat.id))
        await settle(w, chat.id)
        #expect(scripted.calls == 0)
        #expect(claude.requests.withLock { $0.count } == 1)
    }

    @Test func whenJevCantBeReachedTheChatsOwnAgentAnswersAndSaysWhy() async throws {
        let claude = SequenceBrain([], fallback: [.text("claude"), .done])
        let w = await workspace([.claude: claude], jev: ScriptedJev([.failure(.timedOut)]))
        let chat = try #require(w.newChat(in: nil))
        w.setJevChooses(true, for: chat.id)
        #expect(w.send("hi", in: chat.id))
        await settle(w, chat.id)
        #expect(claude.requests.withLock { $0.count } == 1)
        let reply = try #require(w.messages(in: chat.id).last)
        guard case .notice(let notice) = reply.parts.first else { Issue.record("no notice"); return }
        #expect(notice.contains(JevError.timedOut.sentence))
    }

    @Test func theDraftCarriesItToTheNewChat() async throws {
        let codex = SequenceBrain([], fallback: [.text("codex"), .done])
        let w = await workspace([.claude: SequenceBrain([], fallback: [.done]), .codex: codex], jev: ScriptedJev([codexPick()]))
        w.draft.jevChooses = true
        w.draft.text = "Rename foo"
        #expect(w.sendDraft())
        let id = try #require(w.selectedChatID)
        #expect(w.chat(id)?.jevChooses == true)
        await settle(w, id)
        #expect(codex.requests.withLock { $0.count } == 1)
        #expect(w.draft.jevChooses == false)
    }
}
