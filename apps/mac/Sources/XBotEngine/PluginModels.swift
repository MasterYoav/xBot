import Foundation

/// A tool one MCP server offers, as the Plugins page sees it.
public struct PluginTool: Sendable, Hashable, Identifiable {
    public var id: String { ref }
    public var serverID: String
    public var name: String
    public var summary: String
    /// `<serverId>/<name>`. What a grant names.
    public var ref: String
    public var effect: Effect
    public var grantedTo: [Agent.ID]

    public enum Effect: String, Sendable, Hashable {
        case read, write
    }

    public init(
        serverID: String,
        name: String,
        summary: String,
        ref: String,
        effect: Effect,
        grantedTo: [Agent.ID]
    ) {
        self.serverID = serverID
        self.name = name
        self.summary = summary
        self.ref = ref
        self.effect = effect
        self.grantedTo = grantedTo
    }
}

public struct PluginServer: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var vendor: String
    public var url: String
    public var summary: String
    public var docsURL: String
    public var hasCredential: Bool
    public var toolsRefreshedAt: String?
    public var lastError: String?
    public var dynamicClient: Bool
    public var tools: [PluginTool]

    public init(
        id: String,
        title: String,
        vendor: String,
        url: String,
        summary: String,
        docsURL: String,
        hasCredential: Bool,
        toolsRefreshedAt: String?,
        lastError: String?,
        dynamicClient: Bool,
        tools: [PluginTool]
    ) {
        self.id = id
        self.title = title
        self.vendor = vendor
        self.url = url
        self.summary = summary
        self.docsURL = docsURL
        self.hasCredential = hasCredential
        self.toolsRefreshedAt = toolsRefreshedAt
        self.lastError = lastError
        self.dynamicClient = dynamicClient
        self.tools = tools
    }
}

public struct PluginSkill: Sendable, Hashable, Identifiable {
    public var id: String
    public var slug: String
    public var title: String
    public var summary: String
    public var instructions: String
    public var grantedTo: [Agent.ID]
    public var tools: [String]

    public init(
        id: String,
        slug: String,
        title: String,
        summary: String,
        instructions: String,
        grantedTo: [Agent.ID],
        tools: [String]
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.summary = summary
        self.instructions = instructions
        self.grantedTo = grantedTo
        self.tools = tools
    }
}

public struct CatalogueItem: Sendable, Hashable, Identifiable {
    public var id: String { key }
    public var key: String
    public var title: String
    public var vendor: String
    public var summary: String
    public var docsURL: String
    public var auth: AuthKind
    public var perInstance: Bool

    public enum AuthKind: String, Sendable, Hashable {
        case none
        case deploymentBearer = "deployment-bearer"
        case userOAuth = "user-oauth"
        case builtin
    }

    public init(
        key: String,
        title: String,
        vendor: String,
        summary: String,
        docsURL: String,
        auth: AuthKind,
        perInstance: Bool
    ) {
        self.key = key
        self.title = title
        self.vendor = vendor
        self.summary = summary
        self.docsURL = docsURL
        self.auth = auth
        self.perInstance = perInstance
    }
}

/// Everything the Plugins admin page draws.
public struct PluginsPage: Sendable, Hashable {
    public var catalogue: [CatalogueItem]
    public var servers: [PluginServer]
    public var skills: [PluginSkill]
    public var botsMayCallBack: Bool
    public var redirectURI: String?

    public init(
        catalogue: [CatalogueItem],
        servers: [PluginServer],
        skills: [PluginSkill],
        botsMayCallBack: Bool,
        redirectURI: String?
    ) {
        self.catalogue = catalogue
        self.servers = servers
        self.skills = skills
        self.botsMayCallBack = botsMayCallBack
        self.redirectURI = redirectURI
    }
}

/// What one agent holds — the runtime offers exactly this.
public struct GrantedPlugins: Sendable, Hashable {
    public struct GrantedTool: Sendable, Hashable, Identifiable {
        public var id: String { ref }
        public var ref: String
        public var toolName: String
        public var summary: String

        public init(ref: String, toolName: String, summary: String) {
            self.ref = ref
            self.toolName = toolName
            self.summary = summary
        }
    }

    public struct GrantedSkill: Sendable, Hashable, Identifiable {
        public var id: String { slug }
        public var slug: String
        public var title: String
        public var summary: String
        public var instructions: String

        public init(slug: String, title: String, summary: String, instructions: String) {
            self.slug = slug
            self.title = title
            self.summary = summary
            self.instructions = instructions
        }
    }

    public var tools: [GrantedTool]
    public var skills: [GrantedSkill]

    public init(tools: [GrantedTool], skills: [GrantedSkill]) {
        self.tools = tools
        self.skills = skills
    }
}

public enum PluginGrantKind: String, Sendable {
    case mcp, skill, bot
}

/// Which agents this one may hand work to — directional, not reciprocal.
public struct HandoffGrants: Sendable, Hashable {
    public var enabled: Bool
    public var canGrant: Bool
    public var reachable: [Agent.ID]
    public var grantable: Bool

    public init(
        enabled: Bool,
        canGrant: Bool,
        reachable: [Agent.ID],
        grantable: Bool
    ) {
        self.enabled = enabled
        self.canGrant = canGrant
        self.reachable = reachable
        self.grantable = grantable
    }
}
