import Foundation
import Testing
import XBotBrain
import XBotRemote
@testable import XBotCore

/// Agentic Mode from a phone: talking in an agent's thread (with photos) and answering approvals.
@MainActor @Suite struct RemoteHostAgenticTests {
    let support = FileManager.default.temporaryDirectory.appending(path: "support-\(UUID().uuidString)")

    func setUp(_ brains: [HarnessKind: any Brain]) async -> (Workspace, RemoteHost) {
        let w = Workspace(store: .inMemory(), inbox: support.appending(path: "Inbox"), discover: { brains })
        await w.refreshHarnesses()
        let host = RemoteHost(workspace: w, macName: "Mac mini", macID: UUID(), localInterval: .milliseconds(20),
                              cloudInterval: .milliseconds(200))
        return (w, host)
    }

    func until(_ done: () -> Bool) async {
        let end = Date.now.addingTimeInterval(30)
        while !done(), Date.now < end { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func threadSendStartsTheThreadSavesThePhotoAndSaysWhichChat() async throws {
        let brain = ScriptedBrain([.textDelta("A blue picture."), .done])
        let (w, host) = await setUp([.claude: brain])
        let head = try #require(w.headMaster)
        let link = FakeLink()
        host.attach(link)
        let request = UUID()
        link.say(.threadSend(requestID: request, memberID: head.id, text: "What's this?", images: [samplePicture(width: 2400, height: 1800)]))
        await until { link.replies().contains { $0.0 == request } }
        let reply = try #require(link.replies().first { $0.0 == request })
        let thread = try #require(w.thread(for: head.id))
        #expect(reply.1 && reply.3 == thread.id)
        #expect(thread.isThread && thread.mode == .fullAccess)
        // The picture: on disk beside the library, downscaled, and on the person's message.
        let question = try #require(w.messages(in: thread.id).first)
        guard case .image(let image) = question.parts.last else { Issue.record("no picture"); return }
        #expect(FileManager.default.fileExists(atPath: image.path))
        #expect(max(image.width, image.height) == 1600)
        await until { brain.requests.withLock { !$0.isEmpty } }
        #expect(brain.requests.withLock { $0.last?.prompt }?.contains("Attached: ") == true)

        // The phone's list learns it's a thread, and whose.
        await until { link.sent.contains { if case .chat(let c) = $0 { c.id == thread.id && c.thread == true } else { false } } }
        let listed = link.sent.compactMap { if case .chat(let c) = $0, c.id == thread.id { c } else { nil } }.last
        #expect(listed?.agentID == head.id && listed?.thread == true)
        await until { !w.isRunning(thread.id) }
        // Opened, the picture travels with the message.
        link.say(.open(chatID: thread.id))
        let transcript = link.sent.compactMap { if case .transcript(thread.id, let m) = $0 { m } else { nil } }.last
        guard case .image(let sent)? = transcript?.first?.parts.last else { Issue.record("no picture on the wire"); return }
        #expect(sent.jpeg?.isEmpty == false && sent.width == image.width)
    }

    @Test func aThreadsListRowCarriesTheLastMessage() async throws {
        let (w, host) = await setUp([.claude: ScriptedBrain([.textDelta("pong"), .done])])
        let head = try #require(w.headMaster)
        #expect(w.threadSend(head.id, text: "ping", images: []))
        let thread = try #require(w.thread(for: head.id))
        await until { !w.isRunning(thread.id) }
        let link = FakeLink()
        host.attach(link)
        guard case .workspace(_, let chats, _) = link.sent[1] else { Issue.record("no list"); return }
        #expect(chats.first { $0.id == thread.id }?.preview == "pong")
    }

    @Test func threadSendToSomeoneWhoLeftIsRefused() async throws {
        let (_, host) = await setUp([.claude: ScriptedBrain([.done])])
        let link = FakeLink()
        host.attach(link)
        let request = UUID()
        link.say(.threadSend(requestID: request, memberID: UUID(), text: "hi", images: []))
        await until { link.replies().contains { $0.0 == request } }
        let reply = try #require(link.replies().first { $0.0 == request })
        #expect(!reply.1 && reply.2 != nil)
    }

    @Test func aBusyThreadSaysSo() async throws {
        let brain = ScriptedBrain([.textDelta("…")], hold: true)
        let (w, host) = await setUp([.claude: brain])
        let head = try #require(w.headMaster)
        #expect(w.threadSend(head.id, text: "one", images: []))
        let link = FakeLink()
        host.attach(link)
        let request = UUID()
        link.say(.threadSend(requestID: request, memberID: head.id, text: "two", images: []))
        await until { link.replies().contains { $0.0 == request } }
        #expect(link.replies().first { $0.0 == request }?.2 == "It's still answering.")
        if let id = w.thread(for: head.id)?.id { w.stop(id) }
    }

    @Test func answerApprovalResolvesThePendingAsk() async throws {
        let (w, host) = await setUp([.claude: ScriptedBrain([.done])])
        let link = FakeLink()
        host.attach(link)
        var updated: [ApprovalPart] = []
        w.approvals.update = { approval, _ in updated.append(approval) }
        let approval = ApprovalPart(agent: "HeadMaster", summary: "Quit Safari", detail: "mac_quit Safari", risk: "quit")
        let chatID = UUID()
        async let answer = w.approvals.ask(approval, in: chatID)
        await until { !w.approvals.pending.isEmpty }
        let request = UUID()
        link.say(.answerApproval(requestID: request, approvalID: approval.id, allow: true))
        #expect(await answer == .allowed)
        await until { link.replies().contains { $0.0 == request } }
        #expect(link.replies().first { $0.0 == request }?.1 == true)
        #expect(updated.last?.answeredBy == "iPhone", "the phone's name, or iPhone when it gave none")

        // Answering again: refused, with a reason.
        let again = UUID()
        link.say(.answerApproval(requestID: again, approvalID: approval.id, allow: false))
        await until { link.replies().contains { $0.0 == again } }
        let refused = try #require(link.replies().first { $0.0 == again })
        #expect(!refused.1 && refused.2 != nil)
    }

    @Test func anApprovalIsAnsweredInTheDevicesName() async throws {
        let (w, host) = await setUp([.claude: ScriptedBrain([.done])])
        let link = FakeLink()
        link.deviceName = "Yoav's iPhone"
        host.attach(link)
        var updated: [ApprovalPart] = []
        w.approvals.update = { approval, _ in updated.append(approval) }
        let approval = ApprovalPart(agent: "Forge", summary: "git push", detail: "git push origin main", risk: "push")
        async let answer = w.approvals.ask(approval, in: UUID())
        await until { !w.approvals.pending.isEmpty }
        link.say(.answerApproval(requestID: UUID(), approvalID: approval.id, allow: false))
        #expect(await answer == .refused)
        #expect(updated.last?.answeredBy == "Yoav's iPhone")
    }
}
