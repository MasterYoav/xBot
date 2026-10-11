import Foundation
import Synchronization
import Testing
import XBotBrain
@testable import XBotCore

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/abilities/\(name)", withExtension: nil))
    return try Data(contentsOf: url)
}

/// Parsers against output recorded from Claude Code 2.1.296 and Codex 0.162.1 on a real Mac.
@Suite struct AbilityParsingTests {
    @Test func claudePluginsOncePerIDPreferringTheUserScope() throws {
        let plugins = AbilityParsing.claudePlugins(try fixture("claude-plugin-list.json"), manifest: { _ in nil })
        #expect(plugins.count == 10)
        let superpowers = try #require(plugins.first { $0.key == "superpowers@claude-plugins-official" })
        #expect(superpowers.title == "Superpowers" && superpowers.source == "claude-plugins-official")
        #expect(superpowers.enabled == true && superpowers.toggle == .claudePlugin(id: superpowers.key))
        #expect(superpowers.removal == .claudePlugin(id: superpowers.key, scope: "user"))
        #expect(plugins.first { $0.key == "swift-lsp@claude-plugins-official" }?.title == "Swift Lsp")
    }

    @Test func claudeSyncedPluginsCannotBeSwitchedOrRemoved() throws {
        let plugins = AbilityParsing.claudePlugins(try fixture("claude-plugin-list.json"), manifest: { _ in nil })
        let synced = try #require(plugins.first { $0.key == "qdrant@synced" })
        #expect(synced.toggle == nil && synced.removal == nil && synced.fixedReason != nil)
    }

    @Test func codexPlugins() throws {
        let plugins = AbilityParsing.codexPlugins(try fixture("codex-plugin-list.json"), manifest: { _ in nil })
        #expect(plugins.count == 24)
        let documents = try #require(plugins.first)
        #expect(documents.key == "documents@openai-primary-runtime" && documents.agent == .codex)
        #expect(documents.toggle == .codexPlugin(id: documents.key) && documents.removal == .codexPlugin(id: documents.key))
    }

    @Test func marketplacesFromBothAgents() throws {
        let claude = AbilityParsing.marketplace(try fixture("claude-plugin-list-available.json"), agent: .claude)
        let codex = AbilityParsing.marketplace(try fixture("codex-plugin-list-available.json"), agent: .codex)
        #expect(claude.count == 6 && codex.count == 6)
        #expect(claude.first?.pluginID == "42crunch-api-security-testing@claude-plugins-official")
        #expect(claude.first?.summary?.isEmpty == false)
        #expect(codex.first?.pluginID == "chrome@openai-bundled" && codex.first?.installed == false)
    }

    /// A server that comes with a plugin has no table of its own in config.toml, and Codex refuses
    /// to start with one holding only `enabled` ("invalid transport"): no switch for those.
    @Test func codexMCPsFromAPluginHaveNoSwitch() throws {
        let servers = AbilityParsing.codexMCPs(try fixture("codex-mcp-list.json"), configured: ["headroom", "tokensave"])
        let review = try #require(servers.first { $0.key == "code-review" })
        #expect(review.toggle == nil && review.removal == nil && review.fixedReason != nil)
        let headroom = try #require(servers.first { $0.key == "headroom" })
        #expect(headroom.toggle == .codexMCP(name: "headroom") && headroom.removal == .codexMCP(name: "headroom"))
    }

    @Test func configuredCodexServersAreTheTablesInItsConfig() {
        let toml = "[mcp_servers.node_repl]\ncommand = \"x\"\n[mcp_servers.node_repl.env]\nA = \"1\"\n[mcp_servers.\"odd name\"]\n[plugins.\"a@b\"]\n"
        #expect(AbilityParsing.codexConfiguredServers(toml) == ["node_repl", "odd name"])
    }

