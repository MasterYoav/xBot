import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import XBotBrain
@testable import XBotCore

/// A picture `width` × `height`, as a phone would send it (PNG here; the Mac takes any format).
func samplePicture(width: Int, height: Int) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

func pixelSize(of url: URL) -> (Int, Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
    return (width, height)
}

@MainActor @Suite struct ThreadStoreTests {
    @Test func theThreadFlagIsKept() throws {
        let store = Store.inMemory()
        var chat = Chat(projectID: nil, title: "HeadMaster", harness: .codex, mode: .fullAccess)
        chat.isThread = true
        try store.save(chat)
        try store.save(Chat(projectID: nil, title: "Plain", harness: .codex, mode: .editFiles))
        let saved = try store.chats()
        #expect(saved.first { $0.id == chat.id }?.isThread == true)
        #expect(saved.first { $0.title == "Plain" }?.isThread == false)
    }

    /// A library at schema 6 (before threads) gains the column; its chats aren't threads.
    @Test func aV6LibraryMigratesToV7() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/x.sqlite")
        let id = UUID()
        do {
            let old = try Database(url: url)
            try old.execute("""
                CREATE TABLE chats (
                  id TEXT PRIMARY KEY, project_id TEXT, title TEXT NOT NULL, harness TEXT NOT NULL,
                  model TEXT, mode TEXT NOT NULL, session_id TEXT, created_at REAL NOT NULL,
                  updated_at REAL NOT NULL, plan_mode INTEGER NOT NULL DEFAULT 0,
                  review_plan INTEGER NOT NULL DEFAULT 1, effort TEXT, agent_id TEXT, automation_id TEXT)
                """)
            try old.execute("""
                CREATE TABLE agents (
                  id TEXT PRIMARY KEY, name TEXT NOT NULL, role TEXT NOT NULL, instructions TEXT NOT NULL,
                  avatar TEXT NOT NULL, harness TEXT NOT NULL, model TEXT, project_id TEXT,
                  head_master INTEGER NOT NULL DEFAULT 0, sort_index INTEGER NOT NULL DEFAULT 0,
                  created_at REAL NOT NULL, manager_id TEXT)
                """)
            try old.execute("INSERT INTO chats (id, title, harness, mode, created_at, updated_at) VALUES (?, 'Old', 'claude', 'editFiles', 0, 0)",
                            [.text(id.uuidString)])
            try old.execute("PRAGMA user_version = 6")
        }
        let migrated = try Store(database: Database(url: url))
        let chat = try #require(try migrated.chats().first)
        #expect(chat.id == id && !chat.isThread)
        var thread = chat
        thread.isThread = true
        try migrated.save(thread)
        // Opening again doesn't add the column twice, and keeps the flag.
        let reopened = try Store(database: Database(url: url))
        #expect(try reopened.chats().first?.isThread == true)
    }
}

@MainActor @Suite struct ThreadTests {
    let support = FileManager.default.temporaryDirectory.appending(path: "support-\(UUID().uuidString)")
    var inbox: URL { support.appending(path: "Inbox") }

