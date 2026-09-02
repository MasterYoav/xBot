import Foundation

/// Everything the engine needs, rendered from app settings.
///
/// The user never sees this and never edits a file. Upstream's configuration surface is an `.env`
/// with well over a hundred settings; ours is a settings pane, and this is the translation. Every
/// new upstream setting is a decision — expose it, default it, or ignore it — and the decision
/// belongs here where it is visible, not scattered across call sites.
public struct EngineEnvironment: Sendable {
    public struct Inputs: Sendable {
        public var port: UInt16
        public var keyEncryptionKey: String
        public var hostGateway: String
        public var appOrigin: String
        /// Nil runs on local history (ADR-0001). Set runs on CopilotKit Intelligence.
        public var intelligence: Intelligence?
        public var maxBrowsers: Int
        public var auditRetentionDays: Int?
        /// Off unless the user asked in Advanced. See the warning below.
        public var allowPrivateHosts: Bool
        /// Bearer token the engine requires when xBot owns the deployment.
        public var engineToken: String?

        public init(
            port: UInt16,
            keyEncryptionKey: String,
            hostGateway: String,
            appOrigin: String,
            intelligence: Intelligence? = nil,
            maxBrowsers: Int = 1,
            auditRetentionDays: Int? = nil,
            allowPrivateHosts: Bool = false,
            engineToken: String? = nil
        ) {
            self.port = port
            self.keyEncryptionKey = keyEncryptionKey
            self.hostGateway = hostGateway
            self.appOrigin = appOrigin
            self.intelligence = intelligence
            self.maxBrowsers = maxBrowsers
            self.auditRetentionDays = auditRetentionDays
            self.allowPrivateHosts = allowPrivateHosts
            self.engineToken = engineToken
        }
    }

    public struct Intelligence: Sendable {
        public var apiURL: String
        public var gatewayWsURL: String
        public var apiKey: String
        public var licenseToken: String

        public init(apiURL: String, gatewayWsURL: String, apiKey: String, licenseToken: String) {
            self.apiURL = apiURL
            self.gatewayWsURL = gatewayWsURL
            self.apiKey = apiKey
            self.licenseToken = licenseToken
        }
    }

    /// How much RAM to let agents spend on browsers, from what the machine actually has.
    ///
    /// Postgres plus the engine plus one Chromium is 1.5–2.5 GB. Three agents on an 8 GB Mac is a
    /// bad experience that reads as "this app is heavy" rather than "I asked for too much", so the
    /// cap is set for the user rather than offered to them.
    public static func browserLimit(forPhysicalMemory bytes: UInt64) -> Int {
        let gigabytes = Double(bytes) / 1_073_741_824
        return switch gigabytes {
        case ..<12: 1
        case ..<24: 2
        default: 4
        }
    }

    public static func compose(_ inputs: Inputs) -> [String: String] {
        var environment: [String: String] = [
            // The embedded database. One container, one port, one process tree.
            "EMBEDDED_POSTGRES": "on",
            "DATABASE_URL": "postgres://openbot:openbot@127.0.0.1:5432/openbot",

            // Both, and identical: upstream refuses to start if they disagree.
            "PORT": "\(inputs.port)",
            "SERVER_PORT": "\(inputs.port)",

            // Generated per install and held in the Keychain. Upstream's example key is public
            // and it warns about exactly this; a shipped app using it would encrypt every user's
            // credential vault with a key printed in a public repository.
            "KEY_ENCRYPTION_KEY": inputs.keyEncryptionKey,

            // One local user. The bearer token is what actually guards the port — loopback is not
            // a boundary against another process on the same Mac.
            "OPENBOT_SINGLE_USER": "true",
            "TRUSTED_ORIGINS": inputs.appOrigin,

            // Built from the driver, never hardcoded. This is also the path the user's local
            // Ollama is reached on, and getting it wrong presents as a model problem.
            "OPENBOT_TOOL_URL": "http://\(inputs.hostGateway):\(inputs.port)",

            "COMPUTER_MAX_BROWSERS": "\(inputs.maxBrowsers)",
        ]

        if let intelligence = inputs.intelligence {
            environment["INTELLIGENCE_API_URL"] = intelligence.apiURL
            environment["INTELLIGENCE_GATEWAY_WS_URL"] = intelligence.gatewayWsURL
            environment["INTELLIGENCE_API_KEY"] = intelligence.apiKey
            environment["COPILOTKIT_LICENSE_TOKEN"] = intelligence.licenseToken
        }
        // Otherwise all four stay unset, which selects local history. A partial set is refused by
        // the engine, so this is deliberately all-or-nothing rather than field by field.

        if let days = inputs.auditRetentionDays {
            environment["AUDIT_RETENTION_DAYS"] = "\(days)"
        }
        // Unset keeps everything, which is the right default: deleting somebody's audit trail
        // because a default said so is the worse of the two failures.

        if inputs.allowPrivateHosts {
            // ⚠️ This removes the whole private-address floor, not one rule — an agent can then
            // reach link-local addresses including cloud metadata endpoints. Off by default,
            // exposed in Advanced with a plain description, and never switched on to fix an
            // unrelated problem.
            environment["AGENT_COMPUTER_ALLOW_PRIVATE_HOSTS"] = "true"
        }

        if let engineToken = inputs.engineToken {
            environment["XBOT_ENGINE_TOKEN"] = engineToken
        }

        return environment
    }

    /// Environment keys whose values must never leave the machine.
    public static let secretKeys: Set<String> = [
        "KEY_ENCRYPTION_KEY",
        "INTELLIGENCE_API_KEY",
        "COPILOTKIT_LICENSE_TOKEN",
        "DATABASE_URL",
        "XBOT_ENGINE_TOKEN",
        "COMPUTER_TOKEN",
        "SUPERVISOR_TOKEN",
        "AGENT_TOOL_TOKEN",
        "WORKER_SHARED_SECRET",
        "MANAGED_AGENT_TOKEN",
        "BETTER_AUTH_SECRET",
    ]
}
