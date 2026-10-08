import Foundation

public struct HeatCell: Equatable, Sendable {
    public var date: Date
    public var value: Int
    /// 0 for nothing, 1–4 by quartile of what the grid shows.
    public var level: Int
    public var isFuture: Bool
}

/// The profile's numbers, from tokens per day ("yyyy-MM-dd" → tokens).
public struct ProfileStats: Equatable, Sendable {
    public enum Mode: String, CaseIterable, Sendable { case daily, weekly, cumulative }

    public var lifetime: Int
    public var peak: Int
    public var longestStreak: Int
    public var currentStreak: Int

    public init(days: [String: Int], today: Date, calendar: Calendar) {
        lifetime = days.values.reduce(0, +)
        peak = days.values.max() ?? 0
        let active = Set(days.filter { $0.value > 0 }.keys)
        var longest = 0, run = 0
        var previous: Date?
        for key in active.sorted() {
            guard let date = Self.date(key, calendar) else { continue }
            let follows = previous.map { calendar.dateComponents([.day], from: $0, to: date).day == 1 } ?? false
            run = follows ? run + 1 : 1
            longest = max(longest, run)
            previous = date
        }
        longestStreak = longest
        // Today is not over: a streak that reached yesterday still counts.
        var day = calendar.startOfDay(for: today)
        if !active.contains(HistoryTally.day(day, calendar)) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var current = 0
        while active.contains(HistoryTally.day(day, calendar)) {
            current += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        currentStreak = current
    }

    /// The reasoning level used most, and its share. The CLIs' own names ("xhigh") are xBot's
    /// levels; anything neither knows is left out.
    public static func topEffort(_ efforts: [NameCount]) -> (effort: Effort, percent: Int)? {
        var merged: [Effort: Int] = [:]
        for entry in efforts {
            if let effort = Effort(cliValue: entry.name) { merged[effort, default: 0] += entry.count }
        }
        let total = merged.values.reduce(0, +)
        guard let top = merged.max(by: { $0.value < $1.value }), total > 0 else { return nil }
        return (top.key, Int((Double(top.value) / Double(total) * 100).rounded()))
    }

    static func date(_ key: String, _ calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// 53 weeks, oldest first, each the seven days of the calendar's week; the last holds today.
    /// Weekly shows each day its week's total; cumulative, everything up to that day.
    public static func heatmap(_ days: [String: Int], mode: Mode, today: Date, calendar: Calendar) -> [[HeatCell]] {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)!.start
        let start = calendar.date(byAdding: .weekOfYear, value: -52, to: thisWeek)!
        let end = calendar.startOfDay(for: today)
        var running = days.filter { key, _ in date(key, calendar).map { $0 < start } ?? false }.values.reduce(0, +)
        var grid: [[HeatCell]] = []
        for week in 0..<53 {
            let weekStart = calendar.date(byAdding: .weekOfYear, value: week, to: start)!
            let dates = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: weekStart)! }
            let values = dates.map { $0 > end ? 0 : days[HistoryTally.day($0, calendar)] ?? 0 }
            let weekTotal = values.reduce(0, +)
            grid.append(zip(dates, values).map { date, value in
                let future = date > end
                running += value
                let shown: Int = switch mode {
                case .daily: value
                case .weekly: weekTotal
                case .cumulative: running
                }
                return HeatCell(date: date, value: future ? 0 : shown, level: 0, isFuture: future)
            })
        }
        let nonZero = grid.joined().map(\.value).filter { $0 > 0 }.sorted()
        guard !nonZero.isEmpty else { return grid }
        func quantile(_ q: Double) -> Int { nonZero[Int(Double(nonZero.count - 1) * q)] }
        let cuts = [quantile(0.25), quantile(0.5), quantile(0.75)]
        return grid.map { week in
            week.map { cell in
                var cell = cell
                cell.level = cell.value == 0 ? 0 : min(4, 1 + cuts.filter { cell.value >= $0 }.count)
                return cell
            }
        }
    }
}