    @Test func codexMCPsWithTheirSwitches() throws {
        let servers = AbilityParsing.codexMCPs(try fixture("codex-mcp-list.json"), configured: ["code-review", "codex_app", "computer-use", "cua_repl", "headroom", "node_repl", "tokensave"])
        #expect(servers.map(\.key) == ["code-review", "codex_app", "computer-use", "cua_repl", "headroom", "node_repl", "tokensave"])
        #expect(servers.first { $0.key == "computer-use" }?.enabled == false)
        #expect(servers.first { $0.key == "headroom" }?.summary == "headroom mcp serve")
    }

    @Test func claudeMCPsForTheUserAndTheProjectInView() throws {
        let data = try fixture("claude.json")
        let everywhere = AbilityParsing.claudeMCPs(data, project: nil)
        #expect(everywhere.map(\.key) == ["headroom", "tokensave"])
        #expect(everywhere.allSatisfy { $0.toggle == nil && $0.fixedReason != nil })
        let colony = AbilityParsing.claudeMCPs(data, project: URL(filePath: "/Users/me/Developer/Colony/"))
        #expect(colony.map(\.key) == ["headroom", "tokensave", "swiftpieces"])
        #expect(colony.last?.removal == .claudeMCP(name: "swiftpieces", scope: "local"))
    }

    @Test func connectorsAndHealthFromClaudeMCPList() throws {
        let lines = AbilityParsing.claudeHealth(String(decoding: try fixture("claude-mcp-list.txt"), as: UTF8.self))
        #expect(lines.count == 7)
        #expect(lines.first { $0.name == "tokensave" }?.status == .failed)
        let connectors = AbilityParsing.claudeConnectors(lines)
        #expect(connectors.map(\.title) == ["Claude Docs", "Higgsfield.ai MCP", "Zoom for Claude", "Supabase", "Gmail"])
        #expect(connectors[1].status == .needsSignIn && connectors[0].status == .connected)
        #expect(connectors[4].summary == "gmailmcp.googleapis.com")
    }

    @Test func skillFrontMatter() {
        let meta = AbilityParsing.skillFrontMatter("---\nname: \"pdf\"\ndescription: Use when: reading PDFs\n---\n# PDF")
        #expect(meta.name == "pdf" && meta.description == "Use when: reading PDFs")
        #expect(AbilityParsing.skillFrontMatter("# No front matter").name == nil)
    }

    @Test func codexDisabledSkills() {
        let toml = """
        [[skills.config]]
        path = "/a/SKILL.md"
        enabled = false

        [[skills.config]]
        path = "/b/SKILL.md"

        [features]
        enabled = false
        """
        #expect(AbilityParsing.codexDisabledSkills(toml) == ["/a/SKILL.md"])
    }
}

/// Codex's config is the person's file: one value changes, nothing else does.
@Suite struct CodexConfigTests {
    let original = """
    # my settings
    model = "gpt-5.5"

    [plugins."github@openai-curated"]
    enabled = true

    [mcp_servers.headroom]
    command = "headroom"
    args = ["mcp", "serve"]

    [features]
    js_repl = false
    """

    @Test func flipsOneValueAndLeavesTheRestByteForByte() {
        let edited = CodexConfig.setEnabled(false, table: CodexConfig.header("plugins", "github@openai-curated"), in: original)
        #expect(edited == original.replacingOccurrences(of: "[plugins.\"github@openai-curated\"]\nenabled = true",
                                                        with: "[plugins.\"github@openai-curated\"]\nenabled = false"))
    }

    @Test func addsTheLineWhenTheTableHasNone() {
        let edited = CodexConfig.setEnabled(false, table: CodexConfig.header("mcp_servers", "headroom"), in: original)
        #expect(edited.contains("[mcp_servers.headroom]\nenabled = false\ncommand = \"headroom\""))
        #expect(edited.contains("[features]\njs_repl = false"))
    }

    @Test func addsTheTableWhenMissing() {
        let edited = CodexConfig.setEnabled(false, table: CodexConfig.header("plugins", "pdf@openai"), in: original)
        #expect(edited.hasPrefix(original))
        #expect(edited.hasSuffix("\n\n[plugins.\"pdf@openai\"]\nenabled = false\n"))
    }

    @Test func skillEntriesAreFoundByPathOrAdded() {
        let first = CodexConfig.setSkillEnabled(false, path: "/s/SKILL.md", in: original)
        #expect(first.hasSuffix("[[skills.config]]\npath = \"/s/SKILL.md\"\nenabled = false\n"))
        let back = CodexConfig.setSkillEnabled(true, path: "/s/SKILL.md", in: first)
        #expect(back == first.replacingOccurrences(of: "enabled = false\n", with: "enabled = true\n"))
        #expect(AbilityParsing.codexDisabledSkills(back).isEmpty)
    }
}

