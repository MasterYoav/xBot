import Foundation
import Testing
import XBotBrain
import XBotRemote
@testable import XBotCore

/// A phone, as the host sees one: what it was sent, and a way to talk.
@MainActor final class FakeLink: RemoteLink {
    let id = UUID()
    let lane: RemoteLane
    var sent: [HostMessage] = []
    var onReceive: ((ClientMessage) -> Void)?
    var onClose: (() -> Void)?
    init(_ lane: RemoteLane = .local) { self.lane = lane }
    func send(_ messages: [HostMessage]) { sent += messages }
    func say(_ message: ClientMessage) { onReceive?(message) }
    func hangUp() { onClose?() }

    func replies() -> [(UUID, Bool, String?, UUID?)] {
        sent.compactMap { if case .reply(let r, let ok, let why, let chat) = $0 { (r, ok, why, chat) } else { nil } }
    }
}

@MainActor @Suite struct RemoteHostTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")

    func setUp(_ brains: [HarnessKind: any Brain] = [.claude: ScriptedBrain([.textDelta("hel"), .textDelta("lo"), .done])])
        async -> (Workspace, RemoteHost) {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { brains })
        await w.refreshHarnesses()
        let host = RemoteHost(workspace: w, macName: "Mac mini", macID: UUID(), localInterval: .milliseconds(20),
                              cloudInterval: .milliseconds(200))
        return (w, host)
    }

    /// Lets coalesced flushes and turns run.
    func pump(_ ms: Int = 120) async { try? await Task.sleep(for: .milliseconds(ms)) }

    /// Waits for `done` (up to 5 s): fixed sleeps are too short when the whole suite runs at once.
    func until(_ done: () -> Bool) async {
        let end = Date.now.addingTimeInterval(5)
        while !done(), Date.now < end { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aPhoneGetsHelloAndTheChatListOnConnect() async throws {
        let (w, host) = await setUp()
        let project = w.addProject(at: FileManager.default.temporaryDirectory)
        let chat = try #require(w.newChat(in: project.id))
        let link = FakeLink()
        host.attach(link)
        guard case .hello(let version, "Mac mini", _) = link.sent.first else { Issue.record("no hello"); return }
        #expect(version == Wire.version)
        guard case .workspace(let projects, let chats, let agents) = link.sent.dropFirst().first else { Issue.record("no list"); return }
        #expect(projects.map(\.id) == [project.id] && chats.map(\.id) == [chat.id])
        #expect(agents.map(\.id) == ["claude"] && chats.first?.agentName == "Claude Code")
    }

    @Test func automationRunsStayOffThePhonesList() async throws {
        let (w, host) = await setUp()
        var a = w.newAutomation()
        a.steps = [AutomationStep(app: .anything, text: "x")]
        w.saveAutomation(a)
        let run = try #require(w.runAutomation(a.id))
        let link = FakeLink()
        host.attach(link)
        guard case .workspace(_, let chats, _) = link.sent[1] else { return }
        #expect(!chats.contains { $0.id == run.id })
    }

    @Test func sendingFromThePhoneRunsATurnAndStreamsIt() async throws {
        let brain = ScriptedBrain([.textDelta("hel"), .textDelta("lo")], hold: true)
        let (w, host) = await setUp([.claude: brain])
        let chat = try #require(w.newChat(in: nil))
        let link = FakeLink()
        host.attach(link)
        link.say(.open(chatID: chat.id))
        let request = UUID()
        link.say(.send(requestID: request, chatID: chat.id, text: "say hello"))
        await until { link.sent.contains { if case .live(chat.id, [.text("hello")]) = $0 { true } else { false } } }
        #expect(link.replies().contains { $0.0 == request && $0.1 })
        #expect(brain.requests.withLock { $0.last?.prompt } == "say hello")
        // The person's message, then the live reply, coalesced into the whole of it so far.
        #expect(link.sent.contains { if case .message(chat.id, let m) = $0 { m.role == "user" } else { false } })
        let lives = link.sent.compactMap { if case .live(chat.id, let parts) = $0 { parts } else { nil } }
        #expect(lives.last == [.text("hello")])
        #expect(link.sent.contains { if case .chat(let c) = $0 { c.id == chat.id && c.isRunning } else { false } })
        // Stop from the phone: the turn ends, the reply is saved and the live one cleared.
        link.say(.stop(requestID: UUID(), chatID: chat.id))
        await until { link.sent.last { if case .live = $0 { true } else { false } } == .live(chatID: chat.id, parts: []) }
        #expect(!w.isRunning(chat.id))
        #expect(link.sent.contains { if case .message(chat.id, let m) = $0 { m.role == "assistant" } else { false } })
        #expect(lives.isEmpty == false && link.sent.last { if case .live = $0 { true } else { false } } == .live(chatID: chat.id, parts: []))
    }

    /// Ten quick deltas reach a local phone as a few live frames, not ten.
    @Test func liveTextIsCoalesced() async throws {
        let brain = ScriptedBrain((0..<10).map { _ in .textDelta("x") }, hold: true)
        let (w, host) = await setUp([.claude: brain])
        let chat = try #require(w.newChat(in: nil))
        let link = FakeLink()
        host.attach(link)
        link.say(.open(chatID: chat.id))
        link.say(.send(requestID: UUID(), chatID: chat.id, text: "go"))
        await until { link.sent.contains { if case .live(_, [.text("xxxxxxxxxx")]) = $0 { true } else { false } } }
        let lives = link.sent.compactMap { if case .live(_, let parts) = $0 { parts } else { nil } }
        #expect(lives.last == [.text("xxxxxxxxxx")])
        #expect(lives.count <= 3)
        w.stop(chat.id)
    }

    @Test func aChatNotOpenedOnThePhoneSendsNoTranscript() async throws {
        let brain = ScriptedBrain([.textDelta("hi")], hold: true)
        let (w, host) = await setUp([.claude: brain])
        let chat = try #require(w.newChat(in: nil))
        let link = FakeLink()
        host.attach(link)
        _ = w.send("go", in: chat.id)
        await until { link.sent.contains { if case .chat(let c) = $0 { c.isRunning } else { false } } }
        await pump()
        #expect(!link.sent.contains { if case .live = $0 { true } else if case .message = $0 { true } else { false } })
        // The list still learns it's running.
        #expect(link.sent.contains { if case .chat(let c) = $0 { c.isRunning } else { false } })
        w.stop(chat.id)
    }

    @Test func openingAChatSendsItsTranscriptWithoutOpeningATabOnTheMac() async throws {
        let (w, host) = await setUp()
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("hi", in: chat.id)
        await until { !w.isRunning(chat.id) && w.messages(in: chat.id).count == 2 }
        w.close(chat.id)
        // As after a relaunch: not loaded.
        w.transcripts[chat.id] = nil
        let link = FakeLink()
        host.attach(link)
        link.say(.open(chatID: chat.id))
        guard case .transcript(chat.id, let messages) = link.sent.last else { Issue.record("no transcript"); return }
        #expect(messages.map(\.role) == ["user", "assistant"])
        #expect(messages.last?.parts == [.text("hello")])
        #expect(!w.openChatIDs.contains(chat.id))
    }

    @Test func aNewChatFromThePhoneUsesItsSettings() async throws {
        let codex = ScriptedBrain([.done])
        let (w, host) = await setUp([.claude: ScriptedBrain([.done]), .codex: codex])
        let link = FakeLink()
        host.attach(link)
        let request = UUID()
        link.say(.newChat(requestID: request, projectID: nil, text: "start",
                          settings: RemoteChatSettings(agent: "codex", model: Choice("gpt-5"), mode: "readOnly", effort: Choice("low"))))
        await until { link.replies().contains { $0.0 == request } && codex.requests.withLock { !$0.isEmpty } }
        let reply = try #require(link.replies().first { $0.0 == request })
        let chat = try #require(reply.3.flatMap(w.chat))
        #expect(reply.1 && chat.harness == .codex && chat.model == "gpt-5" && chat.mode == .readOnly && chat.effort == .low)
        #expect(codex.requests.withLock { $0.last?.prompt } == "start")
        #expect(!w.openChatIDs.contains(chat.id))
    }

    @Test func settingsFromThePhoneAndTheirRefusals() async throws {
        let (w, host) = await setUp()
        let chat = try #require(w.newChat(in: nil))
        let link = FakeLink()
        host.attach(link)
        let ok = UUID(), bad = UUID(), missing = UUID()
        link.say(.setChat(requestID: ok, chatID: chat.id, settings: RemoteChatSettings(model: Choice("opus"), mode: "fullAccess", planMode: true)))
        link.say(.setChat(requestID: bad, chatID: chat.id, settings: RemoteChatSettings(agent: "codex")))
        link.say(.send(requestID: missing, chatID: UUID(), text: "x"))
        let replies = link.replies()
        #expect(replies.first { $0.0 == ok }?.1 == true)
        #expect(w.chat(chat.id)?.model == "opus" && w.chat(chat.id)?.mode == .fullAccess && w.chat(chat.id)?.planMode == true)
        #expect(replies.first { $0.0 == bad }?.1 == false && replies.first { $0.0 == bad }?.2?.contains("Codex") == true)
        #expect(replies.first { $0.0 == missing }?.1 == false)
        // Back to the default model.
        link.say(.setChat(requestID: UUID(), chatID: chat.id, settings: RemoteChatSettings(model: Choice(nil))))
        #expect(w.chat(chat.id)?.model == nil)
    }

    @Test func editAndResendFromThePhone() async throws {
        let brain = ScriptedBrain([.textDelta("ok"), .done])
        let (w, host) = await setUp([.claude: brain])
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("first", in: chat.id)
        await until { !w.isRunning(chat.id) && w.messages(in: chat.id).count == 2 }
        let first = try #require(w.messages(in: chat.id).first)
        let link = FakeLink()
        host.attach(link)
        link.say(.open(chatID: chat.id))
        link.say(.edit(requestID: UUID(), chatID: chat.id, messageID: first.id, text: "second"))
        await until { link.sent.contains(.messageRemoved(chatID: chat.id, messageID: first.id)) }
        #expect(w.messages(in: chat.id).first?.parts == [.text("second")])
        #expect(link.sent.contains(.messageRemoved(chatID: chat.id, messageID: first.id)))
    }

    @Test func aPlanIsApprovedFromThePhone() async throws {
        let brain = SequenceBrain([[.structured(planJSON(["Read it", "Say it"])), .done]], fallback: [.structured(stepJSON()), .done])
        let (w, host) = await setUp([.claude: brain])
        let chat = try #require(w.newChat(in: nil))
        w.setPlanMode(true, for: chat.id)
        let link = FakeLink()
        host.attach(link)
        link.say(.open(chatID: chat.id))
        link.say(.send(requestID: UUID(), chatID: chat.id, text: "do it"))
        await until { w.latestPlan(in: chat.id)?.plan.status == .review && link.sent.contains { if case .message(_, let m) = $0 { m.parts.contains { if case .plan(let p) = $0 { p.status == "review" } else { false } } } else { false } } }
        let (messageID, drafted) = try #require(w.latestPlan(in: chat.id))
        #expect(drafted.status == .review)
        #expect(link.sent.contains { if case .message(_, let m) = $0 { m.parts.contains { if case .plan(let p) = $0 { p.status == "review" && p.steps.count == 2 } else { false } } } else { false } })
        link.say(.runPlan(requestID: UUID(), chatID: chat.id, messageID: messageID))
        await until { w.latestPlan(in: chat.id)?.plan.startedAt != nil }
        #expect(w.latestPlan(in: chat.id)?.plan.startedAt != nil)
    }

    /// No phone: the host watches nothing, so the Mac pays nothing for the feature.
    @Test func withNoPhoneTheHostDoesNoWork() async throws {
        let (w, host) = await setUp()
        #expect(!host.isWatching)
        let link = FakeLink()
        host.attach(link)
        #expect(host.isWatching)
        link.hangUp()
        #expect(!host.isWatching)
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("hi", in: chat.id)
        await pump()
        #expect(host.flushes == 0 || link.sent.allSatisfy { if case .chat(let c) = $0 { c.id != chat.id } else { true } })
    }

    /// Through iCloud, sends are spaced out (1 a second in the app) so a streaming reply is a few
    /// record writes, not hundreds.
    @Test func aCloudPhoneIsSentLessOften() async throws {
        let brain = ScriptedBrain([], hold: true)
        let (w, host) = await setUp([.claude: brain])
        let chat = try #require(w.newChat(in: nil))
        let cloud = FakeLink(.cloud), local = FakeLink(.local)
        host.attach(cloud)
        host.attach(local)
        cloud.say(.open(chatID: chat.id))
        local.say(.open(chatID: chat.id))
        _ = w.send("go", in: chat.id)
        for i in 0..<10 {
            w.receive(.textDelta("\(i)"), in: chat.id, turn: try #require(w.turns[chat.id]?.token))
            await pump(25)
        }
        await until { cloud.sent.last { if case .live = $0 { true } else { false } } == .live(chatID: chat.id, parts: [.text("0123456789")]) }
        let count = { (l: FakeLink) in l.sent.filter { if case .live = $0 { true } else { false } }.count }
        #expect(count(cloud) < count(local))
        #expect(cloud.sent.last { if case .live = $0 { true } else { false } } == .live(chatID: chat.id, parts: [.text("0123456789")]))
        w.stop(chat.id)
    }

    @Test func attachedPhonesKeepTheMacAwakeAndSoDoTurns() async throws {
        let brain = ScriptedBrain([], hold: true)
        let (w, host) = await setUp([.claude: brain])
        var awake: [Bool] = []
        host.keepAwake = { awake.append($0) }
        let link = FakeLink()
        host.attach(link)
        #expect(awake.last == true)
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("go", in: chat.id)
        link.hangUp()
        await until { w.isRunning(chat.id) }
        #expect(awake.last == true)   // a turn is still running
        w.stop(chat.id)
        host.refreshAwake()
        #expect(awake.last == false)
    }
}
