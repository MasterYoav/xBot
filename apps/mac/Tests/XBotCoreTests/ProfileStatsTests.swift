import Foundation
import Testing
@testable import XBotCore

@Suite struct ProfileStatsTests {
    let utc = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }()

    func date(_ s: String) -> Date { try! Date(s + "T12:00:00Z", strategy: .iso8601) }

    @Test func lifetimePeakAndStreaks() {
        let days = ["2026-10-01": 5, "2026-10-02": 50, "2026-10-03": 1, "2026-10-06": 2, "2026-10-07": 3, "2026-10-08": 4]
        let stats = ProfileStats(days: days, today: date("2026-10-08"), calendar: utc)
        #expect(stats.lifetime == 65 && stats.peak == 50)
        #expect(stats.longestStreak == 3 && stats.currentStreak == 3)
    }

    @Test func aStreakSurvivesUntilTheDayIsOver() {
        let stats = ProfileStats(days: ["2026-10-06": 1, "2026-10-07": 1], today: date("2026-10-08"), calendar: utc)
        #expect(stats.currentStreak == 2)
        let broken = ProfileStats(days: ["2026-10-05": 1], today: date("2026-10-08"), calendar: utc)
        #expect(broken.currentStreak == 0)
    }

    @Test func heatmapIs53WeeksEndingThisWeek() {
        let grid = ProfileStats.heatmap(["2026-10-08": 10], mode: .daily, today: date("2026-10-08"), calendar: utc)
        #expect(grid.count == 53 && grid.allSatisfy { $0.count == 7 })
        // 2026-10-08 is a Thursday: index 4 with Sunday first.
        #expect(grid[52][4].value == 10 && grid[52][4].level == 4)
        #expect(grid[52][5].isFuture && grid[52][6].isFuture)
        #expect(grid[0][0].level == 0)
    }

    @Test func weeklyAndCumulative() {
        let days = ["2026-10-04": 1, "2026-10-05": 2, "2026-10-08": 3]
        let weekly = ProfileStats.heatmap(days, mode: .weekly, today: date("2026-10-08"), calendar: utc)
        #expect(weekly[52][0].value == 6 && weekly[52][4].value == 6)
        let cumulative = ProfileStats.heatmap(days, mode: .cumulative, today: date("2026-10-08"), calendar: utc)
        #expect(cumulative[52][1].value == 3 && cumulative[52][4].value == 6)
    }

    @Test func levelsAreQuartiles() {
        let days = ["2026-10-04": 1, "2026-10-05": 2, "2026-10-06": 3, "2026-10-07": 4, "2026-10-08": 100]
        let week = ProfileStats.heatmap(days, mode: .daily, today: date("2026-10-08"), calendar: utc)[52]
        #expect(week.prefix(5).map(\.level) == [1, 2, 3, 4, 4])
    }

    @Test func topEffortMergesTheCLIsNamesAndSkipsUnknownOnes() {
        let efforts = [NameCount(name: "high", count: 5), NameCount(name: "xhigh", count: 4),
                       NameCount(name: "medium", count: 1), NameCount(name: "bogus", count: 90)]
        let top = ProfileStats.topEffort(efforts)
        #expect(top?.effort == .high && top?.percent == 50)
    }

    @Test func historyIsReadIntoTheWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "hist-\(UUID().uuidString)")
        let claude = root.appending(path: "claude/proj")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let line = #"{"type":"assistant","timestamp":"2026-10-08T10:00:05.000Z","message":{"id":"m","usage":{"input_tokens":7}}}"#
        try (line + "\n").write(to: claude.appending(path: "s.jsonl"), atomically: true, encoding: .utf8)
        let indexer = try HistoryIndexer(database: Database(), claude: root.appending(path: "claude"),
                                         codex: root.appending(path: "codex"), calendar: utc)
        let w = await Workspace(store: .inMemory(), inbox: FileManager.default.temporaryDirectory, discover: { [:] },
                                defaults: UserDefaults(suiteName: UUID().uuidString)!, indexer: indexer)
        await w.indexHistory()
        #expect(await w.history?.days["2026-10-08"] == 7)
    }
}
