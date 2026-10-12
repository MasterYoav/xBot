import Foundation
import Testing
@testable import XBotRemote

@Suite struct WireTests {
    let chatID = UUID()

    var everyHostMessage: [HostMessage] {
        let chat = RemoteChat(id: chatID, title: "Fix the build", projectID: UUID(), agent: "claude", agentName: "Claude Code",
                              model: "opus", mode: "editFiles", effort: "high", planMode: true, crewName: "Forge",
                              updatedAt: Date(timeIntervalSince1970: 1_800_000_000), isRunning: true, blocked: nil)
        let plan = RemotePlan(status: "review", summary: "Two steps", note: "", steps: [RemotePlanStep(id: UUID(), title: "Read", status: "pending")],
                              problem: nil, closing: nil)
        let parts: [RemotePart] = [.text("hi"), .tool(RemoteTool(id: "t", label: "Read", summary: "a.txt", isDone: true, isError: false, size: "2 lines")),
                                   .notice("n"), .failure("f"), .plan(plan)]
        let message = RemoteMessage(id: UUID(), role: "assistant", parts: parts, createdAt: Date(timeIntervalSince1970: 1_800_000_001))
        let agent = RemoteAgent(id: "codex", name: "Codex", models: [.init(id: "gpt-5", name: "GPT-5", efforts: ["low", "high"])],
                                makesPlans: true, editingNeedsFullAccess: false)
        return [
            .hello(version: Wire.version, macName: "Mac mini", macID: UUID()),
            .workspace(projects: [RemoteProject(id: UUID(), name: "xBot")], chats: [chat], agents: [agent]),
            .chat(chat), .chatRemoved(chatID), .agents([agent]),
            .transcript(chatID: chatID, messages: [message]), .message(chatID: chatID, message: message),
            .messageRemoved(chatID: chatID, messageID: message.id), .live(chatID: chatID, parts: parts),
            .reply(requestID: UUID(), ok: false, reason: "busy", chatID: chatID),
        ]
    }

    var everyClientMessage: [ClientMessage] {
        let settings = RemoteChatSettings(agent: "codex", model: Choice(nil), mode: "readOnly", effort: Choice("low"), planMode: false)
        return [
            .hello(version: 1, deviceID: "dev", deviceName: "iPhone"), .open(chatID: chatID), .close(chatID: chatID),
            .send(requestID: UUID(), chatID: chatID, text: "go"),
            .newChat(requestID: UUID(), projectID: nil, text: "hi", settings: settings),
            .stop(requestID: UUID(), chatID: chatID), .edit(requestID: UUID(), chatID: chatID, messageID: UUID(), text: "again"),
            .runPlan(requestID: UUID(), chatID: chatID, messageID: UUID()), .cancelPlan(requestID: UUID(), chatID: chatID, messageID: UUID()),
            .setChat(requestID: UUID(), chatID: chatID, settings: settings), .away,
        ]
    }

    @Test func everyMessageSurvivesTheWire() throws {
        for message in everyHostMessage {
            var buffer = try Frame.encode(message)
            #expect(try Frame.decode(HostMessage.self, from: &buffer) == [message])
            #expect(buffer.isEmpty)
        }
        for message in everyClientMessage {
            var buffer = try Frame.encode(message)
            #expect(try Frame.decode(ClientMessage.self, from: &buffer) == [message])
        }
    }

    /// "Set the model to the agent's default" (inner nil) is not "leave the model alone" (outer nil).
    @Test func aDefaultModelIsNotAnUnchangedOne() throws {
        let toDefault = RemoteChatSettings(model: Choice(nil))
        let unchanged = RemoteChatSettings()
        let a = try Wire.decoder.decode(RemoteChatSettings.self, from: Wire.encoder.encode(toDefault))
        let b = try Wire.decoder.decode(RemoteChatSettings.self, from: Wire.encoder.encode(unchanged))
        #expect(a.model == Choice(nil) && b.model == nil)
    }

    @Test func framesArriveInPiecesAndTogether() throws {
        let messages = Array(everyHostMessage.prefix(4))
        let stream = try messages.map(Frame.encode).reduce(Data(), +)
        var buffer = Data()
        var got: [HostMessage] = []
        for byte in stream {
            buffer.append(byte)
            got += try Frame.decode(HostMessage.self, from: &buffer)
        }
        #expect(got == messages && buffer.isEmpty)
    }

    /// A newer Mac's message this phone doesn't know is skipped; the ones around it still arrive.
    @Test func anUnknownMessageIsSkipped() throws {
        let unknown = Data(#"{"hologram":{"x":1}}"#.utf8)
        var length = UInt32(unknown.count).bigEndian
        var buffer = try Frame.encode(HostMessage.chatRemoved(chatID)) + Data(bytes: &length, count: 4) + unknown
            + Frame.encode(HostMessage.chatRemoved(chatID))
        #expect(try Frame.decode(HostMessage.self, from: &buffer) == [.chatRemoved(chatID), .chatRemoved(chatID)])
    }

    @Test func workflowMessagesSurviveTheWire() throws {
        let run = RemoteRun(id: UUID(), startedAt: Date(timeIntervalSince1970: 1_800_000_000), isRunning: false, failed: true)
        let workflow = RemoteWorkflow(id: UUID(), name: "Nightly", schedule: .daily(hour: 2, minute: 0),
                                      stepTitles: ["Build", "Failing?", "Fix"], isEnabled: true,
                                      nextRun: Date(timeIntervalSince1970: 1_800_003_600), lastRunAt: nil, runs: [run],
                                      blocked: "There's no Jev key yet.")
        let host: [HostMessage] = [.workflowsAvailable(true), .workflows(requestID: UUID(), workflows: [workflow], available: true)]
        let client: [ClientMessage] = [.listWorkflows(requestID: UUID()),
                                       .runWorkflow(requestID: UUID(), workflowID: workflow.id, input: "v2"),
                                       .runWorkflow(requestID: UUID(), workflowID: workflow.id, input: nil)]
        for message in host {
            var buffer = try Frame.encode(message)
            #expect(try Frame.decode(HostMessage.self, from: &buffer) == [message])
        }
        for message in client {
            var buffer = try Frame.encode(message)
            #expect(try Frame.decode(ClientMessage.self, from: &buffer) == [message])
        }
    }

    @Test func anOversizedFrameIsRefused() {
        var length = UInt32(Frame.maximumLength + 1).bigEndian
        var buffer = Data(bytes: &length, count: 4)
        #expect(throws: Frame.TooLarge.self) { _ = try Frame.decode(HostMessage.self, from: &buffer) }
    }
}
