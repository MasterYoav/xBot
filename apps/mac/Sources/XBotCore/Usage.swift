import Foundation

/// An agent's limits and when xBot last heard them.
public struct AgentUsage: Equatable, Sendable {
    public var agent: HarnessKind
    public var limits: RateLimits
    public var updatedAt: Date

    public init(agent: HarnessKind, limits: RateLimits, updatedAt: Date) {
        self.agent = agent
        self.limits = limits
        self.updatedAt = updatedAt
    }
}

/// The words and numbers of the usage menu.
public enum UsageText {
    /// What is left of the window: "97%".
    public static func remaining(_ window: RateWindow) -> String {
        "\(min(max(Int((100 - window.usedPercent).rounded()), 0), 100))%"
    }

    /// "12:42 AM" when it resets within a day, else "Oct 15".
    public static func resets(
        _ date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(date.timeIntervalSince(now) < 86_400 ? "jmm" : "MMMd")
        return formatter.string(from: date)
    }

    public static func updated(_ date: Date, now: Date = .now) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return String(localized: "Updated just now") }
        if minutes < 60 { return String(localized: "Updated \(minutes) min ago") }
        return String(localized: "Updated \(minutes / 60) h ago")
    }
}
