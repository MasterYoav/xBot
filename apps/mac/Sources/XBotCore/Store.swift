import Foundation

/// Everything xBot remembers about projects and chats, in one SQLite file.
/// ponytail: on the main actor; the writes are a row at a time. Move to an actor if a profile says so.
@MainActor
public final class Store {
    private let db: Database
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: Database) throws {
        db = database
        try db.execute("""
            CREATE TABLE IF NOT EXISTS projects (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL UNIQUE, created_at REAL NOT NULL)
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS chats (
              id TEXT PRIMARY KEY, project_id TEXT REFERENCES projects(id) ON DELETE CASCADE,
              title TEXT NOT NULL, harness TEXT NOT NULL, model TEXT, mode TEXT NOT NULL,
              session_id TEXT, created_at REAL NOT NULL, updated_at REAL NOT NULL)
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS messages (
              id TEXT PRIMARY KEY, chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
              role TEXT NOT NULL, parts TEXT NOT NULL, created_at REAL NOT NULL)
            """)
        try db.execute("CREATE INDEX IF NOT EXISTS messages_by_chat ON messages(chat_id)")
        try migrate()
    }

    /// Schema changes since the first release of the redesigned app, each applied once, in order,
    /// counted in SQLite's `user_version`.
    private func migrate() throws {
        let version = Int(try db.rows("PRAGMA user_version").first.map { row -> Double in
            if case .real(let n) = row[0] { n } else { 0 }
        } ?? 0)
        if version < 1 {
            // Plan mode (2026-10-08). The chat's two switches.
            let columns = try db.rows("PRAGMA table_info(chats)").compactMap { $0[1].string }
            if !columns.contains("plan_mode") {
                try db.execute("ALTER TABLE chats ADD COLUMN plan_mode INTEGER NOT NULL DEFAULT 0")
            }
            if !columns.contains("review_plan") {
                try db.execute("ALTER TABLE chats ADD COLUMN review_plan INTEGER NOT NULL DEFAULT 1")
            }
            try db.execute("PRAGMA user_version = 1")
        }
    }

    /// `~/Library/Application Support/xBot/xbot.sqlite`.
    public static func live() throws -> Store {
        try Store(database: Database(url: supportDirectory.appending(path: "xbot.sqlite")))
    }

    public static func inMemory() -> Store {
        // An in-memory database cannot fail to open or to take this schema.
        try! Store(database: Database())
    }

    public nonisolated static var supportDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "xBot", directoryHint: .isDirectory)
    }

    // MARK: Projects

    public func projects() throws -> [Project] {
        try db.rows("SELECT id, name, path, created_at FROM projects ORDER BY name COLLATE NOCASE").compactMap { r in
            guard let id = r[0].uuid, let name = r[1].string, let path = r[2].string else { return nil }
            return Project(id: id, name: name, path: path, createdAt: r[3].date)
        }
    }

    public func save(_ project: Project) throws {
        try db.execute("""
            INSERT INTO projects (id, name, path, created_at) VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name = excluded.name, path = excluded.path
            """, [.text(project.id.uuidString), .text(project.name), .text(project.path), .date(project.createdAt)])
    }

    public func deleteProject(_ id: UUID) throws {
        try db.execute("DELETE FROM projects WHERE id = ?", [.text(id.uuidString)])
    }

    // MARK: Chats

    public func chats() throws -> [Chat] {
        try db.rows("""
            SELECT id, project_id, title, harness, model, mode, session_id, created_at, updated_at,
              plan_mode, review_plan
            FROM chats ORDER BY updated_at DESC
            """).compactMap { r in
            // A row from a newer xBot with a harness this one does not know is skipped, not fatal.
            guard let id = r[0].uuid, let title = r[2].string,
                  let harness = r[3].string.flatMap(HarnessKind.init(rawValue:)),
                  let mode = r[5].string.flatMap(PermissionMode.init(rawValue:)) else { return nil }
            return Chat(
                id: id, projectID: r[1].uuid, title: title, harness: harness, model: r[4].string,
                mode: mode, sessionID: r[6].string, planMode: r[9].bool, reviewPlan: r[10].bool,
                createdAt: r[7].date, updatedAt: r[8].date
            )
        }
    }

    /// An upsert that updates in place. INSERT OR REPLACE would delete the row first, and the
    /// cascade would take the chat's messages with it.
    public func save(_ chat: Chat) throws {
        try db.execute("""
            INSERT INTO chats (id, project_id, title, harness, model, mode, session_id, created_at, updated_at,
              plan_mode, review_plan)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET project_id = excluded.project_id, title = excluded.title,
              harness = excluded.harness, model = excluded.model, mode = excluded.mode,
              session_id = excluded.session_id, updated_at = excluded.updated_at,
              plan_mode = excluded.plan_mode, review_plan = excluded.review_plan
            """, [
                .text(chat.id.uuidString), (chat.projectID?.uuidString).sql, .text(chat.title),
                .text(chat.harness.rawValue), chat.model.sql, .text(chat.mode.rawValue),
                chat.sessionID.sql, .date(chat.createdAt), .date(chat.updatedAt),
                .bool(chat.planMode), .bool(chat.reviewPlan),
            ])
    }

    public func deleteChat(_ id: UUID) throws {
        try db.execute("DELETE FROM chats WHERE id = ?", [.text(id.uuidString)])
    }

    // MARK: Messages

    public func messages(in chatID: UUID) throws -> [ChatMessage] {
        try db.rows(
            "SELECT id, role, parts, created_at FROM messages WHERE chat_id = ? ORDER BY rowid",
            [.text(chatID.uuidString)]
        ).compactMap { r in
            guard let id = r[0].uuid, let role = r[1].string.flatMap(Role.init(rawValue:)),
                  let json = r[2].string,
                  let parts = try? decoder.decode([Part].self, from: Data(json.utf8)) else { return nil }
            return ChatMessage(id: id, chatID: chatID, role: role, parts: parts, createdAt: r[3].date)
        }
    }

    public func append(_ message: ChatMessage) throws {
        let parts = String(decoding: try encoder.encode(message.parts), as: UTF8.self)
        try db.execute(
            "INSERT INTO messages (id, chat_id, role, parts, created_at) VALUES (?, ?, ?, ?, ?)",
            [.text(message.id.uuidString), .text(message.chatID.uuidString), .text(message.role.rawValue),
             .text(parts), .date(message.createdAt)]
        )
    }

    /// A message whose parts changed — a plan, as it runs. Same row, same place in the chat.
    public func replace(_ message: ChatMessage) throws {
        let parts = String(decoding: try encoder.encode(message.parts), as: UTF8.self)
        try db.execute("UPDATE messages SET parts = ? WHERE id = ?", [.text(parts), .text(message.id.uuidString)])
    }
}