/// Answers by the command's arguments; records what was run.
final class ScriptedRunner: CommandRunner {
    let answers: [String: CommandResult]
    let ran = Mutex<[String]>([])

    init(_ answers: [String: CommandResult]) { self.answers = answers }

    func run(_ executable: URL, _ arguments: [String], environment: [String: String], directory: URL?,
             timeout: Duration) async -> CommandResult {
        let line = "\(executable.lastPathComponent) \(arguments.joined(separator: " "))"
        ran.withLock { $0.append(line) }
        return answers[line] ?? CommandResult(status: 0, output: "")
    }
}

@MainActor @Suite struct AbilityCatalogTests {
    func home() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "home-\(UUID().uuidString)")
        let skill = home.appending(path: ".codex/skills/pdf")
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try "---\nname: pdf\ndescription: Read PDFs\n---\n".write(to: skill.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try "model = \"x\"\n".write(to: home.appending(path: ".codex/config.toml"), atomically: true, encoding: .utf8)
        try fixture("claude.json").write(to: home.appending(path: ".claude.json"))
        return home
    }

    func catalog(_ runner: ScriptedRunner, home: URL) -> AbilityCatalog {
        AbilityCatalog(runner: runner, home: home, tools: {
            [.claude: .init(executable: URL(filePath: "/bin/claude"), environment: [:]),
             .codex: .init(executable: URL(filePath: "/bin/codex"), environment: [:])]
        }, project: { nil })
    }

    func answers() throws -> [String: CommandResult] {
        [
            "claude plugin list --json": .init(status: 0, output: String(decoding: try fixture("claude-plugin-list.json"), as: UTF8.self)),
            "codex plugin list --json": .init(status: 0, output: String(decoding: try fixture("codex-plugin-list.json"), as: UTF8.self)),
            "codex mcp list --json": .init(status: 0, output: String(decoding: try fixture("codex-mcp-list.json"), as: UTF8.self)),
            "claude mcp list": .init(status: 0, output: String(decoding: try fixture("claude-mcp-list.txt"), as: UTF8.self)),
        ]
    }

    @Test func everyKindIsReadAndClaudeServersGetTheirHealth() async throws {
        let c = catalog(ScriptedRunner(try answers()), home: try home())
        await c.refresh()
        #expect(c.list(.plugins).count == 34)
        #expect(c.list(.connectors).count == 5)
        #expect(c.list(.mcps).first { $0.agent == .claude && $0.key == "tokensave" }?.status == .failed)
        #expect(c.list(.skills).contains { $0.agent == .codex && $0.title == "pdf" && $0.enabled == true })
        #expect(c.loading.isEmpty)
    }

    /// Codex is asked to load the edited config; if it refuses, the file goes back as it was.
    @Test func aCodexEditThatCodexRejectsIsPutBack() async throws {
        let home = try home()
        var script = try answers()
        script["codex mcp list --json"] = .init(status: 1, output: "", error: "Error: invalid transport")
        let c = catalog(ScriptedRunner(script), home: home)
        var said: [String] = []
        c.report = { said.append($0) }
        let server = Ability(agent: .codex, kind: .mcps, key: "headroom", title: "headroom", enabled: true,
                             toggle: .codexMCP(name: "headroom"))
        await c.setEnabled(server, false)
        #expect(try String(contentsOf: home.appending(path: ".codex/config.toml"), encoding: .utf8) == "model = \"x\"\n")
        #expect(said.last?.contains("invalid transport") == true)
    }

    @Test func aCodexSwitchIsWrittenToItsConfigAndReadBack() async throws {
        let home = try home()
        let c = catalog(ScriptedRunner(try answers()), home: home)
        await c.refresh()
        let skill = try #require(c.list(.skills).first { $0.agent == .codex })
        await c.setEnabled(skill, false)
        #expect(c.list(.skills).first { $0.id == skill.id }?.enabled == false)
        let toml = try String(contentsOf: home.appending(path: ".codex/config.toml"), encoding: .utf8)
        #expect(toml.hasPrefix("model = \"x\"\n"))
        #expect(AbilityParsing.codexDisabledSkills(toml) == [skill.key])
    }

    @Test func aClaudeSwitchRunsTheCLIAndAFailureIsUndoneAndSaid() async throws {
        var script = try answers()
        script["claude plugin disable ponytail@ponytail -s user"] = .init(status: 1, output: "", error: "Plugin is locked by policy")
        let runner = ScriptedRunner(script)
        let c = catalog(runner, home: try home())
        var said: [String] = []
        c.report = { said.append($0) }
        await c.refresh()
        let ponytail = try #require(c.list(.plugins).first { $0.key == "ponytail@ponytail" })
        await c.setEnabled(ponytail, false)
        #expect(runner.ran.withLock { $0.contains("claude plugin disable ponytail@ponytail -s user") })
        #expect(c.list(.plugins).first { $0.id == ponytail.id }?.enabled == true)
        #expect(said.last?.contains("Plugin is locked by policy") == true)
    }

    @Test func addingAnMCPServerGoesToEachChosenAgent() async throws {
        let runner = ScriptedRunner(try answers())
        let c = catalog(runner, home: try home())
        #expect(await c.addMCP(NewMCPServer(name: "sentry", target: .url("https://mcp.sentry.dev/mcp"), agents: [.claude, .codex])))
        #expect(await c.addMCP(NewMCPServer(name: "files", target: .command("npx", arguments: ["-y", "fs-mcp"]), agents: [.codex])))
        let ran = runner.ran.withLock { $0 }
        #expect(ran.contains("claude mcp add -s user --transport http sentry https://mcp.sentry.dev/mcp"))
        #expect(ran.contains("codex mcp add sentry --url https://mcp.sentry.dev/mcp"))
        #expect(ran.contains("codex mcp add files -- npx -y fs-mcp"))
        #expect(!ran.contains { $0.hasPrefix("claude mcp add") && $0.contains("files") })
    }

    @Test func removingAProjectServerRunsInTheProject() async throws {
        let runner = ScriptedRunner(try answers())
        let c = catalog(runner, home: try home())
        let server = Ability(agent: .claude, kind: .mcps, key: "swiftpieces", title: "swiftpieces",
                             removal: .claudeMCP(name: "swiftpieces", scope: "local"))
        await c.remove(server)
        #expect(runner.ran.withLock { $0.contains("claude mcp remove swiftpieces -s local") })
    }

    @Test func addingASkillCopiesTheFolderAndRefusesNonSkills() async throws {
        let home = try home()
        let c = catalog(ScriptedRunner(try answers()), home: home)
        let folder = FileManager.default.temporaryDirectory.appending(path: "notes-skill-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var said: [String] = []
        c.report = { said.append($0) }
        await c.addSkill(from: folder, for: .claude)
        #expect(said.last?.contains("no SKILL.md") == true)
        try "---\nname: notes\n---".write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        await c.addSkill(from: folder, for: .claude)
        #expect(FileManager.default.fileExists(atPath: home.appending(path: ".claude/skills/\(folder.lastPathComponent)/SKILL.md").path))
        #expect(c.list(.skills).contains { $0.agent == .claude && $0.title == "notes" && $0.removal != nil })
    }
}
