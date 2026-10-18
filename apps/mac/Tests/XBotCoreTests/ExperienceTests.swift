import Foundation
import Testing
import XBotBrain
@testable import XBotCore

/// Selection, upkeep and decay of an agent's lessons (Agentic Mode's experience).
@Suite struct ExperienceSelectionTests {
    private func store() -> ExperienceStore {
        ExperienceStore(folder: FileManager.default.temporaryDirectory.appending(path: "xbot-exp-\(UUID().uuidString)"))
    }

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func days(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    @Test func confidenceComesFirstThenRecency() throws {
        let store = store()
        let forge = UUID()
        try store.save([
            Lesson(cue: "old low", lesson: "a", confidence: .low, evidence: "", learnt: days(1)),
            Lesson(cue: "old high", lesson: "b", confidence: .high, evidence: "", learnt: days(9)),
            Lesson(cue: "new medium", lesson: "c", confidence: .medium, evidence: "", learnt: days(0)),
            Lesson(cue: "new high", lesson: "d", confidence: .high, evidence: "", learnt: days(2)),
        ], of: forge)
        #expect(store.selection(for: forge).map(\.cue) == ["new high", "old high", "new medium", "old low"])
    }

    /// Same confidence and the same moment: the cue decides, so the order never wobbles between turns.
    @Test func tiesAreBrokenByCueSoTheOrderIsStable() throws {
        let store = store()
        let forge = UUID()
        try store.save([
            Lesson(cue: "Zed", lesson: "z", confidence: .medium, evidence: "", learnt: now),
            Lesson(cue: "alpha", lesson: "a", confidence: .medium, evidence: "", learnt: now),
            Lesson(cue: "Mid", lesson: "m", confidence: .medium, evidence: "", learnt: now),
        ], of: forge)
        #expect(store.selection(for: forge).map(\.cue) == ["alpha", "Mid", "Zed"])
    }

    @Test func atMostTheLimit() throws {
        let store = store()
        let forge = UUID()
        try store.save((0..<20).map { Lesson(cue: "cue \($0)", lesson: "l", confidence: .high, evidence: "", learnt: days(Double($0))) },
                       of: forge)
        let picked = store.selection(for: forge)
        #expect(picked.count == 12)
        #expect(picked.first?.cue == "cue 0")
        #expect(store.selection(for: forge, limit: 3).map(\.cue) == ["cue 0", "cue 1", "cue 2"])
    }

    /// The budget is counted on the lines as they are sent; one too long is skipped, not a wall.
    @Test func theCharacterBudgetIsRespected() throws {
        let store = store()
        let forge = UUID()
        let long = String(repeating: "x", count: 400)
        try store.save([
            Lesson(cue: "first", lesson: long, confidence: .high, evidence: "", learnt: days(0)),
            Lesson(cue: "huge", lesson: String(repeating: "y", count: 2_000), confidence: .high, evidence: "", learnt: days(1)),
            Lesson(cue: "second", lesson: long, confidence: .high, evidence: "", learnt: days(2)),
            Lesson(cue: "third", lesson: long, confidence: .medium, evidence: "", learnt: days(3)),
            Lesson(cue: "fourth", lesson: long, confidence: .low, evidence: "", learnt: days(4)),
            Lesson(cue: "short", lesson: "s", confidence: .low, evidence: "", learnt: days(5)),
        ], of: forge)
        let picked = store.selection(for: forge, characters: 1_500)
        #expect(picked.map(\.cue) == ["first", "second", "third", "short"])
        #expect(picked.map { $0.instructionLine.count }.reduce(0, +) <= 1_500)
        #expect(store.selection(for: forge, characters: 10).isEmpty)
    }

    @Test func noLessonsSelectsNothing() {
        #expect(store().selection(for: UUID()).isEmpty)
    }

    @Test func aLineReadsAsWhenCueThenLesson() {
        let lesson = Lesson(cue: "When Xcode asks to trust a package", lesson: "Choose Trust and Enable",
                            confidence: .high, evidence: "")
        #expect(lesson.instructionLine == "- When Xcode asks to trust a package: Choose Trust and Enable (high confidence)")
        let bare = Lesson(cue: "tests are slow", lesson: "Use --filter", confidence: .low, evidence: "")
        #expect(bare.instructionLine == "- When tests are slow: Use --filter (low confidence)")
    }

    @Test func markingUsedCountsOnlyThoseGiven() throws {
        let store = store()
        let forge = UUID(), hawk = UUID()
        let a = Lesson(cue: "a", lesson: "a", confidence: .high, evidence: "")
        let b = Lesson(cue: "b", lesson: "b", confidence: .high, evidence: "", uses: 4)
        try store.save([a, b], of: forge)
        try store.save([a], of: hawk)
        try store.markUsed([a.id], of: forge)
        try store.markUsed([a.id, b.id], of: forge)
        #expect(store.lessons(of: forge).map(\.uses) == [2, 5])
        #expect(store.lessons(of: hawk).map(\.uses) == [0], "another agent's copy is untouched")
    }

    @Test func markingNothingUsedWritesNothing() throws {
        let store = store()
        let forge = UUID()
        try store.markUsed([], of: forge)
        try store.markUsed([UUID()], of: forge)
        #expect(!FileManager.default.fileExists(atPath: store.folder.path), "no folder made for nothing")
    }

    @Test func forgettingOneAndAll() throws {
        let store = store()
        let forge = UUID()
        let a = Lesson(cue: "a", lesson: "a", confidence: .high, evidence: "")
        let b = Lesson(cue: "b", lesson: "b", confidence: .low, evidence: "")
        try store.save([a, b], of: forge)
        #expect(try store.forget(a.id, of: forge) == a)
        #expect(store.lessons(of: forge) == [b])
        #expect(try store.forget(UUID(), of: forge) == nil)
        #expect(try store.forgetAll(of: forge) == [b])
        #expect(store.lessons(of: forge).isEmpty)
        #expect(try store.forgetAll(of: forge).isEmpty)
    }

    /// Undo puts them back where they were; a lesson learnt since for the same cue wins.
    @Test func restoringPutsForgottenLessonsBack() throws {
        let store = store()
        let forge = UUID()
        let a = Lesson(cue: "a", lesson: "a", confidence: .high, evidence: "")
        let b = Lesson(cue: "b", lesson: "b", confidence: .low, evidence: "")
        try store.save([a, b], of: forge)
        let gone = try store.forgetAll(of: forge)
        let newer = Lesson(cue: "B", lesson: "newer", confidence: .medium, evidence: "")
        try store.remember(newer, for: forge)
        try store.restore(gone, of: forge)
        #expect(store.lessons(of: forge).map(\.lesson) == ["a", "newer"])
        try store.restore(gone, of: forge)
        #expect(store.lessons(of: forge).count == 2, "restoring twice doesn't double")
    }

    @Test func editingReplacesInPlaceAndKeepsCuesUnique() throws {
        let store = store()
        let forge = UUID()
        let a = Lesson(cue: "a", lesson: "a", confidence: .low, evidence: "e", uses: 3)
        let b = Lesson(cue: "b", lesson: "b", confidence: .low, evidence: "")
        let c = Lesson(cue: "c", lesson: "c", confidence: .low, evidence: "")
        try store.save([a, b, c], of: forge)
        var edited = b
        edited.lesson = "better"
        edited.confidence = .high
        try store.edit(edited, of: forge)
        #expect(store.lessons(of: forge).map(\.lesson) == ["a", "better", "c"])
        #expect(store.lessons(of: forge)[1].confidence == .high)
        // Rewording a cue into another's replaces that one: one lesson per cue.
        var renamed = c
        renamed.cue = "A."
        try store.edit(renamed, of: forge)
        #expect(store.lessons(of: forge).map(\.cue) == ["b", "A."])
        // Editing one that was forgotten meanwhile doesn't bring it back.
        try store.edit(Lesson(cue: "ghost", lesson: "g", confidence: .low, evidence: ""), of: forge)
        #expect(!store.lessons(of: forge).contains { $0.cue == "ghost" })
    }

    @Test func blankCueOrLessonIsNotSaved() throws {
        let store = store()
        let forge = UUID()
        let a = Lesson(cue: "a", lesson: "a", confidence: .low, evidence: "")
        try store.save([a], of: forge)
        var blank = a
        blank.lesson = "   "
        try store.edit(blank, of: forge)
        #expect(store.lessons(of: forge) == [a])
    }
}

@Suite struct ExperienceDecayTests {
    private func store() -> ExperienceStore {
        ExperienceStore(folder: FileManager.default.temporaryDirectory.appending(path: "xbot-exp-\(UUID().uuidString)"))
    }

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func ago(days: Double, seconds: Double = 0) -> Date { now.addingTimeInterval(-days * 86_400 - seconds) }

