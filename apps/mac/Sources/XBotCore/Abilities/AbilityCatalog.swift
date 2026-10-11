import Foundation
import Observation

/// Everything on the Abilities page, and every change made from it. Reads go to the agents' CLIs
/// and folders each time — after every change as well — so the page never disagrees with what the
/// agents will load.
@MainActor @Observable
public final class AbilityCatalog {
    /// An agent's CLI, ready to run: where it is and the environment it needs (the login PATH).
    public struct Tool: Sendable {
        public let executable: URL
        public let environment: [String: String]
        public init(executable: URL, environment: [String: String]) {
            self.executable = executable; self.environment = environment
        }
    }

    public private(set) var items: [AbilityKind: [Ability]] = [:]
    /// Kinds still being read. The connector health check is slow: it connects to every server.
    public private(set) var loading: Set<AbilityKind> = []
    /// Abilities with a change in flight; their controls wait.
    public private(set) var busy: Set<String> = []
    public private(set) var marketplace: [MarketplacePlugin] = []
    public private(set) var isLoadingMarketplace = false
    public private(set) var installing: Set<String> = []
    /// Agents with no CLI on this Mac: nothing of theirs can be shown.
    public var missingAgents: [HarnessKind] { HarnessKind.allCases.filter { tools()[$0] == nil } }

    @ObservationIgnored private let runner: any CommandRunner
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let tools: () -> [HarnessKind: Tool]
    @ObservationIgnored private let project: () -> URL?
    /// Short sentences for the toast: what happened, or the CLI's reason it did not.
    @ObservationIgnored public var report: (String) -> Void = { _ in }

    public init(runner: any CommandRunner = ProcessRunner(),
                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                tools: @escaping () -> [HarnessKind: Tool], project: @escaping () -> URL?) {
        self.runner = runner; self.home = home; self.tools = tools; self.project = project
    }

    public func list(_ kind: AbilityKind) -> [Ability] { items[kind] ?? [] }

    private var codexConfig: URL { home.appending(path: ".codex/config.toml") }

    // MARK: Reading

    public func refresh() async {
        loading = Set(AbilityKind.allCases)
        async let claudePlugins = readClaudePlugins()
        async let codexPlugins = readCodexPlugins()
        async let codexMCPs = readCodexMCPs()
        let plugins = await claudePlugins + codexPlugins
        items[.plugins] = plugins
        loading.remove(.plugins)
        items[.skills] = readSkills(plugins: plugins)
        loading.remove(.skills)
        let claudeMCPs = readClaudeMCPs()
        items[.mcps] = claudeMCPs + (await codexMCPs)
        loading.remove(.mcps)

        // Last, and slowest: it connects to each server to say how it is.
        let health = await readClaudeHealth()
        items[.connectors] = AbilityParsing.claudeConnectors(health)
        let byName = Dictionary(health.map { ($0.name, $0.status) }, uniquingKeysWith: { a, _ in a })
        items[.mcps] = (items[.mcps] ?? []).map { item in
            var item = item
            if item.agent == .claude { item.status = byName[item.key] }
            return item
        }
        loading.remove(.connectors)
    }

    private func run(_ agent: HarnessKind, _ arguments: [String], timeout: Duration = .seconds(60),
                     in directory: URL? = nil) async -> CommandResult? {
        guard let tool = tools()[agent] else { return nil }
        return await runner.run(tool.executable, arguments, environment: tool.environment,
                                directory: directory, timeout: timeout)
    }

    private func readClaudePlugins() async -> [Ability] {
        guard let result = await run(.claude, ["plugin", "list", "--json"]), result.succeeded else { return [] }
        return AbilityParsing.claudePlugins(Data(result.output.utf8))
    }

    private func readCodexPlugins() async -> [Ability] {
        guard let result = await run(.codex, ["plugin", "list", "--json"]), result.succeeded else { return [] }
        return AbilityParsing.codexPlugins(Data(result.output.utf8))
    }

