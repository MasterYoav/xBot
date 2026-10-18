import Foundation
import Testing
@testable import XBotBrain

/// xBot's tools on a turn: each CLI's own way of being given an MCP server for one run.
@Suite struct ToolAttachmentTests {
    let tmp = URL(filePath: NSTemporaryDirectory())
    let tools = ToolAttachment(executable: URL(filePath: "/Applications/xBot.app/Contents/MacOS/XBot"),
                               token: "tok-123", socketPath: "/Users/me/Library/Application Support/xBot/xbot.sock")

    func request(_ mode: PermissionMode = .fullAccess, tools: ToolAttachment? = nil) -> TurnRequest {
        TurnRequest(prompt: "hi", directory: tmp, mode: mode, tools: tools)
    }

    func json(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func after(_ flag: String, in arguments: [String]) -> String? {
        arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }

    @Test func withoutToolsNothingChanges() {
        for kind in HarnessKind.allCases {
            let arguments = kind.arguments(for: request())
            #expect(!arguments.joined(separator: " ").contains("mcp"), "\(kind)")
        }
    }

    @Test func theServersEnvironmentCarriesTheTokenAndSocket() {
        #expect(tools.environment == ["XBOT_TOOLS_TOKEN": "tok-123",
                                      "XBOT_TOOLS_SOCKET": "/Users/me/Library/Application Support/xBot/xbot.sock"])
    }

    // MARK: Claude Code

    @Test func claudeGetsAnMCPConfigFileTheToolsAllowedAndTheHookSettings() {
        let files = ToolAttachment.Files(mcpConfig: URL(filePath: "/tmp/m.json"), settings: URL(filePath: "/tmp/s.json"))
        let arguments = HarnessKind.claude.arguments(for: request(.editFiles, tools: tools), toolFiles: files)
        #expect(after("--mcp-config", in: arguments) == "/tmp/m.json")
        #expect(after("--allowedTools", in: arguments) == "mcp__xbot__*")
        #expect(after("--settings", in: arguments) == "/tmp/s.json")
        // The prompt still goes on stdin: nothing positional after the variadic flags.
        #expect(!arguments.contains("hi"))
    }

    @Test func claudesMCPConfigStartsXBotWithTheToken() throws {
        let config = try json(tools.claudeMCPConfig)
        let server = try #require((config["mcpServers"] as? [String: Any])?["xbot"] as? [String: Any])
        #expect(server["type"] as? String == "stdio")
        #expect(server["command"] as? String == "/Applications/xBot.app/Contents/MacOS/XBot")
        #expect(server["args"] as? [String] == ["--mcp"])
        #expect((server["env"] as? [String: String])?["XBOT_TOOLS_TOKEN"] == "tok-123")
    }

    @Test func claudesHookRunsXBotBeforeTheShellAndOtherServersTools() throws {
        let settings = try json(tools.claudeHookSettings)
        let pre = try #require((settings["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])
        #expect(pre.count == 1)
        #expect(pre[0]["matcher"] as? String == "Bash|mcp__.*")
        let hook = try #require((pre[0]["hooks"] as? [[String: Any]])?.first)
        #expect(hook["type"] as? String == "command")
        #expect(hook["command"] as? String == "/Applications/xBot.app/Contents/MacOS/XBot")
        #expect(hook["args"] as? [String] == ["--hook"])
        // Longer than an approval's ten minutes, and a hook that fails blocks rather than allows.
        #expect((hook["timeout"] as? Int ?? 0) > 600)
        #expect(hook["onFailure"] as? String == "block")
    }

    // MARK: Codex

    @Test func codexGetsTheServerAsConfigOverrides() {
        let arguments = HarnessKind.codex.arguments(for: request(tools: tools))
        #expect(arguments.contains(#"mcp_servers.xbot.command="/Applications/xBot.app/Contents/MacOS/XBot""#))
        #expect(arguments.contains(#"mcp_servers.xbot.args=["--mcp"]"#))
        #expect(arguments.contains(#"mcp_servers.xbot.env.XBOT_TOOLS_TOKEN="tok-123""#))
        #expect(arguments.contains(#"mcp_servers.xbot.env.XBOT_TOOLS_SOCKET="/Users/me/Library/Application Support/xBot/xbot.sock""#))
        // An approval waits up to ten minutes; Codex's default tool timeout is a minute.
        #expect(arguments.contains("mcp_servers.xbot.tool_timeout_sec=900"))
        // Each override follows its -c.
        for override in arguments.filter({ $0.hasPrefix("mcp_servers.") }) {
            #expect(arguments[arguments.firstIndex(of: override)! - 1] == "-c")
        }
        #expect(arguments.last == "-", "the prompt still comes on stdin")
    }

    @Test func codexResumesWithTheToolsToo() {
        var resumed = request(tools: tools)
        resumed.resumeID = "abc"
        let arguments = HarnessKind.codex.arguments(for: resumed)
        #expect(arguments.contains(#"mcp_servers.xbot.args=["--mcp"]"#))
        #expect(Array(arguments.suffix(2)) == ["abc", "-"])
    }

    // MARK: Copilot

    @Test func copilotGetsAnAdditionalMCPConfig() throws {
        let arguments = HarnessKind.copilot.arguments(for: request(.editFiles, tools: tools))
        let value = try #require(after("--additional-mcp-config", in: arguments))
        let config = try json(value)
        let server = try #require((config["mcpServers"] as? [String: Any])?["xbot"] as? [String: Any])
        #expect(server["type"] as? String == "local")
        #expect(server["command"] as? String == "/Applications/xBot.app/Contents/MacOS/XBot")
        #expect(server["args"] as? [String] == ["--mcp"])
        #expect(server["tools"] as? [String] == ["*"])
        #expect((server["env"] as? [String: String])?["XBOT_TOOLS_TOKEN"] == "tok-123")
        // Outside full access its tools still need allowing.
        let allowed = arguments.indices.filter { arguments[$0] == "--allow-tool" }.map { arguments[$0 + 1] }
        #expect(allowed.contains("xbot"))
        #expect(allowed.contains("write"))
    }

    // MARK: Antigravity

    @Test func antigravityHasNoPerRunFlag() {
        let with = HarnessKind.antigravity.arguments(for: request(tools: tools))
        let without = HarnessKind.antigravity.arguments(for: request())
        #expect(with == without)
    }

    // MARK: The process

    @Test func theTurnsProcessGetsTheTokenAndClaudesFilesAreGoneAfterwards() async throws {
        let cli = try fakeCLI("""
        cat > /dev/null
        echo "$XBOT_TOOLS_TOKEN" > "$OUT/token"
        prev=""
        for a in "$@"; do
          if [ "$prev" = "--mcp-config" ]; then cp "$a" "$OUT/mcp.json"; echo "$a" > "$OUT/mcp-path"; fi
          if [ "$prev" = "--settings" ]; then cp "$a" "$OUT/settings.json"; fi
          prev="$a"
        done
        echo '{"type":"result","subtype":"success","is_error":false}'
        """)
        let brain = HarnessBrain(kind: .claude, executable: cli.url, environment: ["PATH": "/usr/bin:/bin"])
        let events = await collect(brain.run(request(tools: tools)))
        #expect(events == [.done])
        let token = try String(contentsOf: cli.out.appending(path: "token"), encoding: .utf8)
        #expect(token.trimmingCharacters(in: .whitespacesAndNewlines) == "tok-123")
        let mcp = try String(contentsOf: cli.out.appending(path: "mcp.json"), encoding: .utf8)
        #expect(mcp.contains("--mcp"))
        #expect(FileManager.default.fileExists(atPath: cli.out.appending(path: "settings.json").path))
        let path = try String(contentsOf: cli.out.appending(path: "mcp-path"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!FileManager.default.fileExists(atPath: path), "removed when the turn ended")
    }
}
