import Foundation

public struct HistorySummary: Equatable, Sendable {
    /// "2026-10-08" → tokens, both agents together.
    public var days: [String: Int] = [:]
    public var tokensByAgent: [HarnessKind: Int] = [:]
    public var tasksByAgent: [HarnessKind: Int] = [:]
    public var longestTask: TimeInterval = 0
    public var tools: [NameCount] = []
    public var skills: [NameCount] = []
    public var efforts: [NameCount] = []
    /// By tokens, most first.
    public var projects: [ProjectTotal] = []
    /// The agents whose logs were found.
    public var found: Set<HarnessKind> = []

    public init() {}
}

/// Reads the agents' own logs into xBot's history, a little at a time: each file from where the
/// last pass stopped, and only whole lines. Nothing leaves the Mac.
public actor HistoryIndexer {
    private let db: Database
    private let claudeRoot: URL
    private let codexRoot: URL
    private let calendar: Calendar

    public init(
        database: Database,
        claude: URL = URL.homeDirectory.appending(path: ".claude/projects"),
        codex: URL = URL.homeDirectory.appending(path: ".codex/sessions"),
        calendar: Calendar = .current
    ) throws {
        db = database
        claudeRoot = claude
        codexRoot = codex
        self.calendar = calendar
        try db.execute("CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, agent TEXT NOT NULL, offset REAL NOT NULL, carry TEXT NOT NULL)")
        try db.execute("""
            CREATE TABLE IF NOT EXISTS days (day TEXT NOT NULL, agent TEXT NOT NULL, tokens REAL NOT NULL,
              tasks REAL NOT NULL, longest REAL NOT NULL, PRIMARY KEY (day, agent))
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS counts (kind TEXT NOT NULL, name TEXT NOT NULL, count REAL NOT NULL,
              PRIMARY KEY (kind, name))
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS projects (path TEXT PRIMARY KEY, tokens REAL NOT NULL, last_active REAL NOT NULL)
            """)
    }

    /// `~/Library/Application Support/xBot/history.sqlite`: derived data, rebuilt if deleted.
    public static func live() throws -> HistoryIndexer {
        try HistoryIndexer(database: Database(url: Store.supportDirectory.appending(path: "history.sqlite")))
    }

    /// One incremental pass over both agents' logs.
    public func index() {
        for file in files(claudeRoot, depth: 2) { read(file, agent: .claude) }
        for file in files(codexRoot, depth: 4) where file.lastPathComponent.hasPrefix("rollout-") {
            read(file, agent: .codex)
        }
    }

    /// `.jsonl` files exactly `depth` folders down — Claude: project/session; Codex: year/month/day/file.
    private func files(_ root: URL, depth: Int) -> [URL] {
        func list(_ url: URL) -> [URL] {
            (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        }
        var level = [root]
        for _ in 1..<depth { level = level.flatMap(list) }
        return level.flatMap(list).filter { $0.pathExtension == "jsonl" }
    }

    private func read(_ url: URL, agent: HarnessKind) {
        let path = url.path
        let row = (try? db.rows("SELECT offset, carry FROM files WHERE path = ?", [.text(path)]))?.first
        var offset = UInt64(row?[0].number ?? 0)
        var carry = row?[1].string.flatMap { try? JSONDecoder().decode(FileCarry.self, from: Data($0.utf8)) } ?? FileCarry()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        // ponytail: a file that shrank was replaced; read it again from the start. Its old totals stay.
        if size < offset {
            offset = 0
            carry = FileCarry()
        }
        guard size > offset else { return }
        try? handle.seek(toOffset: offset)

        var tally = HistoryTally()
        var pending = Data()
        let newline = UInt8(ascii: "\n")
        while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            pending.append(chunk)
            // Only whole lines: a line still being written waits for the next pass.
            guard let last = pending.lastIndex(of: newline) else { continue }
            for line in pending[pending.startIndex..<last].split(separator: newline) {
                let text = String(decoding: line, as: UTF8.self)
                if agent == .claude {
                    tally.claude(text, carry: &carry, calendar: calendar)
                } else {
                    tally.codex(text, carry: &carry, calendar: calendar)
                }
            }
            offset += UInt64(last - pending.startIndex + 1)
            pending = Data(pending[(last + 1)...])
        }
        save(tally, agent: agent, path: path, offset: offset, carry: carry)
    }

    private func save(_ tally: HistoryTally, agent: HarnessKind, path: String, offset: UInt64, carry: FileCarry) {
        do {
            try db.execute("BEGIN")
            for (key, total) in tally.days {
                try db.execute("""
                    INSERT INTO days (day, agent, tokens, tasks, longest) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(day, agent) DO UPDATE SET tokens = tokens + excluded.tokens,
                      tasks = tasks + excluded.tasks, longest = max(longest, excluded.longest)
                    """, [.text(key.day), .text(key.agent.rawValue), .real(Double(total.tokens)),
                          .real(Double(total.tasks)), .real(total.longestTask)])
            }
            for (key, count) in tally.counts {
                try db.execute("""
                    INSERT INTO counts (kind, name, count) VALUES (?, ?, ?)
                    ON CONFLICT(kind, name) DO UPDATE SET count = count + excluded.count
                    """, [.text(key.kind.rawValue), .text(key.name), .real(Double(count))])
            }
            for project in tally.projects.values {
                try db.execute("""
                    INSERT INTO projects (path, tokens, last_active) VALUES (?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET tokens = tokens + excluded.tokens,
                      last_active = max(last_active, excluded.last_active)
                    """, [.text(project.path), .real(Double(project.tokens)), .date(project.lastActive)])
            }
            let json = String(decoding: try JSONEncoder().encode(carry), as: UTF8.self)
            try db.execute("""
                INSERT INTO files (path, agent, offset, carry) VALUES (?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET offset = excluded.offset, carry = excluded.carry
                """, [.text(path), .text(agent.rawValue), .real(Double(offset)), .text(json)])
            try db.execute("COMMIT")
        } catch {
            // The offset was not saved either, so the next pass reads these lines again.
            try? db.execute("ROLLBACK")
        }
    }

    public func summary() -> HistorySummary {
        var summary = HistorySummary()
        for r in (try? db.rows("SELECT day, agent, tokens, tasks, longest FROM days")) ?? [] {
            guard let day = r[0].string, let agent = r[1].string.flatMap(HarnessKind.init(rawValue:)) else { continue }
            let tokens = Int(r[2].number)
            if tokens > 0 { summary.days[day, default: 0] += tokens }
            summary.tokensByAgent[agent, default: 0] += tokens
            summary.tasksByAgent[agent, default: 0] += Int(r[3].number)
            summary.longestTask = max(summary.longestTask, r[4].number)
        }
        func counts(_ kind: CountKey.Kind) -> [NameCount] {
            ((try? db.rows("SELECT name, count FROM counts WHERE kind = ? ORDER BY count DESC", [.text(kind.rawValue)])) ?? [])
                .compactMap { r in r[0].string.map { NameCount(name: $0, count: Int(r[1].number)) } }
        }
        summary.tools = counts(.tool)
        summary.skills = counts(.skill)
        summary.efforts = counts(.effort)
        summary.projects = ((try? db.rows("SELECT path, tokens, last_active FROM projects ORDER BY tokens DESC")) ?? [])
            .compactMap { r in r[0].string.map { ProjectTotal(path: $0, tokens: Int(r[1].number), lastActive: r[2].date) } }
        summary.found = Set(((try? db.rows("SELECT DISTINCT agent FROM files")) ?? [])
            .compactMap { $0[0].string.flatMap(HarnessKind.init(rawValue:)) })
        return summary
    }
}