    /// Only low-confidence, never-used lessons past 30 days go; exactly 30 days stays.
    @Test func dropsOnlyOldUnusedLowConfidenceLessons() throws {
        let store = store()
        let forge = UUID(), hawk = UUID()
        try store.save([
            Lesson(cue: "stale", lesson: "x", confidence: .low, evidence: "", learnt: ago(days: 31)),
            Lesson(cue: "just past", lesson: "x", confidence: .low, evidence: "", learnt: ago(days: 30, seconds: 1)),
            Lesson(cue: "exactly 30", lesson: "x", confidence: .low, evidence: "", learnt: ago(days: 30)),
            Lesson(cue: "used", lesson: "x", confidence: .low, evidence: "", learnt: ago(days: 90), uses: 1),
            Lesson(cue: "medium", lesson: "x", confidence: .medium, evidence: "", learnt: ago(days: 90)),
            Lesson(cue: "young", lesson: "x", confidence: .low, evidence: "", learnt: ago(days: 2)),
        ], of: forge)
        try store.save([Lesson(cue: "stale too", lesson: "x", confidence: .low, evidence: "", learnt: ago(days: 40))], of: hawk)
        try store.decay(now: now)
        #expect(store.lessons(of: forge).map(\.cue) == ["exactly 30", "used", "medium", "young"])
        #expect(store.lessons(of: hawk).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.folder.appending(path: "\(hawk.uuidString).json").path),
                "an emptied agent's file is removed")
    }

