import Foundation

/// Codex's `exec --json` stream. Items arrive whole, so text is `.text`, not deltas.
enum CodexStream {
    static func events(from line: String) -> [BrainEvent] {
        guard let object = jsonObject(line) else { return [] }
        let item = object["item"] as? [String: Any]
        let id = item?["id"] as? String ?? ""

        switch object["type"] as? String {
        case "thread.started":
            return (object["thread_id"] as? String).map { [.session($0)] } ?? []

        case "item.started":
            guard item?["type"] as? String == "command_execution" else { return [] }
            return [.toolCall(id: id, name: "Shell", summary: command(item?["command"]))]

        case "item.completed":
            switch item?["type"] as? String {
            case "agent_message":
                return (item?["text"] as? String).map { [.text($0)] } ?? []
            case "command_execution":
                let exit = item?["exit_code"] as? Int ?? 0
                return [.toolResult(
                    id: id, output: item?["aggregated_output"] as? String ?? "", isError: exit != 0
                )]
            case "file_change":
                let changes = item?["changes"] as? [[String: Any]] ?? []
                let paths = changes.compactMap { $0["path"] as? String }
                return [
                    .toolCall(id: id, name: "Edit", summary: oneLine(paths.joined(separator: ", "))),
                    .toolResult(id: id, output: "", isError: item?["status"] as? String == "failed"),
                ]
            case "error":
                return (item?["message"] as? String).map { [.notice(oneLine($0))] } ?? []
            default:
                return []
            }

        case "turn.completed":
            return [.done]

        case "turn.failed":
            let message = (object["error"] as? [String: Any])?["message"] as? String
            return [.failed(message ?? String(localized: "Codex stopped with an error."))]

        case "error":
            // Not the end of the turn: Codex reports a reconnect this way and then carries on.
            return (object["message"] as? String).map { [.notice(oneLine($0))] } ?? []

        default:
            return []
        }
    }

    /// Codex wraps every command in the login shell (`/bin/zsh -lc '…'`). Show what it ran.
    private static func command(_ value: Any?) -> String {
        let full = value as? String ?? ""
        if let match = full.wholeMatch(of: /\S+ -lc '(.*)'/) { return oneLine(String(match.1)) }
        return oneLine(full)
    }
}
