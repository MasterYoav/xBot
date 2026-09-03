import Foundation

/// Which onboarding flow the user has completed.
///
/// Stored as an integer so a future step can bump `current` and re-run only what changed.
///
/// In `XBotCore` rather than beside the onboarding views, because it is app state that outlives
/// them: uninstall has to clear it, and `XBotCore` cannot import `XBotOnboarding` — the dependency
/// runs the other way.
public enum OnboardingVersion: Sendable {
    public static let current = 1
    private static let key = "xbot.onboardingVersion"

    public static var isComplete: Bool {
        UserDefaults.standard.integer(forKey: key) >= current
    }

    public static func markComplete() {
        UserDefaults.standard.set(current, forKey: key)
    }

    /// For tests, the re-onboarding sheet, and uninstall.
    public static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