    @Test func decayWithoutAFolderIsFine() throws {
        try store().decay(now: now)
    }

    /// Something else in the folder is left alone.
    @Test func decayIgnoresOtherFiles() throws {
        let store = store()
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        let other = store.folder.appending(path: "notes.txt")
        try Data("hi".utf8).write(to: other)
        try Data("not json".utf8).write(to: store.folder.appending(path: "\(UUID().uuidString).json"))
        try store.decay(now: now)
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    /// A file that hasn't changed isn't rewritten (cheap at launch, and no churn for sync tools).
    @Test func decayLeavesUnchangedFilesAlone() throws {
        let store = store()
        let forge = UUID()
        try store.save([Lesson(cue: "keep", lesson: "x", confidence: .high, evidence: "", learnt: ago(days: 100))], of: forge)
        let file = store.folder.appending(path: "\(forge.uuidString).json")
        let before = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: file.path)
        try store.decay(now: now)
        let after = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        #expect(before != nil)
        #expect(after == Date(timeIntervalSince1970: 0))
    }
}

/// What the agent is told it has learnt, and asked to write down.
@MainActor @Suite struct ExperienceInjectionTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")
    let folder = FileManager.default.temporaryDirectory.appending(path: "xbot-exp-\(UUID().uuidString)")

    func workspace(_ brain: ScriptedBrain = ScriptedBrain([.done])) async -> Workspace {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: brain] })
        w.experience = ExperienceStore(folder: folder)
        await w.refreshHarnesses()
        return w
    }

    static let heading = "What you've learnt (from earlier tasks; apply when the cue fits):"
    static let reflection = "When you finish a task, if you learnt something general that would help next time (not task-specific facts), call the xbot_remember tool once with the cue, the lesson, your confidence and the evidence."

    @Test func lessonsAppearUnderTheirHeadingAndAreCountedAsUsed() async throws {
        let w = await workspace()
        let forge = try #require(w.agents.first { $0.name == "Forge" })
        let lesson = Lesson(cue: "When Xcode asks to trust a package", lesson: "Choose Trust and Enable",
                            confidence: .high, evidence: "The build failed until it was trusted")
        try w.experience.remember(lesson, for: forge.id)
        let chat = try #require(w.talk(to: forge.id))
        let text = try #require(w.instructions(for: chat))
        #expect(text.contains(Self.heading + "\n- When Xcode asks to trust a package: Choose Trust and Enable (high confidence)"))
        #expect(!text.contains("The build failed"), "evidence is for the person, not the prompt")
        #expect(w.experience.lessons(of: forge.id).first?.uses == 1)
        _ = w.instructions(for: chat)
        #expect(w.experience.lessons(of: forge.id).first?.uses == 2)
    }

    @Test func onlyTheSelectionIsSentAndCounted() async throws {
        let w = await workspace()
        let forge = try #require(w.agents.first { $0.name == "Forge" })
        let lessons = (0..<30).map {
            Lesson(cue: "cue \($0)", lesson: String(repeating: "z", count: 80), confidence: .medium, evidence: "",
                   learnt: Date.now.addingTimeInterval(Double(-$0)))
        }
        try w.experience.save(lessons, of: forge.id)
        let chat = try #require(w.talk(to: forge.id))
        let text = try #require(w.instructions(for: chat))
        let lines = text.split(separator: "\n").filter { $0.hasPrefix("- When cue ") }
        #expect(lines.count == 12)
        #expect(lines.map(\.count).reduce(0, +) <= 1_500)
        let used = w.experience.lessons(of: forge.id).filter { $0.uses == 1 }.map(\.cue)
        #expect(used == (0..<12).map { "cue \($0)" })
    }

    @Test func noLessonsNoSection() async throws {
        let w = await workspace()
        let forge = try #require(w.agents.first { $0.name == "Forge" })
        let chat = try #require(w.talk(to: forge.id))
        let text = try #require(w.instructions(for: chat))
        #expect(!text.contains("What you've learnt"))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    /// Another agent's lessons stay theirs.
    @Test func lessonsArePerAgent() async throws {
        let w = await workspace()
        let forge = try #require(w.agents.first { $0.name == "Forge" })
        let hawk = try #require(w.agents.first { $0.name == "Hawk" })
        try w.experience.remember(Lesson(cue: "x", lesson: "Forge's", confidence: .high, evidence: ""), for: forge.id)
        let chat = try #require(w.talk(to: hawk.id))
        #expect(try #require(w.instructions(for: chat)).contains("Forge's") == false)
    }

    @Test func theReflectionLineOnlyComesWithTools() async throws {
        let w = await workspace()
        let forge = try #require(w.agents.first { $0.name == "Forge" })
        let chat = try #require(w.talk(to: forge.id))
        #expect(try #require(w.instructions(for: chat)).contains(Self.reflection) == false)
        #expect(try #require(w.instructions(for: chat, toolsAttached: true)).hasSuffix(Self.reflection))
    }

    /// A plain chat has no agent to have learnt anything.
    @Test func aPlainChatStillHasNoInstructions() async throws {
        let w = await workspace()
        let chat = try #require(w.newChat(in: nil))
        #expect(w.instructions(for: chat, toolsAttached: true) == nil)
    }

    @Test func theTurnCarriesTheLessons() async throws {
        let brain = ScriptedBrain([.textDelta("ok"), .done])
        let w = await workspace(brain)
        let forge = try #require(w.agents.first { $0.name == "Forge" })
        try w.experience.remember(Lesson(cue: "tests are slow", lesson: "Use --filter", confidence: .medium, evidence: ""),
                                  for: forge.id)
        let chat = try #require(w.talk(to: forge.id))
        #expect(w.send("Go", in: chat.id))
        for _ in 0..<400 where !w.turns.isEmpty { await Task.yield() }
        let sent = try #require(brain.requests.withLock { $0.last?.instructions })
        #expect(sent.contains("- When tests are slow: Use --filter (medium confidence)"))
    }
}

