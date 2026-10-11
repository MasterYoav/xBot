import Foundation
import Testing
import XBotBrain
@testable import XBotCore

/// The rest of the automations suite: editing, every app, schedule edges, storage, and the
/// workspace's guards. The live end-to-end run is `scripts/e2e-automations.sh`.
@Suite struct AutomationEditingTests {
    func make(_ apps: [AutomationApp]) -> Automation {
        Automation(name: "x", trigger: .manual, steps: apps.map { AutomationStep(app: $0, text: $0.title) })
    }

    @Test func droppingAnAppAddsAStepWhereItLands() {
        var a = make([.mail, .notes])
        do { let ok = a.drop(Automation.dragItem(for: .calendar), at: 1); #expect(ok) }
        #expect(a.steps.map(\.app) == [.mail, .calendar, .notes])
        #expect(a.steps[1].text.isEmpty)
        do { let ok = a.drop(Automation.dragItem(for: .connector("Gmail")), at: 99); #expect(ok) }
        #expect(a.steps.last?.app == .connector("Gmail"))
        do { let ok = a.drop(Automation.dragItem(for: .finder), at: -5); #expect(ok) }
        #expect(a.steps.first?.app == .finder)
    }

    @Test func droppingAStepMovesIt() {
        var a = make([.mail, .calendar, .notes, .reminders])
        let notes = a.steps[2]
        // Up: onto the first card.
        do { let ok = a.drop(Automation.dragItem(for: notes), at: 0); #expect(ok) }
        #expect(a.steps.map(\.app) == [.notes, .mail, .calendar, .reminders])
        // Down: to the end (the drop zone).
        do { let ok = a.drop(Automation.dragItem(for: notes), at: a.steps.count); #expect(ok) }
        #expect(a.steps.map(\.app) == [.mail, .calendar, .reminders, .notes])
        // Down onto a card: lands before that card.
        let mail = a.steps[0]
        do { let ok = a.drop(Automation.dragItem(for: mail), at: 2); #expect(ok) }
        #expect(a.steps.map(\.app) == [.calendar, .mail, .reminders, .notes])
        // Onto itself: no change.
        do { let ok = a.drop(Automation.dragItem(for: mail), at: 1); #expect(ok) }
        #expect(a.steps.map(\.app) == [.calendar, .mail, .reminders, .notes])
        #expect(a.steps.count == 4)
    }

    @Test func otherDropsAreRefused() {
        var a = make([.mail])
        do { let ok = a.drop("hello", at: 0); #expect(!ok) }
        do { let ok = a.drop("app:nonsense", at: 0); #expect(!ok) }
        do { let ok = a.drop("step:\(UUID().uuidString)", at: 0); #expect(!ok) }
        #expect(a.steps.count == 1)
    }

    @Test func hasWorkNeedsAStepThatSaysSomething() {
        #expect(!Automation(name: "x", trigger: .manual, steps: []).hasWork)
        #expect(!Automation(name: "x", trigger: .manual, steps: [AutomationStep(app: .mail, text: " \n ")]).hasWork)
        #expect(make([.mail]).hasWork)
    }
}

@Suite struct AutomationAppTests {
    @Test func everyAppSurvivesStorage() {
        for app in AutomationApp.builtIn + [.connector("Gmail"), .connector("claude.ai Google Drive")] {
            #expect(AutomationApp(storageKey: app.storageKey) == app)
        }
        #expect(AutomationApp(storageKey: "spreadsheet") == nil)
    }

    /// Their icons come from the apps themselves; on this Mac every built-in one is there.
    @Test func builtInAppsPointAtRealApps() {
        for app in AutomationApp.builtIn {
            guard let path = app.bundlePath else {
                #expect([AutomationApp.web, .anything].contains(app))
                continue
            }
            #expect(FileManager.default.fileExists(atPath: path), "\(app.title): \(path)")
        }
    }

    /// Each scriptable app's how-to names it inside osascript, which is what the agent runs.
    @Test func everyAppSaysHowToReachIt() {
        for app in AutomationApp.builtIn where app != .anything {
            #expect(app.howTo?.isEmpty == false, "\(app.title)")
        }
        for app: AutomationApp in [.mail, .calendar, .reminders, .notes, .messages, .contacts, .music, .photos, .safari, .finder] {
            #expect(app.howTo?.contains("tell application \"\(app.title)\"") == true, "\(app.title)")
        }
        #expect(AutomationApp.anything.howTo == nil)
    }

    @Test func howTosAreSaidOnceEach() {
        let a = Automation(name: "x", trigger: .manual, steps: [
            AutomationStep(app: .notes, text: "a"), AutomationStep(app: .notes, text: "b"),
        ])
        let prompt = AutomationPrompt.make(a)
        #expect(prompt.components(separatedBy: "Notes: script it").count == 2)
        #expect(prompt.contains("1. [Notes] a") && prompt.contains("2. [Notes] b"))
    }
}

@MainActor @Suite struct AutomationScheduleEdgeTests {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Jerusalem")!; return c }
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func hourlyRollsOverMidnightAndMonths() {
        #expect(AutomationSchedule.hourly(minute: 0).next(after: date(2026, 10, 31, 23, 30), calendar: calendar)
                == date(2026, 11, 1, 0, 0))
    }

    @Test func weekdaysFromSaturdayAndFromAWeekdayMorning() {
        let s = AutomationSchedule.weekdays(hour: 9, minute: 0)
        #expect(s.next(after: date(2026, 10, 17, 12, 0), calendar: calendar) == date(2026, 10, 19, 9, 0))
        #expect(s.next(after: date(2026, 10, 13, 7, 0), calendar: calendar) == date(2026, 10, 13, 9, 0))
    }

    @Test func weeklyOnTheSameDayLaterIsNextWeek() {
        // Monday 10:00, for Mondays at 09:00 → the Monday after.
        #expect(AutomationSchedule.weekly(weekday: 2, hour: 9, minute: 0).next(after: date(2026, 10, 12, 10, 0), calendar: calendar)
                == date(2026, 10, 19, 9, 0))
    }

    /// Israel leaves summer time on 2026-10-25: a daily 09:00 is still 09:00 on the clock.
    @Test func dailyKeepsItsClockTimeOverASummerTimeChange() {
        let next = AutomationSchedule.daily(hour: 9, minute: 0).next(after: date(2026, 10, 24, 10, 0), calendar: calendar)
        #expect(calendar.dateComponents([.day, .hour, .minute], from: next) == DateComponents(day: 25, hour: 9, minute: 0))
    }

    /// A Mac asleep for days runs a missed schedule once when it wakes, not once per missed time.
    @Test func aMissedScheduleRunsOnceThenWaitsForTheNext() {
        var a = Automation(name: "x", trigger: .schedule(.hourly(minute: 0)), steps: [])
        a.createdAt = date(2026, 10, 10, 9, 30)
        let wake = date(2026, 10, 12, 15, 20)
        #expect(a.isDue(at: wake, calendar: calendar))
        a.lastRunAt = wake
        #expect(!a.isDue(at: date(2026, 10, 12, 15, 59), calendar: calendar))
        #expect(a.isDue(at: date(2026, 10, 12, 16, 0), calendar: calendar))
    }

    @Test func schedulesSurviveStorage() throws {
        let store = Store.inMemory()
        let schedules: [AutomationSchedule] = [.hourly(minute: 15), .daily(hour: 7, minute: 5), .weekdays(hour: 8, minute: 0),
                                               .weekly(weekday: 6, hour: 17, minute: 45)]
        for (i, s) in schedules.enumerated() {
            try store.save(Automation(name: "\(i)", trigger: .schedule(s), steps: [], sortIndex: i))
        }
        try store.save(Automation(name: "m", trigger: .manual, steps: [], sortIndex: 9))
        let back = try store.automations()
        #expect(back.map(\.trigger) == schedules.map(Automation.Trigger.schedule) + [.manual])
    }
}

@MainActor @Suite struct AutomationStoreTests {
    @Test func everythingRoundTrips() throws {
        let store = Store.inMemory()
        let project = Project(name: "p", path: "/tmp/p")
        try store.save(project)
        let a = Automation(
            name: "All", trigger: .schedule(.weekly(weekday: 3, hour: 1, minute: 2)),
            steps: [AutomationStep(app: .connector("GitHub"), text: "list PRs"), AutomationStep(app: .safari, text: "open them")],
            harness: .codex, model: "gpt-5", effort: .high, projectID: project.id, isEnabled: false, sortIndex: 4
        )
        try store.save(a)
        #expect(try store.automations() == [a])
        var edited = a
        edited.name = "Renamed"
        edited.steps.removeFirst()
        try store.save(edited)
        #expect(try store.automations() == [edited])
    }

    /// Saving from the editor never rolls back a run the store has claimed.
    @Test func savingKeepsTheClaimedLastRun() throws {
        let store = Store.inMemory()
        let a = Automation(name: "x", trigger: .manual, steps: [])
        try store.save(a)
        let now = Date.now
        #expect(try store.claim(a.id, expected: nil, at: now))
        try store.save(a)   // the editor's copy, lastRunAt nil
        #expect(try store.automations().first?.lastRunAt == now)
    }

    /// One step the store can't read (a bad id, an app from a newer xBot) loses only itself, not
    /// every step — and so a later save can't wipe them.
    @Test func anUnreadableStepLosesOnlyItself() throws {
        let db = try Database()
        let store = try Store(database: db)
        let a = Automation(name: "x", trigger: .manual, steps: [AutomationStep(app: .notes, text: "keep")])
        try store.save(a)
        try db.execute("""
            UPDATE automations SET steps = '[{"id":"not-a-uuid","app":"terminal","text":"odd id"},
              {"id":"\(UUID().uuidString)","app":"hologram","text":"future app"},
              {"id":"\(a.steps[0].id.uuidString)","app":"notes","text":"keep"}]'
            """)
        let steps = try #require(try store.automations().first).steps
        #expect(steps.map(\.text) == ["odd id", "keep"])
        #expect(steps.last?.id == a.steps[0].id)
    }

    @Test func aLibraryFromBeforeAutomationsMigrates() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/x.sqlite")
        let id = UUID()
        do {
            let old = try Store(database: Database(url: url))
            try old.save(Chat(id: id, projectID: nil, title: "Old", harness: .claude, mode: .editFiles))
        }
        do {
            // Back to how v4 left it: no automations table, no chats.automation_id.
            let db = try Database(url: url)
            try db.execute("DROP TABLE automations")
            try db.execute("ALTER TABLE chats DROP COLUMN automation_id")
            try db.execute("PRAGMA user_version = 4")
        }
        let store = try Store(database: Database(url: url))
        #expect(try store.chats().map(\.id) == [id])
        #expect(try store.chats().first?.automationID == nil)
        #expect(try store.automations().isEmpty)
        _ = try Store(database: Database(url: url))
    }
}

@MainActor @Suite struct AutomationGuardTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")
    func settle(_ w: Workspace) async { for _ in 0..<400 where !w.turns.isEmpty { await Task.yield() } }

    func workspace(_ brains: [HarnessKind: any Brain]) async -> Workspace {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { brains })
        await w.refreshHarnesses()
        return w
    }

    @Test func nothingToDoOrNoAgentMeansNoRun() async throws {
        let w = await workspace([.claude: ScriptedBrain([.done])])
        var empty = w.newAutomation()
        empty.steps = [AutomationStep(app: .mail, text: "  ")]
        w.saveAutomation(empty)
        #expect(w.runAutomation(empty.id) == nil)
        var onCodex = w.newAutomation()
        onCodex.harness = .codex
        onCodex.steps = [AutomationStep(app: .anything, text: "x")]
        w.saveAutomation(onCodex)
        #expect(w.runAutomation(onCodex.id) == nil)
        #expect(w.chats.isEmpty)
    }

    @Test func runsUseTheAutomationsAgentModelEffortAndProject() async throws {
        let codex = ScriptedBrain([.done])
        let w = await workspace([.claude: ScriptedBrain([.done]), .codex: codex])
        let project = w.addProject(at: FileManager.default.temporaryDirectory)
        var a = w.newAutomation()
        a.harness = .codex
        a.model = "gpt-5-mini"
        a.effort = .low
        a.projectID = project.id
        a.steps = [AutomationStep(app: .terminal, text: "ls")]
        w.saveAutomation(a)
        let chat = try #require(w.runAutomation(a.id))
        await settle(w)
        let request = try #require(codex.requests.withLock { $0.last })
        #expect(request.model == "gpt-5-mini" && request.effort == .low && request.mode == .fullAccess)
        #expect(request.directory.standardizedFileURL.path == URL(filePath: project.path).standardizedFileURL.path)
        #expect(chat.title.hasPrefix(a.name + " · "))
    }

    @Test func aDisabledScheduleDoesntRunOnTheTickButRunNowStillWorks() async throws {
        let w = await workspace([.claude: ScriptedBrain([.done])])
        var a = w.newAutomation()
        a.trigger = .schedule(.hourly(minute: 0))
        a.createdAt = .now.addingTimeInterval(-7200)
        a.isEnabled = false
        a.steps = [AutomationStep(app: .anything, text: "x")]
        w.saveAutomation(a)
        #expect(w.runDueAutomations().isEmpty)
        #expect(w.runAutomation(a.id) != nil)
        await settle(w)
    }

    @Test func aFailedRunIsMarkedFailed() async throws {
        let w = await workspace([.claude: ScriptedBrain([.failed("Failed to authenticate")])])
        var a = w.newAutomation()
        a.steps = [AutomationStep(app: .anything, text: "x")]
        w.saveAutomation(a)
        let failed = try #require(w.runAutomation(a.id))
        await settle(w)
        #expect(w.runFailed(failed.id))
        let ok = await workspace([.claude: ScriptedBrain([.textDelta("fine"), .done])])
        var b = ok.newAutomation()
        b.steps = [AutomationStep(app: .anything, text: "x")]
        ok.saveAutomation(b)
        let fine = try #require(ok.runAutomation(b.id))
        await settle(ok)
        #expect(!ok.runFailed(fine.id))
    }

    @Test func deletingAnAutomationKeepsItsRunsAsChats() async throws {
        let w = await workspace([.claude: ScriptedBrain([.done])])
        var a = w.newAutomation()
        a.steps = [AutomationStep(app: .anything, text: "x")]
        w.saveAutomation(a)
        let run = try #require(w.runAutomation(a.id))
        await settle(w)
        w.deleteAutomation(a.id)
        #expect(w.automations.isEmpty)
        #expect(w.chat(run.id)?.automationID == nil)
        // Now a plain chat, so it shows in Recent.
        #expect(SidebarModel(projects: [], chats: w.chats, running: []).recent.contains { $0.id == run.id })
    }

    /// The background helper ran it meanwhile: the app's next look sees that and doesn't repeat it.
    @Test func aRunByTheHelperIsntRepeatedByTheApp() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "auto-\(UUID().uuidString).sqlite")
        let app = Workspace(store: try Store(database: Database(url: url)), inbox: inbox, discover: { [.claude: ScriptedBrain([.done])] })
        await app.refreshHarnesses()
        var a = app.newAutomation()
        a.trigger = .schedule(.hourly(minute: 0))
        a.createdAt = .now.addingTimeInterval(-7200)
        a.steps = [AutomationStep(app: .anything, text: "x")]
        app.saveAutomation(a)
        let helper = Workspace(store: try Store(database: Database(url: url)), inbox: inbox, discover: { [.claude: ScriptedBrain([.done])] })
        await helper.refreshHarnesses()
        #expect(helper.runDueAutomations() == [a.id])
        await settle(helper)
        #expect(app.runDueAutomations().isEmpty)
    }

    @Test func runsAreNewestFirst() async throws {
        let w = await workspace([.claude: ScriptedBrain([.done])])
        var a = w.newAutomation()
        a.steps = [AutomationStep(app: .anything, text: "x")]
        w.saveAutomation(a)
        let first = try #require(w.runAutomation(a.id, at: .now))
        await settle(w)
        let second = try #require(w.runAutomation(a.id, at: .now.addingTimeInterval(1)))
        await settle(w)
        #expect(w.runs(of: a.id).map(\.id) == [second.id, first.id])
    }
}