    private func readCodexMCPs() async -> [Ability] {
        guard let result = await run(.codex, ["mcp", "list", "--json"]), result.succeeded else { return [] }
        let config = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
        return AbilityParsing.codexMCPs(Data(result.output.utf8), configured: AbilityParsing.codexConfiguredServers(config))
    }

    private func readClaudeMCPs() -> [Ability] {
        guard tools()[.claude] != nil, let data = try? Data(contentsOf: home.appending(path: ".claude.json")) else { return [] }
        return AbilityParsing.claudeMCPs(data, project: project())
    }

    private func readClaudeHealth() async -> [AbilityParsing.HealthLine] {
        guard let result = await run(.claude, ["mcp", "list"], timeout: .seconds(90), in: project()) else { return [] }
        return AbilityParsing.claudeHealth(result.output)
    }

    /// Skills: the person's own, the project's, those synced from claude.ai, those Codex has built
    /// in, and those that come with a plugin.
    private func readSkills(plugins: [Ability]) -> [Ability] {
        var skills: [Ability] = []
        let tools = tools()
        if tools[.claude] != nil {
            let root = home.appending(path: ".claude/skills")
            skills += SkillFolder.skills(in: root, agent: .claude, source: String(localized: "Your skills"),
                                         removable: true,
                                         fixedReason: String(localized: "Claude Code loads every skill it finds; remove it to stop."))
            for bucket in SkillFolder.subfolders(of: root.appending(path: "synced")) {
                skills += SkillFolder.skills(in: bucket, agent: .claude, source: String(localized: "Synced from claude.ai"),
                                             removable: false,
                                             fixedReason: String(localized: "Synced skills are managed on claude.ai."))
            }
            if let project = project() {
                skills += SkillFolder.skills(in: project.appending(path: ".claude/skills"), agent: .claude,
                                             source: project.lastPathComponent, removable: true,
                                             fixedReason: String(localized: "Claude Code loads every skill it finds; remove it to stop."))
            }
        }
        if tools[.codex] != nil {
            let disabled = AbilityParsing.codexDisabledSkills((try? String(contentsOf: codexConfig, encoding: .utf8)) ?? "")
            let root = home.appending(path: ".codex/skills")
            skills += SkillFolder.skills(in: root, agent: .codex, source: String(localized: "Your skills"),
                                         removable: true, codexDisabled: disabled)
            skills += SkillFolder.skills(in: root.appending(path: ".system"), agent: .codex,
                                         source: String(localized: "Built into Codex"), removable: false,
                                         codexDisabled: disabled)
        }
        for plugin in plugins {
            guard let folder = plugin.location else { continue }
            skills += SkillFolder.skills(
                in: folder.appending(path: "skills"), agent: plugin.agent,
                source: String(localized: "From \(plugin.title)"), removable: false,
                fixedReason: String(localized: "Comes with the \(plugin.title) plugin: switch the plugin off instead.")
            ).map { skill in
                var skill = skill
                skill.enabled = plugin.enabled
                return skill
            }
        }
        return skills
    }

    // MARK: Changing

    public func setEnabled(_ ability: Ability, _ enabled: Bool) async {
        guard let toggle = ability.toggle, !busy.contains(ability.id) else { return }
        busy.insert(ability.id)
        defer { busy.remove(ability.id) }
        // Shown at once; put back if the change does not take.
        replace(ability.id) { $0.enabled = enabled }
        let failure: String?
        switch toggle {
        case .claudePlugin(let id):
            let scope = if case .claudePlugin(_, let s) = ability.removal { s } else { "user" }
            failure = await command(.claude, ["plugin", enabled ? "enable" : "disable", id, "-s", scope])
        case .codexPlugin(let id):
            failure = await editCodexConfig { CodexConfig.setEnabled(enabled, table: CodexConfig.header("plugins", id), in: $0) }
        case .codexMCP(let name):
            failure = await editCodexConfig { CodexConfig.setEnabled(enabled, table: CodexConfig.header("mcp_servers", name), in: $0) }
        case .codexSkill(let path):
            failure = await editCodexConfig { CodexConfig.setSkillEnabled(enabled, path: path, in: $0) }
        }
        if let failure {
            replace(ability.id) { $0.enabled = !enabled }
            report(String(localized: "Couldn't change \(ability.title): \(failure)"))
        } else if ability.kind == .plugins {
            // A plugin's skills follow it.
            items[.skills] = readSkills(plugins: list(.plugins))
        }
    }

