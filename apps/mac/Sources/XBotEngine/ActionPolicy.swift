import Foundation

/// Whether the computer boundary acts on its verdict. See engine `ActionPolicy`.
public enum PolicyMode: String, Codable, Sendable, CaseIterable {
    case enforce
    case dryRun = "dry-run"
}

/// Deployment-wide rules agents' browser actions are judged against.
public struct ActionPolicy: Codable, Sendable, Equatable {
    public var mode: PolicyMode
    public var deny: [String]
    public var allow: [String]

    public init(mode: PolicyMode = .enforce, deny: [String] = [], allow: [String] = ["true"]) {
        self.mode = mode
        self.deny = deny
        self.allow = allow
    }

    public static let `default` = ActionPolicy()
}

public struct PolicyDryRunChange: Codable, Sendable, Equatable {
    public let id: String
    public let action: String
    public let bot: String
    public let page: String
    public let was: String
    public let would: String
    public let rule: String?
    public let reason: String
}

public struct PolicyDryRunReport: Codable, Sendable, Equatable {
    public let scanned: Int
    public let wouldRefuse: Int
    public let wouldAllow: Int
    public let unchanged: Int
    public let changes: [PolicyDryRunChange]
}
