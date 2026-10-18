import Foundation

/// One thing an agent learnt for next time: Harness2's "cue → lesson", kept per agent.
public struct Lesson: Codable, Equatable, Sendable, Identifiable {
    public enum Confidence: String, Codable, Sendable, CaseIterable { case low, medium, high }

    public var id: UUID
    /// When it applies: "When Xcode asks to trust a package".
    public var cue: String
    /// What to do: "Choose Trust and Enable".
    public var lesson: String
    public var confidence: Confidence
    /// Why it's believed: one line of what happened.
    public var evidence: String
    public var learnt: Date
    /// How many turns it was given to.
    public var uses: Int

    public init(id: UUID = UUID(), cue: String, lesson: String, confidence: Confidence, evidence: String,
                learnt: Date = .now, uses: Int = 0) {
        self.id = id; self.cue = cue; self.lesson = lesson; self.confidence = confidence
        self.evidence = evidence; self.learnt = learnt; self.uses = uses
    }
}

/// Each agent's experience, one JSON file per agent in `Experience/` beside the library, so it's
/// readable, easy to remove, and outside the database schema.
public struct ExperienceStore: Sendable {
    public let folder: URL

    public init(folder: URL) { self.folder = folder }

    /// `~/Library/Application Support/xBot/Experience`.
    public static var live: ExperienceStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ExperienceStore(folder: base.appending(path: "xBot/Experience", directoryHint: .isDirectory))
    }

    private func file(_ agentID: UUID) -> URL { folder.appending(path: "\(agentID.uuidString).json") }

    public func lessons(of agentID: UUID) -> [Lesson] {
        guard let data = try? Data(contentsOf: file(agentID)) else { return [] }
        return (try? Self.decoder.decode([Lesson].self, from: data)) ?? []
    }

    public func save(_ lessons: [Lesson], of agentID: UUID) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if lessons.isEmpty {
            try? FileManager.default.removeItem(at: file(agentID))
        } else {
            try Self.encoder.encode(lessons).write(to: file(agentID), options: .atomic)
        }
    }

    /// Adds a lesson; one with the same cue (ignoring case and spacing) is replaced, not doubled.
    @discardableResult
    public func remember(_ lesson: Lesson, for agentID: UUID) throws -> [Lesson] {
        var all = lessons(of: agentID).filter { Self.key($0.cue) != Self.key(lesson.cue) }
        all.append(lesson)
        try save(all, of: agentID)
        return all
    }

    static func key(_ cue: String) -> String {
        cue.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).joined(separator: " ")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