    public func remove(_ ability: Ability) async {
        guard let removal = ability.removal, !busy.contains(ability.id) else { return }
        busy.insert(ability.id)
        defer { busy.remove(ability.id) }
        let failure: String?
        switch removal {
        case .claudePlugin(let id, let scope):
            failure = await command(.claude, ["plugin", "uninstall", id, "-s", scope, "-y"], timeout: .seconds(120))
        case .codexPlugin(let id):
            failure = await command(.codex, ["plugin", "remove", id], timeout: .seconds(120))
        case .claudeMCP(let name, let scope):
            failure = await command(.claude, ["mcp", "remove", name, "-s", scope], in: scope == "local" ? project() : nil)
        case .codexMCP(let name):
            failure = await command(.codex, ["mcp", "remove", name])
        case .trash(let url):
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil); failure = nil }
            catch { failure = error.localizedDescription }
        }
        if let failure {
            report(String(localized: "Couldn't remove \(ability.title): \(failure)"))
        } else {
            report(String(localized: "Removed \(ability.title)"))
            await refresh()
        }
    }

    public func loadMarketplace() async {
        isLoadingMarketplace = true
        defer { isLoadingMarketplace = false }
        async let claude = run(.claude, ["plugin", "list", "--available", "--json"], timeout: .seconds(120))
        async let codex = run(.codex, ["plugin", "list", "--available", "--json"], timeout: .seconds(120))
        let (c, x) = await (claude, codex)
        marketplace = (c.flatMap { $0.succeeded ? AbilityParsing.marketplace(Data($0.output.utf8), agent: .claude) : nil } ?? [])
            + (x.flatMap { $0.succeeded ? AbilityParsing.marketplace(Data($0.output.utf8), agent: .codex) : nil } ?? [])
    }

    public func install(_ plugin: MarketplacePlugin) async {
        guard !installing.contains(plugin.id) else { return }
        installing.insert(plugin.id)
        defer { installing.remove(plugin.id) }
        let arguments = plugin.agent == .claude
            ? ["plugin", "install", plugin.pluginID, "-s", "user"]
            : ["plugin", "add", plugin.pluginID]
        if let failure = await command(plugin.agent, arguments, timeout: .seconds(300)) {
            report(String(localized: "Couldn't install \(plugin.name): \(failure)"))
            return
        }
        report(String(localized: "Installed \(plugin.name)"))
        marketplace = marketplace.map { $0.id == plugin.id
            ? MarketplacePlugin(agent: $0.agent, pluginID: $0.pluginID, name: $0.name, marketplace: $0.marketplace,
                                summary: $0.summary, installed: true)
            : $0 }
        await refresh()
    }

    /// Adds the server to each chosen agent. True when every one took it.
    @discardableResult
    public func addMCP(_ server: NewMCPServer) async -> Bool {
        let name = server.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !server.agents.isEmpty else { return false }
        var ok = true
        for agent in HarnessKind.allCases where server.agents.contains(agent) {
            let arguments: [String]
            switch (agent, server.target) {
            case (.claude, .command(let command, let args)): arguments = ["mcp", "add", "-s", "user", name, "--", command] + args
            case (.claude, .url(let url)): arguments = ["mcp", "add", "-s", "user", "--transport", "http", name, url]
            case (.codex, .command(let command, let args)): arguments = ["mcp", "add", name, "--", command] + args
            case (.codex, .url(let url)): arguments = ["mcp", "add", name, "--url", url]
            }
            if let failure = await command(agent, arguments) {
                report(String(localized: "\(agent.displayName) didn't add \(name): \(failure)"))
                ok = false
            }
        }
        if ok { report(String(localized: "Added \(name)")) }
        await refresh()
        return ok
    }

    /// Copies a folder holding a SKILL.md into the agent's skills folder.
    public func addSkill(from folder: URL, for agent: HarnessKind) async {
        guard FileManager.default.fileExists(atPath: folder.appending(path: "SKILL.md").path) else {
            report(String(localized: "That folder has no SKILL.md, so it isn't a skill."))
            return
        }
        let root = home.appending(path: agent == .claude ? ".claude/skills" : ".codex/skills")
        let destination = root.appending(path: folder.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            report(String(localized: "\(agent.displayName) already has a skill named \(folder.lastPathComponent)."))
            return
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: folder, to: destination)
            report(String(localized: "Added the \(folder.lastPathComponent) skill to \(agent.displayName)"))
        } catch {
            report(String(localized: "Couldn't add the skill: \(error.localizedDescription)"))
        }
        items[.skills] = readSkills(plugins: list(.plugins))
    }

    // MARK: Helpers

    /// Nil when it worked; otherwise the reason.
    private func command(_ agent: HarnessKind, _ arguments: [String], timeout: Duration = .seconds(60),
                         in directory: URL? = nil) async -> String? {
        guard let result = await run(agent, arguments, timeout: timeout, in: directory) else {
            return String(localized: "\(agent.displayName) isn't installed.")
        }
        return result.succeeded ? nil : result.reason
    }

    /**
     Changes Codex's config, then has Codex load it. If Codex refuses the result, the file goes back
     exactly as it was and Codex's reason is returned: a config Codex cannot read stops it from
     starting at all, in xBot and in the person's terminal alike.
     */
    private func editCodexConfig(_ change: (String) -> String) async -> String? {
        let existed = FileManager.default.fileExists(atPath: codexConfig.path)
        let current = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
        do {
            try FileManager.default.createDirectory(at: codexConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
            try change(current).write(to: codexConfig, atomically: true, encoding: .utf8)
        } catch {
            return error.localizedDescription
        }
        guard let check = await run(.codex, ["mcp", "list", "--json"]), !check.succeeded else { return nil }
        if existed {
            try? current.write(to: codexConfig, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: codexConfig)
        }
        return check.reason
    }

    private func replace(_ id: String, _ change: (inout Ability) -> Void) {
        for kind in AbilityKind.allCases {
            guard let index = items[kind]?.firstIndex(where: { $0.id == id }) else { continue }
            change(&items[kind]![index])
        }
    }
}

/// Skill folders on disk: every `*/SKILL.md` directly inside a folder.
enum SkillFolder {
    static func subfolders(of folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().map { folder.appending(path: $0) }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    static func skills(in folder: URL, agent: HarnessKind, source: String, removable: Bool,
                       fixedReason: String? = nil, codexDisabled: Set<String>? = nil) -> [Ability] {
        subfolders(of: folder).compactMap { dir in
            let file = dir.appending(path: "SKILL.md")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            let meta = AbilityParsing.skillFrontMatter(text)
            let path = file.path(percentEncoded: false)
            let name = meta.name ?? dir.lastPathComponent
            return Ability(
                agent: agent, kind: .skills, key: path, title: name, source: source, summary: meta.description,
                enabled: codexDisabled.map { !$0.contains(path) },
                toggle: codexDisabled == nil ? nil : .codexSkill(path: path),
                fixedReason: codexDisabled == nil ? fixedReason : nil,
                location: dir, removal: removable ? .trash(dir) : nil
            )
        }
    }
}
