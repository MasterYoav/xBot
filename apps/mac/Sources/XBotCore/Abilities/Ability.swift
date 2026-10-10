import Foundation

/// What an agent can use beyond its model: an account's connectors, installed plugins, skills and
/// MCP servers. Read from, and changed through, the agents' own CLIs and folders — xBot keeps no
/// list of its own, so what the page shows is what the agents will actually load.
public enum AbilityKind: String, CaseIterable, Sendable {
    case connectors, plugins, skills, mcps

    public var title: String {
        switch self {
        case .connectors: String(localized: "Connectors")
        case .plugins: String(localized: "Plugins")
        case .skills: String(localized: "Skills")
        case .mcps: String(localized: "MCPs")
        }
    }
}

public struct Ability: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case connected, needsSignIn, failed, pending
    }

    /// How an ability is switched on and off — which CLI or file owns that switch.
    public enum Switch: Equatable, Sendable {
        case claudePlugin(id: String)
        case codexPlugin(id: String)
        case codexMCP(name: String)
        case codexSkill(path: String)
    }

    /// How an ability is removed.
    public enum Removal: Equatable, Sendable {
        case claudePlugin(id: String, scope: String)
        case codexPlugin(id: String)
        case claudeMCP(name: String, scope: String)
        case codexMCP(name: String)
        /// A skill folder the person put there: moved to the Trash, never deleted.
        case trash(URL)
    }

    public var id: String { "\(agent.rawValue)/\(kind.rawValue)/\(key)" }
    public let agent: HarnessKind
    public let kind: AbilityKind
    /// The name the CLI knows it by: "superpowers@claude-plugins-official", an MCP server's name.
    public let key: String
    public var title: String
    /// Where it comes from: a marketplace, a scope, the plugin that brings it.
    public var source: String?
    public var summary: String?
    /// Nil: it cannot be switched off on its own (see `fixedReason`).
    public var enabled: Bool?
    public var toggle: Switch?
    /// Why there is no switch, said on hover.
    public var fixedReason: String?
    public var status: Status?
    public var icon: URL?
    public var location: URL?
    public var removal: Removal?

    public init(agent: HarnessKind, kind: AbilityKind, key: String, title: String, source: String? = nil,
                summary: String? = nil, enabled: Bool? = nil, toggle: Switch? = nil, fixedReason: String? = nil,
                status: Status? = nil, icon: URL? = nil, location: URL? = nil, removal: Removal? = nil) {
        self.agent = agent; self.kind = kind; self.key = key; self.title = title; self.source = source
        self.summary = summary; self.enabled = enabled; self.toggle = toggle; self.fixedReason = fixedReason
        self.status = status; self.icon = icon; self.location = location; self.removal = removal
    }

    /// For search: everything a person might type to find it.
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [title, key, source ?? "", summary ?? "", agent.displayName]
            .contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

/// A plugin a marketplace offers, for Browse.
public struct MarketplacePlugin: Identifiable, Equatable, Sendable {
    public var id: String { "\(agent.rawValue)/\(pluginID)" }
    public let agent: HarnessKind
    public let pluginID: String
    public let name: String
    public let marketplace: String
    public let summary: String?
    public let installed: Bool
}

/// An MCP server to add: a command to start, or a URL to reach.
public struct NewMCPServer: Equatable, Sendable {
    public enum Target: Equatable, Sendable {
        case command(String, arguments: [String])
        case url(String)
    }

    public var name: String
    public var target: Target
    public var agents: Set<HarnessKind>

    public init(name: String, target: Target, agents: Set<HarnessKind>) {
        self.name = name; self.target = target; self.agents = agents
    }
}
