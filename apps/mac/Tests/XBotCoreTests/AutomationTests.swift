import Foundation
import Testing
import XBotBrain
@testable import XBotCore

@Suite struct AutomationScheduleTests {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Jerusalem")!; return c }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func dailyIsTodayIfStillAheadElseTomorrow() {
        let s = AutomationSchedule.daily(hour: 9, minute: 0)
        #expect(s.next(after: date(2026, 10, 12, 8, 0), calendar: calendar) == date(2026, 10, 12, 9, 0))
        #expect(s.next(after: date(2026, 10, 12, 9, 0), calendar: calendar) == date(2026, 10, 13, 9, 0))
    }

    /// Friday evening: the next weekday run is Monday morning.
    @Test func weekdaysSkipTheWeekend() {
        let s = AutomationSchedule.weekdays(hour: 8, minute: 30)
        #expect(s.next(after: date(2026, 10, 16, 18, 0), calendar: calendar) == date(2026, 10, 19, 8, 30))
    }

    @Test func weeklyAndHourly() {
        // 2026-10-12 is a Monday; weekday 4 is Wednesday.
        #expect(AutomationSchedule.weekly(weekday: 4, hour: 17, minute: 0).next(after: date(2026, 10, 12, 10, 0), calendar: calendar)
                == date(2026, 10, 14, 17, 0))
        #expect(AutomationSchedule.hourly(minute: 15).next(after: date(2026, 10, 12, 10, 20), calendar: calendar)
                == date(2026, 10, 12, 11, 15))
    }

    @Test func dueWhenTheNextRunAfterTheLastHasPassed() {
        var a = Automation(name: "x", trigger: .schedule(.hourly(minute: 0)), steps: [])
        a.createdAt = date(2026, 10, 12, 9, 30)
        #expect(!a.isDue(at: date(2026, 10, 12, 9, 59), calendar: calendar))
        #expect(a.isDue(at: date(2026, 10, 12, 10, 0), calendar: calendar))
        a.lastRunAt = date(2026, 10, 12, 10, 0)
        #expect(!a.isDue(at: date(2026, 10, 12, 10, 30), calendar: calendar))
        a.isEnabled = false
        #expect(!a.isDue(at: date(2026, 10, 12, 12, 0), calendar: calendar))
        #expect(!Automation(name: "m", trigger: .manual, steps: []).isDue(at: .now, calendar: calendar))
    }
}

@Suite struct AutomationPromptTests {
    @Test func stepsInOrderWithTheirAppsAndOnlyTheHowTosNeeded() {
        let a = Automation(name: "Morning brief", trigger: .manual, steps: [
            AutomationStep(app: .calendar, text: "Find today's meetings"),
            AutomationStep(app: .connector("Gmail"), text: "Find unread mail from my boss"),
            AutomationStep(app: .notes, text: "Write a note called Brief with both"),
        ])
        let prompt = AutomationPrompt.make(a)
        let cal = prompt.range(of: "Find today's meetings")!, gmail = prompt.range(of: "unread mail")!
        let notes = prompt.range(of: "note called Brief")!
        #expect(cal.lowerBound < gmail.lowerBound && gmail.lowerBound < notes.lowerBound)
        #expect(prompt.contains("1. [Calendar]") && prompt.contains("2. [Gmail connector]") && prompt.contains("3. [Notes]"))
        #expect(prompt.contains("osascript"))
        #expect(prompt.contains("Gmail") && prompt.contains("MCP"))
        #expect(!prompt.contains("shortcuts run"))
        #expect(prompt.contains("Morning brief"))
    }

    @Test func emptyStepsAreLeftOut() {
        let a = Automation(name: "x", trigger: .manual, steps: [
            AutomationStep(app: .anything, text: "  "), AutomationStep(app: .shortcuts, text: "Run Focus"),
        ])
        let prompt = AutomationPrompt.make(a)
        #expect(prompt.contains("1. [Shortcuts] Run Focus") && !prompt.contains("2."))
        #expect(prompt.contains("shortcuts run"))
    }
}

