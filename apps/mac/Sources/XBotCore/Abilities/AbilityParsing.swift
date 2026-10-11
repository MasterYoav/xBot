import Foundation

/// Turns what the CLIs print and keep on disk into abilities. Pure: tested against output recorded
/// from real runs (`Tests/XBotCoreTests/Fixtures/abilities`).
public enum AbilityParsing {
    // MARK: Plugins

    /// `claude plugin list --json`. A plugin installed at more than one scope appears once per scope;
    /// the user-scope entry is the one shown, because that is the one `enable`/`disable` act on.
    public static func claudePlugins(_ data: Data, manifest: (URL) -> PluginManifest? = PluginManifest.read) -> [Ability] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var byID: [String: [String: Any]] = [:]
        var order: [String] = []
        for row in rows {
            guard let id = row["id"] as? String else { continue }
            if byID[id] == nil { order.append(id) }
            if byID[id] == nil || row["scope"] as? String == "user" { byID[id] = row }
        }
        return order.compactMap { id in
            guard let row = byID[id] else { return nil }
            let scope = row["scope"] as? String ?? "user"
            let path = (row["installPath"] as? String).map { URL(filePath: $0) }
            let info = path.flatMap(manifest)
            let (name, marketplace) = splitID(id)
            // Synced from the person's claude.ai account: the CLI can neither switch nor remove them.
            let synced = scope == "synced"
            return Ability(
                agent: .claude, kind: .plugins, key: id, title: info?.displayName ?? displayName(name),
                source: synced ? String(localized: "Synced from claude.ai") : marketplace, summary: info?.summary,
                enabled: row["enabled"] as? Bool ?? true, toggle: synced ? nil : .claudePlugin(id: id),
                fixedReason: synced ? String(localized: "Synced plugins are managed on claude.ai.") : nil,
                icon: info?.icon, location: path, removal: synced ? nil : .claudePlugin(id: id, scope: scope)
            )
        }
    }

    /// `codex plugin list --json`, `installed` only.
    public static func codexPlugins(_ data: Data, manifest: (URL) -> PluginManifest? = PluginManifest.read) -> [Ability] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["installed"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let id = row["pluginId"] as? String, row["installed"] as? Bool != false else { return nil }
            let path = ((row["source"] as? [String: Any])?["path"] as? String).map { URL(filePath: $0) }
            let info = path.flatMap(manifest)
            let name = row["name"] as? String ?? splitID(id).name
            return Ability(
                agent: .codex, kind: .plugins, key: id, title: info?.displayName ?? displayName(name),
                source: row["marketplaceName"] as? String, summary: info?.summary,
                enabled: row["enabled"] as? Bool ?? true, toggle: .codexPlugin(id: id), icon: info?.icon,
                location: path, removal: .codexPlugin(id: id)
            )
        }
    }

    /// `… plugin list --available --json`: what the marketplaces offer, for Browse.
    public static func marketplace(_ data: Data, agent: HarnessKind) -> [MarketplacePlugin] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let installedIDs = Set((root["installed"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String ?? $0["pluginId"] as? String })
        return (root["available"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["pluginId"] as? String else { return nil }
            let name = row["name"] as? String ?? splitID(id).name
            let interface = row["interface"] as? [String: Any]
            return MarketplacePlugin(
                agent: agent, pluginID: id, name: interface?["displayName"] as? String ?? displayName(name),
                marketplace: row["marketplaceName"] as? String ?? splitID(id).marketplace ?? "",
                summary: row["description"] as? String ?? interface?["shortDescription"] as? String,
                installed: row["installed"] as? Bool ?? installedIDs.contains(id)
            )
        }
    }

    // MARK: MCP servers

    /// `codex mcp list --json`. Only servers with a table of their own in config.toml (`configured`)
    /// can be switched or removed: the rest come with a plugin, and an `[mcp_servers.x]` table with
    /// nothing but `enabled` in it stops Codex from starting at all ("invalid transport").
    public static func codexMCPs(_ data: Data, configured: Set<String>) -> [Ability] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let name = row["name"] as? String else { return nil }
            let transport = row["transport"] as? [String: Any] ?? [:]
            let own = configured.contains(name)
            return Ability(
                agent: .codex, kind: .mcps, key: name, title: name, source: transport["type"] as? String,
                summary: target(transport), enabled: row["enabled"] as? Bool ?? true,
                toggle: own ? .codexMCP(name: name) : nil,
                fixedReason: own ? nil : String(localized: "Comes with a Codex plugin: switch the plugin off instead."),
                removal: own ? .codexMCP(name: name) : nil
            )
        }
    }

    /// The servers with a table of their own in Codex's config: `[mcp_servers.name]`.
    public static func codexConfiguredServers(_ toml: String) -> Set<String> {
        var names = Set<String>()
        for raw in toml.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[mcp_servers."), line.hasSuffix("]"), !line.hasPrefix("[[") else { continue }
            let key = String(line.dropFirst("[mcp_servers.".count).dropLast())
            if key.hasPrefix("\""), let end = key.dropFirst().firstIndex(of: "\""), key.index(after: end) == key.endIndex {
                names.insert(String(key.dropFirst().dropLast()))
            } else if !key.contains(".") {
                names.insert(key)
            }
        }
        return names
    }

    /// Claude Code's own MCP servers, from `~/.claude.json`: the user's, and the project's (scope
    /// "local") for the project in view. Claude Code has no switch that turns a server off
    /// everywhere, so these have none either — only Remove.
    public static func claudeMCPs(_ data: Data, project: URL?) -> [Ability] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        func rows(_ servers: Any?, scope: String, source: String) -> [Ability] {
            guard let servers = servers as? [String: [String: Any]] else { return [] }
            return servers.keys.sorted().map { name in
                Ability(
                    agent: .claude, kind: .mcps, key: name, title: name, source: source,
                    summary: target(servers[name] ?? [:]),
                    fixedReason: String(localized: "Claude Code can't switch a server off without removing it."),
                    removal: .claudeMCP(name: name, scope: scope)
                )
            }
        }
        var result = rows(root["mcpServers"], scope: "user", source: String(localized: "All projects"))
        if let project, let projects = root["projects"] as? [String: [String: Any]],
           let entry = projects[project.standardizedFileURL.path(percentEncoded: false).droppingTrailing("/")] {
            result += rows(entry["mcpServers"], scope: "local", source: project.lastPathComponent)
        }
        return result
    }

    /// One line per server from `claude mcp list`: "name: target - ✔ Connected".
    public struct HealthLine: Equatable, Sendable {
        public let name: String
        public let target: String
        public let status: Ability.Status
    }

    public static func claudeHealth(_ text: String) -> [HealthLine] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let line = String(line)
            guard let colon = line.range(of: ": "), let dash = line.range(of: " - ", options: .backwards),
                  colon.upperBound <= dash.lowerBound else { return nil }
            let name = String(line[..<colon.lowerBound])
            let rest = line[dash.upperBound...]
            let status: Ability.Status =
                rest.contains("✔") ? .connected
                : rest.localizedCaseInsensitiveContains("auth") ? .needsSignIn
                : rest.contains("⏸") ? .pending
                : .failed
            return HealthLine(name: name, target: String(line[colon.upperBound..<dash.lowerBound]), status: status)
        }
    }

    /// The account's claude.ai connectors: the health lines named "claude.ai …".
    public static func claudeConnectors(_ lines: [HealthLine]) -> [Ability] {
        lines.compactMap { line in
            guard line.name.hasPrefix("claude.ai ") else { return nil }
            let title = String(line.name.dropFirst("claude.ai ".count))
            return Ability(agent: .claude, kind: .connectors, key: line.name, title: title,
                           source: String(localized: "claude.ai"), summary: host(line.target),
                           fixedReason: String(localized: "Connectors are managed on claude.ai."), status: line.status)
        }
    }

    // MARK: Skills

    /// `[[skills.config]]` entries in Codex's config: which skill files are switched off.
    public static func codexDisabledSkills(_ toml: String) -> Set<String> {
        var disabled = Set<String>()
        var inSkill = false
        var path: String?
        var enabled = true
        func flush() { if inSkill, let path, !enabled { disabled.insert(path) } }
        for raw in toml.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                flush()
                inSkill = line == "[[skills.config]]"
                path = nil; enabled = true
                continue
            }
            guard inSkill, let (key, value) = CodexConfig.assignment(line) else { continue }
            if key == "path" { path = CodexConfig.unquote(value) }
            if key == "enabled" { enabled = value != "false" }
        }
        flush()
        return disabled
    }

    /// A skill's `name` and `description` from its SKILL.md front matter.
    public static func skillFrontMatter(_ text: String) -> (name: String?, description: String?) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, nil) }
        var name: String?, description: String?
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let (key, value) = CodexConfig.assignment(line, separator: ":") else { continue }
            if key == "name" { name = CodexConfig.unquote(value) }
            if key == "description" { description = CodexConfig.unquote(value) }
        }
        return (name, description)
    }

    // MARK: Helpers

    static func splitID(_ id: String) -> (name: String, marketplace: String?) {
        guard let at = id.lastIndex(of: "@") else { return (id, nil) }
        return (String(id[..<at]), String(id[id.index(after: at)...]))
    }

    /// "swift-lsp" → "Swift Lsp", as the reference names plugins without a display name.
    static func displayName(_ name: String) -> String {
        name.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    static func target(_ entry: [String: Any]) -> String? {
        if let url = entry["url"] as? String { return url }
        guard let command = entry["command"] as? String else { return nil }
        let args = entry["args"] as? [String] ?? []
        return ([command] + args).joined(separator: " ")
    }

    static func host(_ url: String) -> String { URL(string: url)?.host() ?? url }
}

/// What a plugin says about itself: `.claude-plugin/plugin.json` or `.codex-plugin/plugin.json`.
public struct PluginManifest: Equatable, Sendable {
    public var displayName: String?
    public var summary: String?
    public var icon: URL?

    public static func read(_ folder: URL) -> PluginManifest? {
        for name in [".codex-plugin", ".claude-plugin"] {
            let file = folder.appending(path: "\(name)/plugin.json")
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let interface = json["interface"] as? [String: Any]
            let icon = (interface?["composerIcon"] as? String ?? interface?["logo"] as? String)
                .map { folder.appending(path: $0) }
                .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            return PluginManifest(
                displayName: interface?["displayName"] as? String,
                summary: interface?["shortDescription"] as? String ?? json["description"] as? String,
                icon: icon
            )
        }
        return nil
    }
}

extension String {
    func droppingTrailing(_ suffix: String) -> String {
        hasSuffix(suffix) && count > suffix.count ? String(dropLast(suffix.count)) : self
    }
}
