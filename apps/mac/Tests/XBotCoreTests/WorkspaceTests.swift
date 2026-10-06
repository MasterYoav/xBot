import Foundation
import Synchronization
import Testing
import XBotBrain
@testable import XBotCore

/// Plays a script. With `hold`, it never ends the turn on its own.
final class ScriptedBrain: Brain {
    let script: [BrainEvent]
    let hold: Bool
    let requests = Mutex<[TurnRequest]>([])

    init(_ script: [BrainEvent], hold: Bool = false) {
        self.script = script
        self.hold = hold
    }

    func run(_ request: TurnRequest) -> AsyncStream<BrainEvent> {
        requests.withLock { $0.append(request) }
        let (stream, continuation) = AsyncStream.makeStream(of: BrainEvent.self)
        for event in script { continuation.yield(event) }
        if !hold { continuation.finish() }
        return stream
    }
}

@MainActor @Suite struct WorkspaceTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")

    func workspace(_ brain: ScriptedBrain) async -> Workspace {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: brain] })
        await w.refreshHarnesses()
        return w
    }

    func settle(_ w: Workspace, _ id: UUID) async {
        for _ in 0..<200 where w.isRunning(id) { await Task.yield() }
    }

    @Test func aTurnIsStreamedThenSaved() async throws {
        let brain = ScriptedBrain([.session("s1"), .textDelta("Hel"), .textDelta("lo"), .done])
        let w = await workspace(brain)
        let chat = try #require(w.newChat(in: nil))
        #expect(w.send("Say hello to the team", in: chat.id))
        await settle(w, chat.id)

        #expect(w.messages(in: chat.id).map(\.parts) == [[.text("Say hello to the team")], [.text("Hello")]])
        #expect(w.chat(chat.id)?.sessionID == "s1")
        #expect(w.chat(chat.id)?.title == "Say hello to the team")
        #expect(w.live[chat.id] == nil)
    }

    @Test func theNextTurnResumesTheSession() async throws {
        let brain = ScriptedBrain([.session("s1"), .done])
        let w = await workspace(brain)
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("one", in: chat.id); await settle(w, chat.id)
        _ = w.send("two", in: chat.id); await settle(w, chat.id)
        #expect(brain.requests.withLock { $0.map(\.resumeID) } == [nil, "s1"])
    }

    @Test func sendingWhileRunningIsRefused() async throws {
        let w = await workspace(ScriptedBrain([.textDelta("…")], hold: true))
        let chat = try #require(w.newChat(in: nil))
        #expect(w.send("first", in: chat.id))
        #expect(!w.send("second", in: chat.id))
        #expect(w.messages(in: chat.id).count == 1)
        w.stop(chat.id)
    }

    @Test func stopKeepsThePartialReply() async throws {
        let w = await workspace(ScriptedBrain([.textDelta("Half an ans")], hold: true))
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("go", in: chat.id)
        for _ in 0..<50 { await Task.yield() }
        w.stop(chat.id)
        #expect(!w.isRunning(chat.id))
        let reply = try #require(w.messages(in: chat.id).last)
        #expect(reply.role == .assistant)
        #expect(reply.parts == [.text("Half an ans"), .notice(String(localized: "Stopped."))])
    }

    @Test func aFailureIsSavedInTheReply() async throws {
        let w = await workspace(ScriptedBrain([.failed("Not signed in to Claude Code.")]))
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("hi", in: chat.id); await settle(w, chat.id)
        #expect(w.messages(in: chat.id).last?.parts == [.failure("Not signed in to Claude Code.")])
    }

    @Test func switchingHarnessForgetsTheOldSession() async throws {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: {
            [.claude: ScriptedBrain([.session("s1"), .done]), .codex: ScriptedBrain([.done])]
        })
        await w.refreshHarnesses()
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("one", in: chat.id); await settle(w, chat.id)
        w.setHarness(.codex, for: chat.id)
        #expect(w.chat(chat.id)?.sessionID == nil)
        #expect(w.chat(chat.id)?.model == nil)
    }

    @Test func noHarnessMeansNoChat() async {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [:] })
        await w.refreshHarnesses()
        #expect(w.newChat(in: nil) == nil)
    }

    @Test func aProjectIsAddedOnce() async {
        let w = await workspace(ScriptedBrain([]))
        let a = w.addProject(at: URL(filePath: "/tmp/site"))
        let b = w.addProject(at: URL(filePath: "/tmp/site/"))
        #expect(a.id == b.id)
        #expect(w.projects.count == 1)
        #expect(a.name == "site")
    }

    @Test func projectChatsRunInTheProjectAndInboxChatsInTheInbox() async throws {
        let brain = ScriptedBrain([.done])
        let w = await workspace(brain)
        let project = w.addProject(at: FileManager.default.temporaryDirectory)
        let inProject = try #require(w.newChat(in: project.id))
        let loose = try #require(w.newChat(in: nil))
        _ = w.send("a", in: inProject.id); await settle(w, inProject.id)
        _ = w.send("b", in: loose.id); await settle(w, loose.id)
        #expect(brain.requests.withLock { $0.map(\.directory) } == [project.url, inbox])
        #expect(FileManager.default.fileExists(atPath: inbox.path))
    }

    @Test func titlesAreTheFirstLineShortened() {
        #expect(Workspace.title(from: "  Fix the login bug\nmore detail") == "Fix the login bug")
        #expect(Workspace.title(from: String(repeating: "word ", count: 30)).count <= 49)
    }
}
