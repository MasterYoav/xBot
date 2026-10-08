import Foundation

public struct DayKey: Hashable, Sendable {
    public var day: String
    public var agent: HarnessKind
}

public struct DayTotal: Equatable, Sendable {
    public var tokens = 0
    public var tasks = 0
    public var longestTask: TimeInterval = 0
}

public struct CountKey: Hashable, Sendable {
    public enum Kind: String, Sendable { case tool, skill, effort }
    public var kind: Kind
    public var name: String
}

public struct ProjectTotal: Equatable, Sendable {
    public var path: String
    public var tokens: Int
    public var lastActive: Date
}

public struct NameCount: Equatable, Sendable {
    public var name: String
    public var count: Int
}

/// What one log file leaves unfinished between passes.
public struct FileCarry: Codable, Equatable, Sendable {
    /// Claude Code writes one line per content block, each repeating its message's usage.
    public var lastMessageID: String?
    public var taskStart: Date?
    public var taskDay: String?
    /// The last line of the task in progress; a long silence after it ends the task there.
    public var lastSeen: Date?
    /// Codex's running token total for the session.
    public var codexTotal = 0
    public var cwd: String?
    public var effort: String?
}

/// The arithmetic of the profile, one log line at a time. No files and no database: those are
/// the indexer's.
public struct HistoryTally: Sendable {
    public var days: [DayKey: DayTotal] = [:]
    public var counts: [CountKey: Int] = [:]
    public var projects: [String: ProjectTotal] = [:]

    public init() {}

    static let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    /// Thirty minutes without a word from the agent ends a task.
    static let idleGap: TimeInterval = 30 * 60

    /// "2026-10-08", in the calendar's time zone.
    static func day(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Claude Code's `~/.claude/projects/*/*.jsonl`. A person's message starts a task; it lasts
    /// until the last reply before the next one.
    public mutating func claude(_ line: String, carry: inout FileCarry, calendar: Calendar) {
        guard line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\""),
              let object = historyJSON(line), let stamp = object["timestamp"] as? String,
              let date = try? Self.iso.parse(stamp) else { return }
        let day = Self.day(date, calendar)
        let message = object["message"] as? [String: Any] ?? [:]
        switch object["type"] as? String {
        case "user":
            // Tool results come back as user lines too; only words from the person start a task.
            let content = message["content"]
            let isQuestion = content is String
                || ((content as? [[String: Any]])?.contains { $0["type"] as? String == "text" } ?? false)
            guard isQuestion, object["isMeta"] as? Bool != true else { return }
            carry.taskStart = date
            carry.taskDay = day
            carry.lastSeen = date
            days[DayKey(day: day, agent: .claude), default: DayTotal()].tasks += 1
        case "assistant":
            // A session left open and picked up hours later is not one long task.
            if let seen = carry.lastSeen, date.timeIntervalSince(seen) > Self.idleGap { carry.taskStart = nil }
            carry.lastSeen = date
            if let start = carry.taskStart, let taskDay = carry.taskDay {
                let key = DayKey(day: taskDay, agent: .claude)
                let longest = max(days[key]?.longestTask ?? 0, date.timeIntervalSince(start))
                days[key, default: DayTotal()].longestTask = longest
            }
            let id = message["id"] as? String
            let isNew = id == nil || id != carry.lastMessageID
            carry.lastMessageID = id
            if isNew, let usage = message["usage"] as? [String: Any] {
                let tokens = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
                    .reduce(0) { $0 + ((usage[$1] as? NSNumber)?.intValue ?? 0) }
                days[DayKey(day: day, agent: .claude), default: DayTotal()].tokens += tokens
                if let cwd = object["cwd"] as? String { addProject(cwd, tokens, date) }
                if let effort = object["effort"] as? String { counts[CountKey(kind: .effort, name: effort), default: 0] += 1 }
            }
            for block in message["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "tool_use" {
                guard let name = block["name"] as? String else { continue }
                counts[CountKey(kind: .tool, name: name), default: 0] += 1
                if name == "Skill", let skill = (block["input"] as? [String: Any])?["skill"] as? String {
                    counts[CountKey(kind: .skill, name: skill), default: 0] += 1
                }
            }
        default:
            break
        }
    }

    /// Codex's `~/.codex/sessions/**/rollout-*.jsonl`. Tokens are the growth of the session's
    /// running total, so a repeated count line adds nothing.
    public mutating func codex(_ line: String, carry: inout FileCarry, calendar: Calendar) {
        guard let object = historyJSON(line), let stamp = object["timestamp"] as? String,
              let date = try? Self.iso.parse(stamp),
              let payload = object["payload"] as? [String: Any] else { return }
        let day = Self.day(date, calendar)
        switch (object["type"] as? String, payload["type"] as? String) {
        case ("turn_context", _):
            carry.cwd = payload["cwd"] as? String ?? carry.cwd
            carry.effort = payload["effort"] as? String ?? carry.effort
        case ("response_item", "function_call"), ("response_item", "custom_tool_call"):
            if let name = payload["name"] as? String { counts[CountKey(kind: .tool, name: name), default: 0] += 1 }
        case ("event_msg", "token_count"):
            let info = payload["info"] as? [String: Any]
            guard let total = ((info?["total_token_usage"] as? [String: Any])?["total_tokens"] as? NSNumber)?.intValue else { return }
            let added = total >= carry.codexTotal ? total - carry.codexTotal : total
            carry.codexTotal = total
            guard added > 0 else { return }
            days[DayKey(day: day, agent: .codex), default: DayTotal()].tokens += added
            if let cwd = carry.cwd { addProject(cwd, added, date) }
        case ("event_msg", "task_complete"):
            let key = DayKey(day: day, agent: .codex)
            var total = days[key] ?? DayTotal()
            total.tasks += 1
            if let ms = (payload["duration_ms"] as? NSNumber)?.doubleValue { total.longestTask = max(total.longestTask, ms / 1000) }
            days[key] = total
            if let effort = carry.effort { counts[CountKey(kind: .effort, name: effort), default: 0] += 1 }
        default:
            break
        }
    }

    private mutating func addProject(_ path: String, _ tokens: Int, _ date: Date) {
        var total = projects[path] ?? ProjectTotal(path: path, tokens: 0, lastActive: date)
        total.tokens += tokens
        total.lastActive = max(total.lastActive, date)
        projects[path] = total
    }
}

/// One log line as a dictionary, or nil for anything that is not a JSON object.
private func historyJSON(_ line: String) -> [String: Any]? {
    guard line.first == "{" else { return nil }
    return (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
}
