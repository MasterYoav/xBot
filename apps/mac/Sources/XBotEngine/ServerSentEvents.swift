import Foundation

/// One dispatched server-sent event.
public struct ServerSentEvent: Sendable, Equatable {
    public let name: String?
    public let data: String
    public let id: String?

    public init(name: String? = nil, data: String, id: String? = nil) {
        self.name = name
        self.data = data
        self.id = id
    }
}

/// The SSE wire format, line by line.
///
/// Written out rather than pulled in, because the format is small and the failure modes are
/// specific to what this app does with it. It follows the WHATWG rules that matter here: `data:`
/// accumulates across lines joined by a newline, a leading space after the colon is stripped, a
/// line starting with `:` is a comment, and a blank line dispatches.
///
/// The property that earns the hand-written version: **an incomplete event is never dispatched.**
/// Upstream's own configuration notes that agent endpoints "will be redeployed mid-answer" and
/// "will sometimes accept a connection and then write nothing at all", so a truncated stream is
/// the normal case rather than the exceptional one. A parser that flushed on end-of-stream would
/// hand the conversation half a JSON object to decode.
public struct ServerSentEventParser: Sendable {
    private var name: String?
    private var data: [String] = []
    private var id: String?

    public init() {}

    /// Feed one line. Returns an event when that line completed one.
    public mutating func consume(_ rawLine: String) -> ServerSentEvent? {
        // A stray CR from CRLF framing would otherwise end up inside the JSON.
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine

        guard !line.isEmpty else { return dispatch() }
        // Comments. Servers send these as keep-alives, and they must not reset the buffer.
        guard !line.hasPrefix(":") else { return nil }

        let field: String
        var value: String
        if let colon = line.firstIndex(of: ":") {
            field = String(line[line.startIndex..<colon])
            value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }
        } else {
            field = line
            value = ""
        }

        switch field {
        case "event": name = value
        case "data": data.append(value)
        case "id": id = value
        default: break  // `retry` and anything unknown are ignored, per the spec.
        }
        return nil
    }

    private mutating func dispatch() -> ServerSentEvent? {
        defer {
            name = nil
            data = []
            id = nil
        }
        guard !data.isEmpty else { return nil }
        return ServerSentEvent(name: name, data: data.joined(separator: "\n"), id: id)
    }
}

/// AG-UI's events, narrowed to the ones the conversation can draw.
///
/// Unknown types return nil rather than throwing. AG-UI has more than thirty event types and this
/// app renders a handful; a stream carrying a `REASONING_MESSAGE_CHUNK` is working correctly, and
/// treating it as an error would break a conversation over an event we simply do not show yet.
public enum AGUIDecoder {
    public static func decode(_ event: ServerSentEvent) -> TurnEvent? {
        guard
            let payload = event.data.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let type = object["type"] as? String
        else { return nil }

        // `messageId` is absent on run-level events, so it falls back to the run's own id — the
        // conversation keys everything by message, and an event with no key cannot be placed.
        let messageId =
            (object["messageId"] as? String)
            ?? (object["parentMessageId"] as? String)
            ?? (object["runId"] as? String)
            ?? ""

        switch type {
        case "RUN_STARTED", "TEXT_MESSAGE_START":
            return .started(messageId: messageId)

        case "TEXT_MESSAGE_CONTENT", "TEXT_MESSAGE_CHUNK":
            guard let delta = object["delta"] as? String, !delta.isEmpty else { return nil }
            return .textDelta(messageId: messageId, text: delta)

        case "TOOL_CALL_START":
            let name = object["toolCallName"] as? String ?? "tool"
            return .toolCall(messageId: messageId, name: name, target: "")

        case "TEXT_MESSAGE_END", "RUN_FINISHED":
            return .finished(messageId: messageId)

        case "RUN_ERROR":
            // The engine's own sentence, not one we invent. It is written for a person and it is
            // the only thing that will tell them what to do next.
            let message = object["message"] as? String ?? String(localized: "The turn failed")
            return .failed(messageId: messageId, reason: message)

        default:
            return nil
        }
    }
}
