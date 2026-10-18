import Foundation

/// xBot's own MCP server, attached to one turn: the running app's binary (started by the CLI as
/// `XBot --mcp`) and the token that tells the app which chat and agent are asking.
public struct ToolAttachment: Equatable, Sendable {
    /// The running XBot binary.
    public var executable: URL
    /// The per-turn token. The app refuses calls with any other.
    public var token: String
    /// The app's Unix socket, so the server finds a sandboxed or relocated app.
    public var socketPath: String

    public init(executable: URL, token: String, socketPath: String) {
        self.executable = executable
        self.token = token
        self.socketPath = socketPath
    }

    /// Claude Code takes the server and its hook from files; HarnessBrain writes them for the
    /// turn and removes them when it ends.
    public struct Files: Equatable, Sendable {
        public var mcpConfig: URL
        public var settings: URL

        public init(mcpConfig: URL, settings: URL) {
            self.mcpConfig = mcpConfig
            self.settings = settings
        }
    }

    // The same names as XBotTools' `ToolEnvironment` (XBotBrain stays free of it).
    static let tokenVariable = "XBOT_TOOLS_TOKEN"
    static let socketVariable = "XBOT_TOOLS_SOCKET"

    /// For the server, and for the CLI's process (Claude Code's hook and Antigravity's server
    /// inherit it from there).
    public var environment: [String: String] { [Self.tokenVariable: token, Self.socketVariable: socketPath] }

    /// An approval waits ten minutes; the CLIs give up on a tool call later than that.
    static let toolTimeoutSeconds = 900

    var command: String { executable.path(percentEncoded: false) }

    /// `--mcp-config`'s file.
    public var claudeMCPConfig: String {
        Self.json(["mcpServers": ["xbot": [
            "type": "stdio", "command": command, "args": ["--mcp"], "env": environment,
        ] as [String: Any]]])
    }

    /// `--settings`'s file: a PreToolUse hook that runs `XBot --hook` before Claude Code's own
    /// shell and other MCP servers' tools, so they follow the same approval rules as xBot's.
    /// Exec form (no shell to quote for), and a hook that fails or times out blocks the call
    /// rather than letting it through.
    public var claudeHookSettings: String {
        Self.json(["hooks": ["PreToolUse": [[
            "matcher": "Bash|mcp__.*",
            "hooks": [[
                "type": "command", "command": command, "args": ["--hook"],
                "timeout": Self.toolTimeoutSeconds + 60, "onFailure": "block",
            ] as [String: Any]],
        ] as [String: Any]]]])
    }

    /// Codex's `-c` overrides, each a TOML value.
    var codexOverrides: [String] {
        var overrides = [
            "mcp_servers.xbot.command=\(HarnessKind.tomlString(command))",
            "mcp_servers.xbot.args=[\"--mcp\"]",
        ]
        for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
            overrides.append("mcp_servers.xbot.env.\(key)=\(HarnessKind.tomlString(value))")
        }
        overrides.append("mcp_servers.xbot.tool_timeout_sec=\(Self.toolTimeoutSeconds)")
        return overrides
    }

    /// `--additional-mcp-config`'s JSON, in the shape `copilot mcp add --json` writes.
    var copilotMCPConfig: String {
        Self.json(["mcpServers": ["xbot": [
            "type": "local", "command": command, "args": ["--mcp"], "tools": ["*"], "env": environment,
            "timeout": Self.toolTimeoutSeconds * 1000,
        ] as [String: Any]]])
    }

    static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
