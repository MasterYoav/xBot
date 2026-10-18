import Foundation

/// Each agent's experience as the Mac shows it: read, reworded and forgotten from the agent editor.
/// The lessons themselves are written by the agent (the `xbot_remember` tool) into `experience`.
extension Workspace {
    /// Their lessons, as the person sees them: by confidence, then the newest. Read again only when
    /// the file has changed, since the crew card asks every second.
    public func lessons(of agentID: UUID) -> [Lesson] {
        _ = experienceRevision
        let file = experience.folder.appending(path: "\(agentID.uuidString).json")
        let date = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        if let cached = lessonCache[agentID], cached.date == date { return cached.lessons }
        let lessons = experience.lessons(of: agentID).sorted(by: ExperienceStore.ranks)
        lessonCache[agentID] = (date, lessons)
        return lessons
    }

    /// Forgets one; returns how to bring it back, or nil if there was nothing to forget.
    @discardableResult
    public func forgetLesson(_ id: UUID, of agentID: UUID) -> (@MainActor () -> Void)? {
        guard let gone = attempt({ try experience.forget(id, of: agentID) }) ?? nil else { return nil }
        changedExperience(of: agentID)
        return { [weak self] in self?.restoreLessons([gone], of: agentID) }
    }

    /// Forgets everything they've learnt; returns how to bring it back, or nil if there was nothing.
    @discardableResult
    public func forgetAllLessons(of agentID: UUID) -> (@MainActor () -> Void)? {
        guard let gone = attempt({ try experience.forgetAll(of: agentID) }), !gone.isEmpty else { return nil }
        changedExperience(of: agentID)
        return { [weak self] in self?.restoreLessons(gone, of: agentID) }
    }

    /// The person's rewording of a cue, a lesson or how sure it is.
    public func editLesson(_ lesson: Lesson, of agentID: UUID) {
        attempt { try experience.edit(lesson, of: agentID) }
        changedExperience(of: agentID)
    }

    func restoreLessons(_ lessons: [Lesson], of agentID: UUID) {
        attempt { try experience.restore(lessons, of: agentID) }
        changedExperience(of: agentID)
    }

    func changedExperience(of agentID: UUID) {
        lessonCache[agentID] = nil
        experienceRevision += 1
    }

    // MARK: In a turn

    /// "What you've learnt", for the agent's instructions, counting each lesson as used. Nil when
    /// they haven't learnt anything yet.
    func experienceSection(for agentID: UUID) -> String? {
        let picked = experience.selection(for: agentID)
        guard !picked.isEmpty else { return nil }
        // Bookkeeping: a count that couldn't be written isn't worth a banner.
        try? experience.markUsed(picked.map(\.id), of: agentID)
        lessonCache[agentID] = nil
        return "What you've learnt (from earlier tasks; apply when the cue fits):\n"
            + picked.map(\.instructionLine).joined(separator: "\n")
    }

    /// The end of every turn with xBot's tools: Harness2's reflection, done by the agent itself in
    /// the same turn rather than by a second model run.
    static let reflection = "When you finish a task, if you learnt something general that would help next time (not task-specific facts), call the xbot_remember tool once with the cue, the lesson, your confidence and the evidence."
}
