import Foundation

/// What "Copy diagnostics" produces.
///
/// The user never reads a log. This exists so they can send one — which means it leaves the
/// machine, which means what is in it matters more than what is convenient.
public struct Diagnostics: Sendable, Equatable {
    public var appVersion: String
    public var engineVersion: String?
    public var runtime: String
    public var runtimeVersion: String?
    public var architecture: String
    public var macOSVersion: String
    public var port: UInt16?
    public var stateHistory: [String]
    public var containerStatus: String
    public var engineLogTail: [String]
    public var driverCommands: [String]

    public init(
        appVersion: String,
        engineVersion: String? = nil,
        runtime: String,
        runtimeVersion: String? = nil,
        architecture: String,
        macOSVersion: String,
        port: UInt16? = nil,
        stateHistory: [String] = [],
        containerStatus: String = "",
        engineLogTail: [String] = [],
        driverCommands: [String] = []
    ) {
        self.appVersion = appVersion
        self.engineVersion = engineVersion
        self.runtime = runtime
        self.runtimeVersion = runtimeVersion
        self.architecture = architecture
        self.macOSVersion = macOSVersion
        self.port = port
        self.stateHistory = stateHistory
        self.containerStatus = containerStatus
        self.engineLogTail = engineLogTail
        self.driverCommands = driverCommands
    }

    public func rendered() -> String {
        var lines: [String] = [
            "xBot \(appVersion)",
            "engine \(engineVersion ?? "unknown")",
            "runtime \(runtime) \(runtimeVersion ?? "unknown")",
            "\(architecture) · macOS \(macOSVersion)",
            "port \(port.map(String.init) ?? "unallocated")",
            "container \(containerStatus)",
            "",
            "state history:",
        ]
        lines += stateHistory.map { "  \($0)" }
        lines += ["", "driver commands:"]
        lines += driverCommands.map { "  \($0)" }
        lines += ["", "engine log:"]
        lines += engineLogTail.map { "  \($0)" }
        return Redaction.scrub(lines.joined(separator: "\n"))
    }
}

/// Removes secrets from anything on its way off the machine.
///
/// A tested function, not care. The test in `RedactionTests` fails if a known secret shape
/// survives, because "we were careful" is not a property that holds across a year of edits by
/// people who have not read this comment.
public enum Redaction {
    /// Patterns matched by shape rather than by name, so a key that reaches a log through a route
    /// nobody anticipated is still caught.
    private static let patterns: [String] = [
        // Vendor key shapes.
        "sk-ant-[A-Za-z0-9_-]{16,}",
        "sk-[A-Za-z0-9]{20,}",
        "xai-[A-Za-z0-9]{16,}",
        "AIza[A-Za-z0-9_-]{20,}",
        "ghp_[A-Za-z0-9]{20,}",
        // Bearer tokens and JWTs.
        "[Bb]earer\\s+[A-Za-z0-9._~+/=-]{16,}",
        "eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}",
        // A URL carrying credentials, which is how DATABASE_URL leaks.
        "://[^/\\s:]+:[^/@\\s]+@",
        // Any assignment whose name says it is a secret, whatever the value looks like.
        "(?i)\\b[A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]*\\s*[=:]\\s*\\S+",
        // Base64 blobs long enough to be an encryption key.
        "\\b[A-Za-z0-9+/]{40,}={0,2}\\b",
    ]

    public static let placeholder = "[redacted]"

    public static func scrub(_ text: String) -> String {
        var scrubbed = text
        for pattern in patterns {
            guard
                let expression = try? NSRegularExpression(pattern: pattern)
            else { continue }
            scrubbed = expression.stringByReplacingMatches(
                in: scrubbed,
                range: NSRange(scrubbed.startIndex..., in: scrubbed),
                withTemplate: placeholder
            )
        }
        return scrubbed
    }

    /// An environment block, safe to include.
    ///
    /// Keys are kept and values are dropped for anything named as a secret. Which variables were
    /// set is genuinely useful for debugging; what they were set to never is.
    public static func scrub(environment: [String: String]) -> [String: String] {
        environment.reduce(into: [:]) { result, pair in
            result[pair.key] =
                EngineEnvironment.secretKeys.contains(pair.key)
                ? placeholder
                : scrub(pair.value)
        }
    }
}
