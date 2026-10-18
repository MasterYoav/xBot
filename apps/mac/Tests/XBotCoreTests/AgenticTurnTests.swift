import Foundation
import Testing
import XBotTools
@testable import XBotCore

/// Turns with xBot's tools: which get them, and what comes with them.
@MainActor
@Suite struct AgenticTurnTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "agentic-\(UUID().uuidString)")

    func workspace(_ brain: ScriptedBrain, defaults: UserDefaults? = nil, store: Store = .inMemory()) async -> (Workspace, ToolHost) {
        let defaults = defaults ?? UserDefaults(suiteName: "agentic-\(UUID().uuidString)")!
        let w = Workspace(store: store, inbox: folder, discover: { [.claude: brain] }, defaults: defaults)
        await w.refreshHarnesses()
        let host = ToolHost(workspace: w, mac: FakeMac(), socketPath: "/tmp/x.sock",
                            executable: URL(filePath: "/Applications/xBot.app/Contents/MacOS/XBot"),
                            imagesFolder: folder, appearance: Appearance(defaults: defaults, folder: folder),
                            antigravity: AntigravityMCP(defaults: defaults))
        w.toolHost = host
        return (w, host)
    }

    func settle(_ w: Workspace) async {
        for _ in 0..<500 where w.isRunningAnyTurn { await Task.yield() }
    }

    @Test func aThreadTurnHasTheToolsFullAccessAndTheirGuidance() async throws {
        let brain = ScriptedBrain([.done])
        let (w, host) = await workspace(brain)
        let head = try #require(w.headMaster)
        let chat = try #require(w.talk(to: head.id))
        w.update(chat.id) { $0.isThread = true }
        #expect(w.send("Take a screenshot", in: chat.id))
        for _ in 0..<500 where brain.requests.withLock({ $0.isEmpty }) { await Task.yield() }
        let request = try #require(brain.requests.withLock { $0.last })
        let tools = try #require(request.tools)
        #expect(tools.executable.path == "/Applications/xBot.app/Contents/MacOS/XBot")
        #expect(tools.socketPath == "/tmp/x.sock")
        #expect(request.mode == .fullAccess)
        #expect(request.instructions?.hasPrefix("You are HeadMaster") == true, "who the agent is comes first")
        #expect(request.instructions?.contains("mac_ui") == true)
        #expect(request.instructions?.contains("xbot_ask") == true)
        // While it runs the token works; once it ends it's refused.
        await settle(w)
        let after = await host.handle(ToolCall(token: tools.token, tool: "xbot_crew", arguments: [:]))
        #expect(after.isError)
    }

    @Test func anOrdinaryChatHasNoToolsUnlessTheSettingIsOn() async throws {
        let brain = ScriptedBrain([.done])
        let (w, _) = await workspace(brain)
        let chat = try #require(w.newChat(in: nil))
        #expect(!w.toolsInEveryChat, "off by default")
        _ = w.send("one", in: chat.id)
        await settle(w)
        #expect(brain.requests.withLock { $0.last?.tools } == nil)
        w.toolsInEveryChat = true
        _ = w.send("two", in: chat.id)
        await settle(w)
        let request = try #require(brain.requests.withLock { $0.last })
        #expect(request.tools != nil)
        #expect(request.mode == .editFiles, "every chat gets the tools, not full access")
    }

    @Test func withoutAToolHostNothingIsAttached() async throws {
        let brain = ScriptedBrain([.done])
        let w = Workspace(store: .inMemory(), inbox: folder, discover: { [.claude: brain] })
        await w.refreshHarnesses()
        let chat = try #require(w.newChat(in: nil))
        w.update(chat.id) { $0.isThread = true }
        _ = w.send("hi", in: chat.id)
        await settle(w)
        #expect(brain.requests.withLock { $0.last?.tools } == nil)
    }

    @Test func anApprovalCardIsKeptInTheLibraryWithItsAnswer() async throws {
        let url = folder.appending(path: "library.sqlite")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let brain = ScriptedBrain([.done])
        let (w, _) = await workspace(brain, store: try Store(database: Database(url: url)))
        let chat = try #require(w.newChat(in: nil))
        let approval = ApprovalPart(agent: "Forge", summary: "Forge wants to quit Safari", detail: "mac_quit", risk: "quit")
        async let state = w.approvals.ask(approval, in: chat.id)
        for _ in 0..<500 where w.approvals.pending.isEmpty { await Task.yield() }
        w.answerApproval(approval.id, allow: true)
        #expect(await state == .allowed)
        let saved = try Store(database: Database(url: url)).messages(in: chat.id).flatMap(\.parts)
        guard case .approval(let card)? = saved.first else { Issue.record("no card saved"); return }
        #expect(card.state == .allowed)
        #expect(card.answeredBy == "Mac")
    }

    @Test func stoppingEndsAWaitingQuestion() async throws {
        let (w, _) = await workspace(ScriptedBrain([.textDelta("…")], hold: true))
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("go", in: chat.id)
        async let answer = w.questions.ask(in: chat.id, timeout: .seconds(30))
        for _ in 0..<500 where !w.isAsking(in: chat.id) { await Task.yield() }
        w.stop(chat.id)
        #expect(await answer == nil)
    }
}
