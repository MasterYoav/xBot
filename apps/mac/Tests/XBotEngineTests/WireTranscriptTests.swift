import Foundation
import Testing
@testable import XBotEngine

/// The runtime dedupes by message id, so a transcript rebuilt under different ids duplicates the thread.
@Suite
struct WireTranscriptTests {
    @Test func eventsRebuildMessagesUnderUpstreamsIds() {
        var transcript = WireTranscript(messages: [WireMessage(id: "u1", role: "user", content: "hi")])
        transcript.apply(["type": "TEXT_MESSAGE_START", "messageId": "a1", "role": "assistant"])
        transcript.apply(["type": "TEXT_MESSAGE_CONTENT", "messageId": "a1", "delta": "let me "])
        transcript.apply(["type": "TEXT_MESSAGE_CONTENT", "messageId": "a1", "delta": "look"])
        // Attached to its assistant parent.
        transcript.apply(["type": "TOOL_CALL_START", "toolCallId": "c1", "toolCallName": "computer_read", "parentMessageId": "a1"])
        transcript.apply(["type": "TOOL_CALL_ARGS", "toolCallId": "c1", "delta": "{}"])
        // No parent: opens an assistant message under the call's id.
        transcript.apply(["type": "TOOL_CALL_START", "toolCallId": "c2", "toolCallName": "computer_snapshot"])

        #expect(transcript.messages.map(\.id) == ["u1", "a1", "c2"])
        #expect(transcript.messages[1].content == "let me look")
        #expect(transcript.messages[1].toolCalls == [WireToolCall(id: "c1", name: "computer_read", arguments: "{}")])
        #expect(transcript.messages[2].toolCalls.map(\.id) == ["c2"])
    }

    @Test func onlyUnansweredComputerCallsArePending() {
        var transcript = WireTranscript()
        transcript.apply(["type": "TOOL_CALL_START", "toolCallId": "c1", "toolCallName": "computer_read"])
        transcript.apply(["type": "TOOL_CALL_START", "toolCallId": "c2", "toolCallName": "computer_click"])
        transcript.apply(["type": "TOOL_CALL_START", "toolCallId": "s1", "toolCallName": "some_server_tool"])
        transcript.apply(["type": "TOOL_CALL_RESULT", "toolCallId": "c1", "messageId": "r1", "content": "ok"])
        #expect(transcript.pendingClientCalls.map(\.id) == ["c2"])

        transcript.appendToolResult(callId: "c2", content: "{}")
        #expect(transcript.pendingClientCalls.isEmpty)
    }

    @Test func aHistoryRowRoundTripsToTheWire() throws {
        let row: [String: Any] = [
            "id": "a1", "role": "assistant", "createdAt": "ignored",
            "toolCalls": [["id": "c1", "type": "function", "function": ["name": "computer_read", "arguments": "{}"]]],
        ]
        let message = try #require(WireMessage(row: row))
        let wire = message.dictionary
        #expect(wire["createdAt"] == nil)
        let calls = try #require(wire["toolCalls"] as? [[String: Any]])
        #expect((calls.first?["function"] as? [String: Any])?["name"] as? String == "computer_read")
    }
}