@MainActor @Suite struct AutomationWorkspaceTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")

    func settle(_ w: Workspace) async { for _ in 0..<400 where !w.turns.isEmpty { await Task.yield() } }

    @Test func automationsAreSavedAndComeBack() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "auto-\(UUID().uuidString).sqlite")
        let w = Workspace(store: try Store(database: Database(url: url)), inbox: inbox, discover: { [:] })
        var a = w.newAutomation()
        a.name = "Tidy downloads"
        a.trigger = .schedule(.weekdays(hour: 8, minute: 0))
        a.steps = [AutomationStep(app: .finder, text: "Move old files to the Trash")]
        w.saveAutomation(a)
        let again = Workspace(store: try Store(database: Database(url: url)), inbox: inbox, discover: { [:] })
        #expect(again.automations == [a])
    }

    @Test func runningMakesATaggedFullAccessChatWithTheCompiledPrompt() async throws {
        let brain = ScriptedBrain([.textDelta("Done."), .done])
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: brain] })
        await w.refreshHarnesses()
        var a = w.newAutomation()
        a.steps = [AutomationStep(app: .reminders, text: "Add 'buy milk'")]
        w.saveAutomation(a)
        let chat = try #require(w.runAutomation(a.id))
        await settle(w)
        #expect(chat.automationID == a.id && chat.mode == .fullAccess)
        let request = try #require(brain.requests.withLock { $0.last })
        #expect(request.prompt == AutomationPrompt.make(a) && request.mode == .fullAccess)
        #expect(w.runs(of: a.id).map(\.id) == [chat.id])
        #expect(w.automation(a.id)?.lastRunAt != nil)
        #expect(!w.openChatIDs.contains(chat.id))
    }

    @Test func aRunningAutomationIsntStartedTwice() async throws {
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: ScriptedBrain([.textDelta("…")], hold: true)] })
        await w.refreshHarnesses()
        var a = w.newAutomation()
        a.steps = [AutomationStep(app: .anything, text: "wait")]
        w.saveAutomation(a)
        #expect(w.runAutomation(a.id) != nil)
        #expect(w.runAutomation(a.id) == nil)
        #expect(w.isRunning(automation: a.id))
    }

    /// Another process (the background helper) claimed it first: this one leaves it alone.
    @Test func claimingIsCompareAndSet() throws {
        let store = Store.inMemory()
        let a = Automation(name: "x", trigger: .manual, steps: [])
        try store.save(a)
        let now = Date.now
        #expect(try store.claim(a.id, expected: nil, at: now))
        #expect(!(try store.claim(a.id, expected: nil, at: now.addingTimeInterval(1))))
        #expect(try store.claim(a.id, expected: now, at: now.addingTimeInterval(2)))
    }

    @Test func dueAutomationsRunOnTheTick() async throws {
        let brain = ScriptedBrain([.done])
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: brain] })
        await w.refreshHarnesses()
        var due = w.newAutomation()
        due.trigger = .schedule(.hourly(minute: 0))
        due.createdAt = Date.now.addingTimeInterval(-7200)
        due.steps = [AutomationStep(app: .anything, text: "x")]
        w.saveAutomation(due)
        var manual = w.newAutomation()
        manual.steps = [AutomationStep(app: .anything, text: "y")]
        w.saveAutomation(manual)
        let started = w.runDueAutomations(at: .now)
        #expect(started == [due.id])
        await settle(w)
    }

    @Test func runsStayOutOfTheSidebarAndRecentHoldsProjectlessChats() async throws {
        let brain = ScriptedBrain([.done])
        let w = Workspace(store: .inMemory(), inbox: inbox, discover: { [.claude: brain] })
        await w.refreshHarnesses()
        let plain = try #require(w.newChat(in: nil))
        var a = w.newAutomation()
        a.steps = [AutomationStep(app: .anything, text: "x")]
        w.saveAutomation(a)
        let run = try #require(w.runAutomation(a.id))
        await settle(w)
        let model = SidebarModel(projects: w.projects, chats: w.chats, running: [])
        #expect(model.recent.map(\.id).contains(plain.id))
        #expect(!model.recent.contains { $0.id == run.id })
    }
}

@Suite struct BackgroundHelperTests {
    @Test func theLaunchAgentRunsXBotHeadlessEveryMinute() throws {
        let binary = URL(filePath: "/Applications/XBot.app/Contents/MacOS/XBot")
        let data = AutomationHelper.plist(binary: binary)
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == AutomationHelper.label)
        #expect(plist["ProgramArguments"] as? [String] == [binary.path, AutomationHelper.tickArgument])
        #expect(plist["StartInterval"] as? Int == 60)
        #expect(plist["RunAtLoad"] as? Bool == false)
    }
}
