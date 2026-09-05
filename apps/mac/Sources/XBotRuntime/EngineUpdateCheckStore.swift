import Foundation

/// When the app last looked for a published engine digest. See docs/11-packaging-and-updates.md.
public enum EngineUpdateCheckStore: Sendable {
    public static let checkInterval: TimeInterval = 86_400

    private static let lastCheckKey = "xbot.engine.lastUpdateCheck"

    public static func shouldCheck(
        now: Date = .now,
        interval: TimeInterval = checkInterval,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let last = defaults.object(forKey: lastCheckKey) as? Date else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    public static func markChecked(now: Date = .now, defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: lastCheckKey)
    }

    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lastCheckKey)
    }
}
