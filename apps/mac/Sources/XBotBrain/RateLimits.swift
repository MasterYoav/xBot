import Foundation

/// One usage window: how much of it is used, and when it starts over.
public struct RateWindow: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var resetsAt: Date

    public init(usedPercent: Double, resetsAt: Date) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// An agent's subscription limits as the agent itself last reported them. No credentials involved:
/// Claude Code prints them in every turn's stream; Codex writes them into its session logs.
public struct RateLimits: Codable, Equatable, Sendable {
    public var fiveHour: RateWindow?
    public var weekly: RateWindow?
    public var plan: String?

    public init(fiveHour: RateWindow?, weekly: RateWindow?, plan: String? = nil) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.plan = plan
    }
}

public enum CodexUsage {
    public static var sessions: URL { URL.homeDirectory.appending(path: ".codex/sessions") }

    /// The newest session log that has limits in it. A session that just started has none yet, so
    /// a few are tried; only the last 512 KB of each is read.
    public static func latest(in root: URL = sessions) -> RateLimits? {
        for file in newestRollouts(in: root, limit: 5) {
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > 524_288 ? size - 524_288 : 0)
            let text = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
            for line in text.split(separator: "\n").reversed() {
                if let limits = limits(fromLine: String(line)) { return limits }
            }
        }
        return nil
    }

    static func limits(fromLine line: String) -> RateLimits? {
        guard line.contains("\"rate_limits\""), let object = jsonObject(line),
              let payload = object["payload"] as? [String: Any],
              let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        func window(_ key: String) -> RateWindow? {
            guard let w = limits[key] as? [String: Any],
                  let used = (w["used_percent"] as? NSNumber)?.doubleValue,
                  let reset = (w["resets_at"] as? NSNumber)?.doubleValue else { return nil }
            return RateWindow(usedPercent: used, resetsAt: Date(timeIntervalSince1970: reset))
        }
        let result = RateLimits(fiveHour: window("primary"), weekly: window("secondary"),
                                plan: (limits["plan_type"] as? String).flatMap(planName))
        return result.fiveHour == nil && result.weekly == nil ? nil : result
    }

    static func planName(_ type: String) -> String? {
        switch type {
        case "plus": "ChatGPT Plus"
        case "pro": "ChatGPT Pro"
        case "team": "ChatGPT Team"
        case "business": "ChatGPT Business"
        case "enterprise": "ChatGPT Enterprise"
        default: nil
        }
    }

    /// `sessions/YYYY/MM/DD/rollout-<time>-<id>.jsonl`, newest first: the names sort by time.
    static func newestRollouts(in root: URL, limit: Int) -> [URL] {
        func entries(_ url: URL) -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        var found: [URL] = []
        for year in entries(root) {
            for month in entries(year) {
                for day in entries(month) {
                    found += entries(day).filter { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
                    if found.count >= limit { return Array(found.prefix(limit)) }
                }
            }
        }
        return found
    }
}

public enum ClaudeAccount {
    public static var config: URL { URL.homeDirectory.appending(path: ".claude.json") }

    /// "Claude Max", from the account summary Claude Code keeps beside its settings. Only the
    /// account block is looked at; the file holds no secrets.
    public static func plan(at url: URL = config) -> String? {
        switch account(at: url)?["organizationType"] as? String {
        case "claude_max": "Claude Max"
        case "claude_pro": "Claude Pro"
        case "claude_team": "Claude Team"
        case "claude_enterprise": "Claude Enterprise"
        default: nil
        }
    }

    public static func isSignedIn(at url: URL = config) -> Bool { account(at: url) != nil }

    private static func account(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["oauthAccount"] as? [String: Any]
    }
}
