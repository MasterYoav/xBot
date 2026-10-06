import Foundation

/// Claude Code's `--output-format stream-json`, run with `--include-partial-messages`.
///
/// Text is read from the `stream_event` deltas only: the complete `assistant` message that follows
/// repeats it. Tool calls are read from the `assistant` message, where their input is whole.
/// Anything a subagent says (`parent_tool_use_id` set) belongs to that subagent, not the reply.
enum ClaudeStream {
    static func events(from line: String) -> [BrainEvent] {
        guard let object = jsonObject(line) else { return [] }
        let topLevel = object["parent_tool_use_id"] == nil || object["parent_tool_use_id"] is NSNull

        switch object["type"] as? String {
        case "system":
            guard object["subtype"] as? String == "init",
                  let id = object["session_id"] as? String else { return [] }
            return [.session(id)]

        case "stream_event":
            guard topLevel,
                  let event = object["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return [] }
            return [.textDelta(text)]

        case "assistant":
            guard topLevel else { return [] }
            return blocks(of: object).compactMap { block in
                guard block["type"] as? String == "tool_use",
                      let id = block["id"] as? String,
                      let name = block["name"] as? String else { return nil }
                return .toolCall(id: id, name: name, summary: summary(of: block["input"]))
            }

        case "user":
            guard topLevel else { return [] }
            return blocks(of: object).compactMap { block in
                guard block["type"] as? String == "tool_result",
                      let id = block["tool_use_id"] as? String else { return nil }
                return .toolResult(
                    id: id,
                    output: text(of: block["content"]),
                    isError: block["is_error"] as? Bool ?? false
                )
            }

        case "result":
            if object["is_error"] as? Bool == true || object["subtype"] as? String != "success" {
                let reason = (object["errors"] as? [String])?.joined(separator: "\n")
                    ?? (object["result"] as? String)
                    ?? String(localized: "Claude Code stopped with an error.")
                return [.failed(reason)]
            }
            return [.done]

        default:
            return []
        }
    }

    private static func blocks(of object: [String: Any]) -> [[String: Any]] {
        ((object["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
    }

    /// A tool result's content is a string, or a list of blocks of which only text is readable.
    private static func text(of content: Any?) -> String {
        if let string = content as? String { return string }
        let blocks = content as? [[String: Any]] ?? []
        return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }
}
