import Foundation
import Testing
@testable import XBotCore

@MainActor @Suite struct UsageTests {
    let utc = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    let us = Locale(identifier: "en_US")

    @Test func remainingIsWhatIsLeft() {
        #expect(UsageText.remaining(RateWindow(usedPercent: 3.4, resetsAt: .now)) == "97%")
        #expect(UsageText.remaining(RateWindow(usedPercent: 104, resetsAt: .now)) == "0%")
    }

    @Test func resetTodayIsATimeLaterIsADate() {
        let now = Date(timeIntervalSince1970: 1791460000)  // 2026-10-08 11:46 UTC
        // Foundation puts a narrow no-break space before AM/PM.
        let time = UsageText.resets(now.addingTimeInterval(3600), now: now, calendar: utc, locale: us)
        #expect(time.replacingOccurrences(of: "\u{202F}", with: " ") == "12:46 PM")
        #expect(UsageText.resets(now.addingTimeInterval(7 * 86400), now: now, calendar: utc, locale: us) == "Oct 15")
    }

    @Test func aResetWithinADayIsATimeEvenAfterMidnight() {
        let lateEvening = Date(timeIntervalSince1970: 1791496800)  // 2026-10-08 22:00 UTC
        let time = UsageText.resets(lateEvening.addingTimeInterval(3 * 3600), now: lateEvening, calendar: utc, locale: us)
        #expect(time.replacingOccurrences(of: "\u{202F}", with: " ") == "1:00 AM")
    }

    @Test func updatedAgo() {
        let now = Date.now
        #expect(UsageText.updated(now.addingTimeInterval(-20), now: now) == "Updated just now")
        #expect(UsageText.updated(now.addingTimeInterval(-125), now: now) == "Updated 2 min ago")
    }

    @Test func aTurnsLimitsAreRecordedAndKept() async throws {
        let limits = RateLimits(fiveHour: RateWindow(usedPercent: 10, resetsAt: Date(timeIntervalSince1970: 1)), weekly: nil)
        let brain = ScriptedBrain([.session("s"), .limits(limits), .textDelta("hi"), .done])
        let store = Store.inMemory()
        let w = Workspace(store: store, inbox: FileManager.default.temporaryDirectory, discover: { [.claude: brain] })
        await w.refreshHarnesses()
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("hello", in: chat.id)
        for _ in 0..<200 where w.isRunning(chat.id) { await Task.yield() }
        #expect(w.usage[.claude]?.limits.fiveHour?.usedPercent == 10)
        #expect(w.messages(in: chat.id).last?.parts == [.text("hi")])
        #expect(try store.usage()[.claude]?.limits == limits)
    }

    @Test func codexUsageIsReadOnRequest() async {
        let limits = RateLimits(fiveHour: nil, weekly: RateWindow(usedPercent: 20, resetsAt: Date(timeIntervalSince1970: 1)), plan: "ChatGPT Plus")
        let w = Workspace(store: .inMemory(), inbox: FileManager.default.temporaryDirectory, discover: { [:] },
                          codexUsage: { limits })
        await w.refreshCodexUsage()
        #expect(w.usage[.codex]?.limits == limits)
    }
}
