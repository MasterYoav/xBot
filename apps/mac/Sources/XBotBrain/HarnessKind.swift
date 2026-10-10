import Foundation

/// An agent CLI the person has installed and signed in to, which xBot drives on their subscription.
public enum HarnessKind: String, Codable, CaseIterable, Sendable {
    case claude
    case codex

    /// Product names, so not localised.
    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    public var executableName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        }
    }

    /// What the composer offers. `nil` first: the CLI's own default, whatever it is this week.
    public var models: [String?] {
        switch self {
        case .claude: [nil, "opus", "sonnet", "haiku"]
        case .codex: [nil]
        }
    }

    /// Never the prompt: it goes on stdin, because a prompt starting with "-" would be read as a
    /// flag and argv has a length limit. Codex reads a schema from a file, which the caller writes.
    public func arguments(for request: TurnRequest, schemaFile: URL? = nil) -> [String] {
        switch self {
        case .claude:
            let mode = switch (request.planning, request.mode) {
            case (true, _): "plan"
            case (false, .readOnly): "default"
            case (false, .editFiles): "acceptEdits"
            case (false, .fullAccess): "bypassPermissions"
            }
            var arguments = [
                "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                "--permission-mode", mode,
            ]
            // Galaxy is max effort on the strongest model, whatever model was picked.
            let model = request.effort == .galaxy ? "opus" : request.model
            if let model { arguments += ["--model", model] }
            if let effort = request.effort { arguments += ["--effort", effort.claudeValue] }
            if let resume = request.resumeID { arguments += ["--resume", resume] }
            if let schema = request.schema { arguments += ["--json-schema", schema] }
            if let instructions = request.instructions { arguments += ["--append-system-prompt", instructions] }
            return arguments

        case .codex:
            let sandbox = switch (request.planning, request.mode) {
            case (true, _), (false, .readOnly): "read-only"
            case (false, .editFiles): "workspace-write"
            case (false, .fullAccess): "danger-full-access"
            }
            // `-c` rather than `-s`: `exec resume` has no `-s`, and one spelling for both is simpler.
            var arguments = ["exec"]
            if request.resumeID != nil { arguments.append("resume") }
            arguments += ["--json", "--skip-git-repo-check", "-c", "sandbox_mode=\"\(sandbox)\""]
            if let model = request.model { arguments += ["-m", model] }
            if let effort = request.effort { arguments += ["-c", "model_reasoning_effort=\"\(effort.codexValue)\""] }
            if let schemaFile { arguments += ["--output-schema", schemaFile.path] }
            if let instructions = request.instructions {
                arguments += ["-c", "developer_instructions=\(Self.tomlString(instructions))"]
            }
            if let resume = request.resumeID { arguments.append(resume) }
            arguments.append("-")
            return arguments
        }
    }

    /// A TOML basic string, as `-c key=value` parses its value.
    static func tomlString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                out += String(format: "\\u%04X", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    public func events(from line: String) -> [BrainEvent] {
        switch self {
        case .claude: ClaudeStream.events(from: line)
        case .codex: CodexStream.events(from: line)
        }
    }
}
