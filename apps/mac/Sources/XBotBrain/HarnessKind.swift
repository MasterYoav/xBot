import Foundation

/// An agent CLI the person has installed and signed in to, which xBot drives on their subscription.
public enum HarnessKind: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    /// Google's Antigravity CLI (`agy`): Gemini, and the other models Google offers in it. It
    /// replaced Gemini CLI, which no longer works for personal Google accounts.
    case antigravity
    /// GitHub Copilot CLI: whichever models the person's Copilot plan includes.
    case copilot

    /// Product names, so not localised.
    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .copilot: "GitHub Copilot"
        }
    }

    public var executableName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .antigravity: "agy"
        case .copilot: "copilot"
        }
    }

    /// What the composer offers. `nil` first: the CLI's own default, whatever it is this week.
    public var models: [String?] {
        switch self {
        case .claude: [nil, "opus", "sonnet", "haiku"]
        case .codex, .antigravity, .copilot: [nil]
        }
    }

    /// Answers to a JSON schema (plan mode, drawn wallpapers). Antigravity's `--json-schema` came
    /// back empty when tried, and Copilot has none.
    public var givesStructuredAnswers: Bool { self == .claude || self == .codex }

    /// No option for a system prompt: who the agent is goes ahead of the prompt.
    public var needsInstructionsInPrompt: Bool { self == .antigravity || self == .copilot }

    /// Run headless, Antigravity's edit mode refuses even to read, so "Edit files" has to use its
    /// full permissions. The composer says so.
    public var editingNeedsFullAccess: Bool { self == .antigravity }

    /// The prompt as this CLI receives it: with who the agent is ahead of it when it can't take
    /// that separately.
    func promptText(for request: TurnRequest) -> String {
        guard needsInstructionsInPrompt, let instructions = request.instructions, !instructions.isEmpty else {
            return request.prompt
        }
        return "<instructions>\n\(instructions)\n</instructions>\n\n" + request.prompt
    }

    /// Whether the prompt goes on stdin. Antigravity and Copilot read it only from their flag.
    var readsPromptFromStdin: Bool { self == .claude || self == .codex }

    /// Claude Code and Codex never get the prompt here: it goes on stdin, because a prompt starting
    /// with "-" would be read as a flag and argv has a length limit. Antigravity and Copilot read it
    /// only from a flag, so theirs is attached to it (`--print=…`, `--prompt=…`), which can't be
    /// taken for an option; the length limit stands for them. Codex reads a schema from a file,
    /// which the caller writes, and Claude Code xBot's tools (`toolFiles`, with `request.tools`).
    public func arguments(for request: TurnRequest, schemaFile: URL? = nil, toolFiles: ToolAttachment.Files? = nil) -> [String] {
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
            // Both flags take several values; the prompt is on stdin, so nothing positional follows.
            if request.tools != nil, let toolFiles {
                arguments += ["--mcp-config", toolFiles.mcpConfig.path, "--allowedTools", "mcp__xbot__*",
                              "--settings", toolFiles.settings.path]
            }
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
            for override in request.tools?.codexOverrides ?? [] { arguments += ["-c", override] }
            if let resume = request.resumeID { arguments.append(resume) }
            arguments.append("-")
            return arguments

        // Neither reads a prompt from stdin. Attached to its flag ("--prompt=…") a prompt that
        // starts with "-" can't be taken for an option.
        case .copilot:
            var arguments = ["--prompt=" + promptText(for: request), "--output-format", "json", "--no-color"]
            switch (request.planning, request.mode) {
            case (true, _), (false, .readOnly): break   // reads are allowed; anything else is denied headless
            case (false, .editFiles): arguments += ["--allow-tool", "write"]
            case (false, .fullAccess): arguments += ["--allow-all-tools", "--allow-all-paths"]
            }
            if let tools = request.tools {
                arguments += ["--additional-mcp-config", tools.copilotMCPConfig]
                // Headless, a tool that isn't allowed is denied; full access allows them all already.
                if request.planning || request.mode != .fullAccess { arguments += ["--allow-tool", "xbot"] }
            }
            if let model = request.model { arguments += ["--model", model] }
            if let effort = request.effort { arguments += ["--reasoning-effort", effort.claudeValue] }
            if let resume = request.resumeID { arguments += ["--resume", resume] }
            return arguments

        case .antigravity:
            var arguments = ["--print=" + promptText(for: request), "--output-format", "stream-json"]
            switch (request.planning, request.mode) {
            case (true, _), (false, .readOnly): arguments += ["--mode", "plan"]
            case (false, .editFiles), (false, .fullAccess): arguments.append("--dangerously-skip-permissions")
            }
            if let model = request.model { arguments += ["--model", model] }
            if let effort = request.effort {
                let level = switch effort { case .low: "low"; case .medium: "medium"; default: "high" }
                arguments += ["--effort", level]
            }
            if let resume = request.resumeID { arguments += ["--conversation", resume] }
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
        case .copilot: CopilotStream.events(from: line)
        case .antigravity: AntigravityStream.events(from: line)
        }
    }
}