    func workspace(_ brains: [HarnessKind: any Brain]) async -> Workspace {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { brains })
        await w.refreshHarnesses()
        return w
    }

    func settle(_ w: Workspace, _ id: UUID?) async {
        guard let id else { return }
        for _ in 0..<400 where w.isRunning(id) { await Task.yield() }
    }

    /// HeadMaster, on Codex with a model.
    func headMaster(_ w: Workspace) throws -> Agent {
        var head = try #require(w.headMaster)
        head.harness = .codex
        head.model = "gpt-5.1-codex"
        w.saveAgent(head)
        return head
    }

    @Test func theFirstMessageStartsTheAgentsThread() async throws {
        let brain = ScriptedBrain([.session("s1"), .textDelta("pong"), .done])
        let w = await workspace([.codex: brain, .claude: ScriptedBrain([.done])])
        let head = try headMaster(w)
        #expect(w.thread(for: head.id) == nil)

        #expect(w.threadSend(head.id, text: "Reply with exactly the word: pong", images: []))
        let thread = try #require(w.thread(for: head.id))
        await settle(w, thread.id)

        #expect(thread.isThread && thread.agentID == head.id)
        #expect(thread.harness == .codex && thread.model == "gpt-5.1-codex")
        #expect(thread.mode == .fullAccess)
        #expect(thread.projectID == nil, "xBot's Inbox folder")
        #expect(thread.title == "HeadMaster")
        #expect(brain.requests.withLock { $0.last?.directory } == inbox)
        #expect(brain.requests.withLock { $0.last?.mode } == .fullAccess)
        #expect(w.messages(in: thread.id).map(\.parts) == [[.text("Reply with exactly the word: pong")], [.text("pong")]])
        // The Mac's window wasn't switched to it: the phone started it.
        #expect(w.selectedChatID != thread.id)
        #expect(w.threads.map(\.id) == [thread.id])
    }

    @Test func laterMessagesContinueTheSameThreadAndSession() async throws {
        let brain = ScriptedBrain([.session("s1"), .textDelta("ok"), .done])
        let w = await workspace([.codex: brain])
        let head = try headMaster(w)
        #expect(w.threadSend(head.id, text: "one", images: []))
        let first = try #require(w.thread(for: head.id))
        await settle(w, first.id)
        #expect(w.threadSend(head.id, text: "two", images: []))
        await settle(w, first.id)
        #expect(w.thread(for: head.id)?.id == first.id)
        #expect(w.chats.filter(\.isThread).count == 1)
        #expect(brain.requests.withLock { $0.last?.resumeID } == "s1")
    }

    @Test func aBusyThreadRefusesAndKeepsNothing() async throws {
        let brain = ScriptedBrain([.textDelta("…")], hold: true)
        let w = await workspace([.codex: brain])
        let head = try headMaster(w)
        #expect(w.threadSend(head.id, text: "one", images: []))
        let thread = try #require(w.thread(for: head.id))
        #expect(!w.threadSend(head.id, text: "two", images: [samplePicture(width: 10, height: 10)]))
        #expect(w.messages(in: thread.id).count == 1)
        let images = (try? FileManager.default.contentsOfDirectory(atPath: support.appending(path: "Images").path)) ?? []
        #expect(images.isEmpty, "a refused send leaves no pictures behind")
        w.stop(thread.id)
    }

    @Test func nothingToSayIsRefused() async throws {
        let w = await workspace([.codex: ScriptedBrain([.done])])
        let head = try headMaster(w)
        #expect(!w.threadSend(head.id, text: "  ", images: []))
        #expect(!w.threadSend(UUID(), text: "hi", images: []), "nobody by that id")
        #expect(w.thread(for: head.id) == nil)
    }

    @Test func aPhotoIsDownscaledSavedAndReferencedInThePrompt() async throws {
        let brain = ScriptedBrain([.textDelta("A blue square."), .done])
        let w = await workspace([.codex: brain])
        let head = try headMaster(w)
        #expect(w.threadSend(head.id, text: "What is this?", images: [samplePicture(width: 3200, height: 2000)]))
        let thread = try #require(w.thread(for: head.id))
        await settle(w, thread.id)

        let question = try #require(w.messages(in: thread.id).first)
        #expect(question.role == .user)
        guard question.parts.count == 2, case .text("What is this?") = question.parts[0], case .image(let image) = question.parts[1] else {
            Issue.record("expected the text and the picture, got \(question.parts)"); return
        }
        // Kept beside the library, as a JPEG no bigger than 1600 px.
        #expect(image.path == support.appending(path: "Images/\(image.id.uuidString).jpg").path)
        #expect(image.width == 1600 && image.height == 1000)
        let size = try #require(pixelSize(of: URL(filePath: image.path)))
        #expect(size == (1600, 1000))
        #expect(FileManager.default.contents(atPath: image.path)?.starts(with: [0xFF, 0xD8]) == true, "a JPEG")
        // And in the thread's folder, where the agent can open it, named in the prompt.
        let attachment = inbox.appending(path: "Attachments/\(image.id.uuidString).jpg")
        #expect(FileManager.default.fileExists(atPath: attachment.path))
        let prompt = try #require(brain.requests.withLock { $0.last?.prompt })
        #expect(prompt.hasPrefix("What is this?"))
        #expect(prompt.contains("Attached: \(attachment.path)"))
    }

    @Test func aPhotoAloneIsEnough() async throws {
        let brain = ScriptedBrain([.done])
        let w = await workspace([.codex: brain])
        let head = try headMaster(w)
        #expect(w.threadSend(head.id, text: "", images: [samplePicture(width: 40, height: 30)]))
        let thread = try #require(w.thread(for: head.id))
        await settle(w, thread.id)
        let parts = w.messages(in: thread.id).first?.parts ?? []
        #expect(parts.count == 1)
        if case .image(let image) = parts.first { #expect(image.width == 40 && image.height == 30) } else { Issue.record("no picture") }
        #expect(brain.requests.withLock { $0.last?.prompt }?.hasPrefix("Attached: ") == true)
    }

    /// A session that can't be resumed (the agent moved to another CLI, or the old one lost it):
    /// the thread goes on in a new chat that starts with what was said lately.
    @Test func anUnresumableSessionContinuesInANewThread() async throws {
        let claude = ScriptedBrain([.session("c1"), .textDelta("Hello from Claude"), .done])
        let codex = ScriptedBrain([.session("x1"), .textDelta("Hello from Codex"), .done])
        let w = await workspace([.claude: claude, .codex: codex])
        var head = try #require(w.headMaster)
        head.harness = .claude
        w.saveAgent(head)
        #expect(w.threadSend(head.id, text: "Remember the word banana", images: []))
        let old = try #require(w.thread(for: head.id))
        await settle(w, old.id)

        head.harness = .codex
        w.saveAgent(head)
        #expect(w.threadSend(head.id, text: "Which word?", images: []))
        let new = try #require(w.thread(for: head.id))
        await settle(w, new.id)
        #expect(new.id != old.id && new.harness == .codex && new.isThread)
        #expect(w.chat(old.id)?.isThread == false, "the old chat stays, as a plain chat with the agent")
        #expect(w.chat(old.id)?.agentID == head.id)
        let request = try #require(codex.requests.withLock { $0.last })
        #expect(request.resumeID == nil)
        #expect(request.prompt.contains("Remember the word banana") && request.prompt.contains("Hello from Claude"))
        #expect(request.prompt.hasSuffix("Which word?"))
        // What the person sees in the new thread is only what they said.
        #expect(w.messages(in: new.id).first?.parts == [.text("Which word?")])
    }

    @Test func aLostSessionContinuesInANewThread() async throws {
        let brain = ScriptedBrain([.session("s1"), .textDelta("ok"), .done])
        let w = await workspace([.codex: brain])
        let head = try headMaster(w)
        #expect(w.threadSend(head.id, text: "first", images: []))
        let old = try #require(w.thread(for: head.id))
        await settle(w, old.id)
        // The CLI said it couldn't find the session.
        w.save(ChatMessage(chatID: old.id, role: .assistant, parts: [.failure("No conversation found with session ID: s1")]))
        #expect(w.threadSend(head.id, text: "second", images: []))
        let new = try #require(w.thread(for: head.id))
        #expect(new.id != old.id)
        await settle(w, new.id)
    }

    @Test func approvalCardsAreShownAndUpdatedInPlace() async throws {
        let w = await workspace([.codex: ScriptedBrain([.done])])
        let head = try headMaster(w)
        #expect(w.threadSend(head.id, text: "hi", images: []))
        let thread = try #require(w.thread(for: head.id))
        await settle(w, thread.id)
        var approval = ApprovalPart(agent: "HeadMaster", summary: "Quit Safari", detail: "mac_quit Safari", risk: "quit")
        w.showApproval(approval, in: thread.id)
        let count = w.messages(in: thread.id).count
        approval.state = .allowed
        approval.answeredBy = "iPhone"
        w.showApproval(approval, in: thread.id)
        #expect(w.messages(in: thread.id).count == count, "updated, not added")
        #expect(w.messages(in: thread.id).last?.parts == [.approval(approval)])
    }
}
