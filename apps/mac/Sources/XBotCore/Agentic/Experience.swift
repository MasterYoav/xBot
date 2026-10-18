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
        self.evidence = evidence; self.uses = uses
        // Whole seconds, as the file keeps it (ISO 8601), so a lesson equals itself read back.
        self.learnt = Date(timeIntervalSinceReferenceDate: learnt.timeIntervalSinceReferenceDate.rounded(.down))
    }

    /// How it reads in a turn's instructions: "- When <cue>: <lesson> (high confidence)". A cue
    /// that already starts with "When" isn't given a second one. Evidence stays out: it's for the
    /// person, and the budget is better spent on more lessons.
    public var instructionLine: String {
        var cue = cue.trimmingCharacters(in: .whitespacesAndNewlines)
        if cue.range(of: "when ", options: [.caseInsensitive, .anchored]) != nil { cue = String(cue.dropFirst(5)) }
        return "- When \(cue): \(lesson.trimmingCharacters(in: .whitespacesAndNewlines)) (\(confidence.rawValue) confidence)"
    }
}

extension Lesson.Confidence {
    /// High first.
    var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
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

    // MARK: What goes into a turn

    /// The lessons for a turn's instructions: by confidence, then the newest, then the cue (so the
    /// order never wobbles between turns), at most `limit`, their lines within `characters`. A lesson
    /// too long for what's left is skipped rather than ending the list, so one wall of text can't
    /// crowd out the short ones behind it.
    public func selection(for agentID: UUID, limit: Int = 12, characters: Int = 1500) -> [Lesson] {
        var budget = characters
        var picked: [Lesson] = []
        for lesson in lessons(of: agentID).sorted(by: Self.ranks) where picked.count < limit {
            let cost = lesson.instructionLine.count
            guard cost <= budget else { continue }
            budget -= cost
            picked.append(lesson)
        }
        return picked
    }

    /// The order the person sees them in, and the order a turn gets them in.
    public static func ranks(_ a: Lesson, _ b: Lesson) -> Bool {
        if a.confidence != b.confidence { return a.confidence.rank > b.confidence.rank }
        if a.learnt != b.learnt { return a.learnt > b.learnt }
        let order = a.cue.localizedCaseInsensitiveCompare(b.cue)
        return order == .orderedSame ? a.id.uuidString < b.id.uuidString : order == .orderedAscending
    }

    /// They were given to a turn: count it. Writes nothing when none of them are this agent's.
    public func markUsed(_ ids: [UUID], of agentID: UUID) throws {
        let wanted = Set(ids)
        guard !wanted.isEmpty else { return }
        var all = lessons(of: agentID)
        var changed = false
        for index in all.indices where wanted.contains(all[index].id) {
            all[index].uses += 1
            changed = true
        }
        if changed { try save(all, of: agentID) }
    }

    // MARK: Upkeep

    /// A low-confidence lesson nobody has used in its first 30 days goes; that's when it was a
    /// guess that never came up again. Every agent's file is looked at; only changed ones written.
    public func decay(now: Date = .now) throws {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            guard let agentID = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
            let all = lessons(of: agentID)
            let kept = all.filter { !Self.isStale($0, now: now) }
            if kept.count != all.count { try save(kept, of: agentID) }
        }
    }

    static let staleAfter: TimeInterval = 30 * 86_400

    static func isStale(_ lesson: Lesson, now: Date) -> Bool {
        lesson.confidence == .low && lesson.uses == 0 && now.timeIntervalSince(lesson.learnt) > staleAfter
    }

    /// Removes one; returns it, for Undo.
    @discardableResult
    public func forget(_ id: UUID, of agentID: UUID) throws -> Lesson? {
        var all = lessons(of: agentID)
        guard let index = all.firstIndex(where: { $0.id == id }) else { return nil }
        let gone = all.remove(at: index)
        try save(all, of: agentID)
        return gone
    }

    /// Removes all of them; returns them, for Undo.
    @discardableResult
    public func forgetAll(of agentID: UUID) throws -> [Lesson] {
        let all = lessons(of: agentID)
        if !all.isEmpty { try save([], of: agentID) }
        return all
    }

    /// Undo: puts forgotten lessons back, in the order they were learnt. One learnt since for the
    /// same cue wins, as `remember` would have had it.
    public func restore(_ forgotten: [Lesson], of agentID: UUID) throws {
        let all = lessons(of: agentID)
        let ids = Set(all.map(\.id)), cues = Set(all.map { Self.key($0.cue) })
        let back = forgotten.filter { !ids.contains($0.id) && !cues.contains(Self.key($0.cue)) }
        guard !back.isEmpty else { return }
        // Stable, with what comes back first among equal dates: it was there before.
        let merged = (back + all).enumerated().sorted { ($0.element.learnt, $0.offset) < ($1.element.learnt, $1.offset) }
        try save(merged.map(\.element), of: agentID)
    }

    /// The person's rewording, in place. A blank cue or lesson is not a lesson, and one forgotten
    /// meanwhile stays forgotten; a cue reworded into another's replaces that one.
    public func edit(_ lesson: Lesson, of agentID: UUID) throws {
        var lesson = lesson
        lesson.cue = lesson.cue.trimmingCharacters(in: .whitespacesAndNewlines)
        lesson.lesson = lesson.lesson.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lesson.cue.isEmpty, !lesson.lesson.isEmpty else { return }
        var all = lessons(of: agentID)
        guard let index = all.firstIndex(where: { $0.id == lesson.id }) else { return }
        all[index] = lesson
        all.removeAll { $0.id != lesson.id && Self.key($0.cue) == Self.key(lesson.cue) }
        try save(all, of: agentID)
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