/// What the Mac's agent editor does with them.
@MainActor @Suite struct ExperienceWorkspaceTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")

    @Test func aLibraryOnDiskKeepsExperienceBesideIt() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "lib-\(UUID().uuidString)")
        let store = try Store(database: Database(url: dir.appending(path: "xbot.sqlite")))
        let w = Workspace(store: store, inbox: inbox, discover: { [:] })
        #expect(w.experience.folder.standardizedFileURL.path == dir.appending(path: "Experience").standardizedFileURL.path)
    }

    /// Tests and a library that couldn't open never touch the person's real experience.
    @Test func anInMemoryLibraryKeepsExperienceAwayFromThePersons() {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [:] })
        #expect(w.experience.folder != ExperienceStore.live.folder)
    }

    /// Stale lessons go when the library opens.
    @Test func decayRunsWhenTheWorkspaceLoads() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "lib-\(UUID().uuidString)")
        let experience = ExperienceStore(folder: dir.appending(path: "Experience"))
        let forge = UUID()
        try experience.save([
            Lesson(cue: "stale", lesson: "x", confidence: .low, evidence: "", learnt: .now.addingTimeInterval(-40 * 86_400)),
            Lesson(cue: "fresh", lesson: "x", confidence: .low, evidence: "", learnt: .now),
        ], of: forge)
        let store = try Store(database: Database(url: dir.appending(path: "xbot.sqlite")))
        _ = Workspace(store: store, inbox: inbox, discover: { [:] })
        #expect(experience.lessons(of: forge).map(\.cue) == ["fresh"])
    }

    @Test func forgetAndUndo() async throws {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [:] })
        let forge = UUID()
        let a = Lesson(cue: "a", lesson: "a", confidence: .high, evidence: "")
        let b = Lesson(cue: "b", lesson: "b", confidence: .low, evidence: "")
        try w.experience.save([a, b], of: forge)
        #expect(w.lessons(of: forge) == [a, b])
        let undo = try #require(w.forgetLesson(a.id, of: forge))
        #expect(w.lessons(of: forge) == [b])
        undo()
        #expect(w.lessons(of: forge) == [a, b])
        let undoAll = try #require(w.forgetAllLessons(of: forge))
        #expect(w.lessons(of: forge).isEmpty)
        undoAll()
        #expect(w.lessons(of: forge) == [a, b])
        #expect(w.forgetLesson(UUID(), of: forge) == nil)
    }

    @Test func editingThroughTheWorkspace() {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [:] })
        let forge = UUID()
        var a = Lesson(cue: "a", lesson: "a", confidence: .low, evidence: "")
        _ = try? w.experience.save([a], of: forge)
        a.lesson = "  sharper  "
        a.cue = " a cue "
        w.editLesson(a, of: forge)
        #expect(w.lessons(of: forge).map(\.lesson) == ["sharper"])
        #expect(w.lessons(of: forge).map(\.cue) == ["a cue"])
    }

    /// The count on the crew card follows lessons written by someone else (the xbot_remember tool).
    @Test func countsFollowWritesFromElsewhere() throws {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [:] })
        let forge = UUID()
        #expect(w.lessons(of: forge).isEmpty)
        try w.experience.remember(Lesson(cue: "a", lesson: "a", confidence: .low, evidence: ""), for: forge)
        #expect(w.lessons(of: forge).count == 1)
    }
}
