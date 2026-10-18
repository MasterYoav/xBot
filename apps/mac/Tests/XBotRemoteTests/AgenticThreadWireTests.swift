import Foundation
import Testing
@testable import XBotRemote

/// Agentic Mode's wire: threads, photos sent from the phone, approvals answered there, and what
/// the phone's chat list and thread derive from messages.
@Suite struct AgenticThreadWireTests {
    func roundTrip<M: Codable & Equatable>(_ message: M) throws -> M {
        try Wire.decoder.decode(M.self, from: Wire.encoder.encode(message))
    }

    @Test func threadSendAndAnswerApprovalSurviveTheWire() throws {
        let messages: [ClientMessage] = [
            .threadSend(requestID: UUID(), memberID: UUID(), text: "What's on my screen?", images: [Data([0xFF, 0xD8, 0xFF, 0xE0])]),
            .threadSend(requestID: UUID(), memberID: UUID(), text: "", images: []),
            .answerApproval(requestID: UUID(), approvalID: UUID(), allow: true),
            .answerApproval(requestID: UUID(), approvalID: UUID(), allow: false),
        ]
        for message in messages { #expect(try roundTrip(message) == message) }
    }

    @Test func aChatSaysWhetherItsAThreadAndWhoItsWith() throws {
        let agent = UUID()
        let chat = RemoteChat(id: UUID(), title: "HeadMaster", projectID: nil, agent: "codex", agentName: "Codex", model: nil,
                              mode: "fullAccess", effort: nil, planMode: false, crewName: "HeadMaster",
                              updatedAt: Date(timeIntervalSince1970: 1_800_000_000), isRunning: false, blocked: nil,
                              thread: true, agentID: agent, preview: "pong")
        let back = try roundTrip(chat)
        #expect(back == chat)
        #expect(back.thread == true && back.agentID == agent && back.preview == "pong")
    }

    /// An older Mac sends chats without the new fields: they decode as not a thread.
    @Test func aChatFromAnOlderMacIsNotAThread() throws {
        let json = #"{"id":"6F1C9C65-6C0C-4F09-8C1F-2D1B7E0B0A11","title":"t","agent":"claude","agentName":"Claude Code","mode":"editFiles","planMode":false,"updatedAt":1000,"isRunning":false}"#
        let chat = try Wire.decoder.decode(RemoteChat.self, from: Data(json.utf8))
        #expect(chat.thread == nil && chat.agentID == nil && chat.preview == nil)
        #expect(!chat.isThread)
    }

    // MARK: What the phone derives

    func chat(_ agent: UUID?, thread: Bool?, updated: TimeInterval) -> RemoteChat {
        RemoteChat(id: UUID(), title: "t", projectID: nil, agent: "codex", agentName: "Codex", model: nil, mode: "fullAccess",
                   effort: nil, planMode: false, crewName: nil, updatedAt: Date(timeIntervalSince1970: updated), isRunning: false,
                   blocked: nil, thread: thread, agentID: agent)
    }

    @Test func threadsAreKeyedByAgentNewestFirst() {
        let a = UUID(), b = UUID()
        let old = chat(a, thread: true, updated: 10), new = chat(a, thread: true, updated: 20)
        let plain = chat(a, thread: false, updated: 30), other = chat(b, thread: true, updated: 5)
        let threads = AgenticDigest.threads(in: [old, plain, new, other, chat(nil, thread: true, updated: 1)])
        #expect(threads[a]?.id == new.id)
        #expect(threads[b]?.id == other.id)
        #expect(threads.count == 2)
    }

    @Test func theActivityLineIsTheLatestToolRow() {
        func tool(_ label: String, _ summary: String, done: Bool) -> RemotePart {
            .tool(RemoteTool(id: UUID().uuidString, label: label, summary: summary, isDone: done, isError: false, size: nil))
        }
        #expect(AgenticDigest.activity(in: []) == nil)
        #expect(AgenticDigest.activity(in: [.text("Let me look")]) == nil)
        #expect(AgenticDigest.activity(in: [tool("Read", "a.txt", done: true), tool("Running", "swift test", done: false)])
                == "Running swift test…")
        #expect(AgenticDigest.activity(in: [tool("Read", "a.txt", done: true), .text("Hmm")]) == "Read a.txt")
        #expect(AgenticDigest.activity(in: [tool("Searching the web", "", done: false)]) == "Searching the web…")
        // A long summary is cut short.
        let long = AgenticDigest.activity(in: [tool("Ran", String(repeating: "x", count: 200), done: true)]) ?? ""
        #expect(long.count <= 64)
    }

    @Test func toolsAreCountedForDidNThings() {
        let parts: [RemotePart] = [
            .text("Done."),
            .tool(RemoteTool(id: "1", label: "Read", summary: "a", isDone: true, isError: false, size: nil)),
            .tool(RemoteTool(id: "2", label: "Ran", summary: "b", isDone: true, isError: true, size: nil)),
        ]
        #expect(AgenticDigest.tools(in: parts).map(\.id) == ["1", "2"])
    }

    @Test func handOffsAndReportsAreRecognised() {
        #expect(AgenticDigest.handoff("Handed to Forge: build the login page") == .handed(name: "Forge", task: "build the login page"))
        #expect(AgenticDigest.handoff("Forge finished: the login page works") == .finished(name: "Forge", gist: "the login page works"))
        #expect(AgenticDigest.handoff("There's no Zed in the crew, so that task wasn't handed off.") == nil)
    }

    @Test func previewsSayWhatTheLastMessageWas() {
        func message(_ role: String, _ parts: [RemotePart]) -> RemoteMessage {
            RemoteMessage(id: UUID(), role: role, parts: parts, createdAt: .now)
        }
        #expect(AgenticDigest.preview(of: message("assistant", [.text("**pong**\n\nmore")])) == "pong more")
        #expect(AgenticDigest.preview(of: message("user", [.text("hi")])) == "You: hi")
        #expect(AgenticDigest.preview(of: message("user", [.image(RemoteImage(id: UUID(), jpeg: nil, width: 1, height: 1, caption: nil))]))
                == "You: Photo")
        #expect(AgenticDigest.preview(of: message("assistant", [.approval(RemoteApproval(id: UUID(), agent: "Forge", summary: "Delete 3 files",
                                                                                         detail: "", risk: "delete", state: "pending", answeredBy: nil))]))
                == "Needs your OK: Delete 3 files")
        #expect(AgenticDigest.preview(of: message("assistant", [.image(RemoteImage(id: UUID(), jpeg: nil, width: 1, height: 1, caption: nil))]))
                == "Screenshot")
        #expect(AgenticDigest.preview(of: message("assistant", [.failure("Codex stopped")])) == "Codex stopped")
        let long = AgenticDigest.preview(of: message("assistant", [.text(String(repeating: "word ", count: 100))]))
        #expect(long.count <= 121)
    }
}
