import Foundation

/// App update checks through Sparkle. See docs/11-packaging-and-updates.md.
@MainActor
public protocol AppUpdateControlling: AnyObject {
    /// Whether an appcast URL and public key are configured for this build.
    var isConfigured: Bool { get }

    /// Called once so the controller can defer checks while a turn is streaming.
    func bindUpdateBlockingActivity(_ isBlocked: @escaping () -> Bool)

    /// User-initiated check from Settings → Updates.
    func checkForUpdates(userInitiated: Bool)

    /// Daily automatic check — skipped while `isBlocked` returns true.
    func scheduleAutomaticCheckIfDue()
}

/// When Sparkle is not configured (no appcast in the bundled Info.plist).
@MainActor
public final class DisabledAppUpdateController: AppUpdateControlling {
    public static let shared = DisabledAppUpdateController()

    public var isConfigured: Bool { false }

    public func bindUpdateBlockingActivity(_ isBlocked: @escaping () -> Bool) {}

    public func checkForUpdates(userInitiated: Bool) {}

    public func scheduleAutomaticCheckIfDue() {}
}

/// When the app last looked for a newer xBot build.
public enum AppUpdateCheckStore: Sendable {
    public static let checkInterval: TimeInterval = 86_400

    private static let lastCheckKey = "xbot.app.lastUpdateCheck"

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
