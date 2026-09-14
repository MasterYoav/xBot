import Foundation

/// One AG-UI message, as runs carry them.
public struct WireMessage: Sendable, Equatable {
    public let id: String
    public let role: String
    public var content: String?
    public var toolCalls: [WireToolCall]
    public let toolCallId: String?

    public init(id: String, role: String, content: String? = nil, toolCalls: [WireToolCall] = [], toolCallId: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }

    /// A message from the engine's thread history. Only the AG-UI fields travel; anything else the
    /// history route adds is not part of what a run accepts.
    public init?(row: [String: Any]) {
        guard let id = row["id"] as? String, let role = row["role"] as? String else { return nil }
        let calls = (row["toolCalls"] as? [[String: Any]] ?? []).compactMap { call -> WireToolCall? in
            guard let callId = call["id"] as? String,
                  let function = call["function"] as? [String: Any],
                  let name = function["name"] as? String
            else { return nil }
            return WireToolCall(id: callId, name: name, arguments: function["arguments"] as? String ?? "")
        }
        self.init(id: id, role: role, content: row["content"] as? String, toolCalls: calls, toolCallId: row["toolCallId"] as? String)
    }

    public var dictionary: [String: Any] {
        var wire: [String: Any] = ["id": id, "role": role]
        if let content { wire["content"] = content }
        if !toolCalls.isEmpty {
            wire["toolCalls"] = toolCalls.map {
                ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments]]
            }
        }
        if let toolCallId { wire["toolCallId"] = toolCallId }
        return wire
    }
}

public struct WireToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/**
 A conversation's messages as the next run must send them, rebuilt from a run's events.

 **Why a run sends the whole conversation.** CopilotKit's runtime hands the agent exactly the messages
 the client sent, and never adds the thread's earlier history; it only uses history to decide which
 incoming messages are new and worth persisting. The Mac app used to send just the newest user
 message, so every agent answered every message as though it opened a fresh conversation — no memory
 of anything said before. CopilotKit's own client sends its full list, and so does this.

 **Why rebuilt with upstream's reducer, id for id.** The runtime skips messages whose ids the thread
 already has. A message rebuilt under a different id than the thread stored would be persisted again —
 the conversation would fill with duplicates. So events apply exactly as `@ag-ui/client` applies them:
 a text message under its `messageId`; a tool call attached to its `parentMessageId` when that is an
 assistant message and otherwise opening an assistant message whose id is the tool call's own; a
 result as a `tool` message.
 */
public struct WireTranscript: Sendable, Equatable {
    public private(set) var messages: [WireMessage]

    public init(messages: [WireMessage] = []) {
        self.messages = messages
    }

    public mutating func append(_ message: WireMessage) {
        messages.append(message)
    }

    /// Apply one AG-UI event, as `@ag-ui/client`'s default reducer does.
    public mutating func apply(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "TEXT_MESSAGE_START":
            guard let id = event["messageId"] as? String, !messages.contains(where: { $0.id == id }) else { return }
            messages.append(WireMessage(id: id, role: event["role"] as? String ?? "assistant", content: ""))

        case "TEXT_MESSAGE_CONTENT", "TEXT_MESSAGE_CHUNK":
            guard let id = event["messageId"] as? String, let delta = event["delta"] as? String else { return }
            if let index = messages.lastIndex(where: { $0.id == id }) {
                messages[index].content = (messages[index].content ?? "") + delta
            } else {
                messages.append(WireMessage(id: id, role: "assistant", content: delta))
            }

        case "TOOL_CALL_START":
            guard let callId = event["toolCallId"] as? String,
                  let name = event["toolCallName"] as? String
            else { return }
            let call = WireToolCall(id: callId, name: name, arguments: "")
            if let parent = event["parentMessageId"] as? String {
                if let index = messages.firstIndex(where: { $0.id == parent }), messages[index].role == "assistant" {
                    messages[index].toolCalls.append(call)
                    return
                }
                // A parent that is not an assistant message: upstream falls back to the call's id.
                let existing = messages.contains { $0.id == parent }
                messages.append(WireMessage(id: existing ? callId : parent, role: "assistant", toolCalls: [call]))
                return
            }
            messages.append(WireMessage(id: callId, role: "assistant", toolCalls: [call]))

        case "TOOL_CALL_ARGS":
            guard let callId = event["toolCallId"] as? String, let delta = event["delta"] as? String else { return }
            for index in messages.indices {
                if let call = messages[index].toolCalls.firstIndex(where: { $0.id == callId }) {
                    messages[index].toolCalls[call].arguments += delta
                    return
                }
            }

        case "TOOL_CALL_RESULT":
            guard let callId = event["toolCallId"] as? String else { return }
            let id = event["messageId"] as? String ?? "\(callId)-result"
            guard !messages.contains(where: { $0.id == id }) else { return }
            messages.append(WireMessage(id: id, role: "tool", content: event["content"] as? String ?? "", toolCallId: callId))

        default:
            return
        }
    }

    /// Client tool calls the Bot made that nothing has answered yet — what the client must now run.
    public var pendingClientCalls: [WireToolCall] {
        let answered = Set(messages.compactMap { $0.role == "tool" ? $0.toolCallId : nil })
        return messages.flatMap(\.toolCalls).filter { ComputerTools.names.contains($0.name) && !answered.contains($0.id) }
    }

    public mutating func appendToolResult(callId: String, content: String, id: String = UUID().uuidString) {
        messages.append(WireMessage(id: id, role: "tool", content: content, toolCallId: callId))
    }
}
