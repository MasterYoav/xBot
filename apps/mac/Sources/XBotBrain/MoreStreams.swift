import Foundation

/// GitHub Copilot CLI's `--output-format json`: one event per line, `{"type": …, "data": {…}}`.
///
/// The reply is read from `assistant.message_delta` only (`assistant.message` repeats it, and
/// `assistant.reasoning*` is the model thinking, not the answer). Tools come from
/// `tool.execution_start` / `tool.execution_complete`, named as xBot names them elsewhere.
enum CopilotStream {
    static func events(from line: String) -> [BrainEvent] {
        guard let object = jsonObject(line), let type = object["type"] as? String else { return [] }
        let data = object["data"] as? [String: Any] ?? [:]
        switch type {
        case "assistant.message_delta":
            guard let text = data["deltaContent"] as? String, !text.isEmpty else { return [] }
            return [.textDelta(text)]
        case "tool.execution_start":
            guard let id = data["toolCallId"] as? String, let name = data["toolName"] as? String else { return [] }
            let input = arguments(data["arguments"])
            return [.toolCall(id: id, name: ToolNames.canonical(name), summary: summary(of: input))]
        case "tool.execution_complete":
            guard let id = data["toolCallId"] as? String else { return [] }
            if data["success"] as? Bool == false {
                let error = (data["error"] as? [String: Any])?["message"] as? String ?? String(localized: "The tool failed.")
                return [.toolResult(id: id, output: error, isError: true)]
            }
            let result = data["result"] as? [String: Any]
            return [.toolResult(id: id, output: result?["content"] as? String ?? "", isError: false)]
        case "session.error":
            return [.failed(data["message"] as? String ?? String(localized: "GitHub Copilot stopped with an error."))]
        case "result":
            var events: [BrainEvent] = []
            if let session = object["sessionId"] as? String { events.append(.session(session)) }
            let code = (object["exitCode"] as? NSNumber)?.intValue ?? 0
            events.append(code == 0 ? .done : .failed(String(localized: "GitHub Copilot stopped (exit code \(code)).")))
            return events
        default:
            return []
        }
    }

    /// Arguments arrive as an object, or as a JSON string of one.
    private static func arguments(_ value: Any?) -> [String: Any] {
        if let object = value as? [String: Any] { return object }
        if let text = value as? String, let object = jsonObject(text) { return object }
        return [:]
    }
}

/// Antigravity CLI's (`agy`) `--output-format stream-json`: `{"event": name, name: {…}}` per line.
/// Its steps are `user_input`, `agent_response` (text in `text_delta`) and `tool` (ACTIVE when it
/// starts, DONE with its output); `result` ends the turn.
enum AntigravityStream {
    static func events(from line: String) -> [BrainEvent] {
        guard let object = jsonObject(line), let event = object["event"] as? String else { return [] }
        switch event {
        case "init":
            return (object["conversation_id"] as? String).map { [.session($0)] } ?? []
        case "step_update":
            guard let step = object["step_update"] as? [String: Any] else { return [] }
            let index = (step["step_index"] as? NSNumber)?.intValue ?? 0
            let state = step["state"] as? String
            switch step["step_type"] as? String {
            case "agent_response":
                guard let text = step["text_delta"] as? String, !text.isEmpty else { return [] }
                return [.textDelta(text)]
            case "tool":
                let info = step["tool_info"] as? [String: Any] ?? [:]
                let name = ToolNames.canonical(step["tool_name"] as? String ?? info["name"] as? String ?? "tool")
                let id = "step-\(index)"
                if state == "ACTIVE" {
                    return [.toolCall(id: id, name: name, summary: summary(of: info["parameters"]))]
                }
                guard state == "DONE" || state == "ERROR" else { return [] }
                return [.toolResult(id: id, output: info["output"] as? String ?? "", isError: state == "ERROR")]
            default:
                return []
            }
        case "result":
            let result = object["result"] as? [String: Any] ?? [:]
            if result["status"] as? String == "SUCCESS" { return [.done] }
            let reason = [result["error"], result["response"]].compactMap { $0 as? String }.first { !$0.isEmpty }
            return [.failed(reason ?? String(localized: "Antigravity stopped with an error."))]
        default:
            return []
        }
    }

    /// `agy models`: "id<TAB>name" per line, after a "Fetching…" line.
    public static func models(_ text: String) -> [ModelOption] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[0].contains(" ") else { return nil }
            return ModelOption(id: parts[0], name: parts[1], efforts: [])
        }
    }
}

/// Other CLIs' tool names, as Claude Code's, which the rest of xBot knows how to show.
enum ToolNames {
    static func canonical(_ name: String) -> String {
        switch name {
        case "view", "view_file", "read_file", "read": "Read"
        case "bash", "shell", "run_command", "run_shell_command": "Bash"
        case "edit", "str_replace", "replace_file_content", "multi_replace_file_content", "sed_file", "replace": "Edit"
        case "create", "write_to_file", "write_file", "write": "Write"
        case "grep", "grep_search", "search_file_content": "Grep"
        case "glob", "find_by_name", "find": "Glob"
        case "list_dir", "ls", "list_directory": "LS"
        case "search_web", "web_search", "google_web_search": "WebSearch"
        case "read_url_content", "web_fetch", "fetch": "WebFetch"
        default: name
        }
    }
}

/// Antigravity's models, from `agy models` (it asks Google, so it can take a few seconds).
public enum AntigravityModels {
    public static func read(executable: URL, environment: [String: String]) async -> [ModelOption] {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["models"]
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let pid = process.processIdentifier
        let timeout = Task.detached {
            try await Task.sleep(for: .seconds(20))
            kill(pid, SIGKILL)
        }
        let data = await PipeReader.readAll(output.fileHandleForReading)
        timeout.cancel()
        return AntigravityStream.models(String(decoding: data, as: UTF8.self))
    }
}
