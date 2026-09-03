import Foundation

/// Which onboarding flow the user has completed.
///
/// Stored as an integer so a future step can bump `current` and re-run only what changed.
public enum OnboardingVersion {
    public static let current = 1
    private static let key = "xbot.onboardingVersion"

    public static var isComplete: Bool {
        UserDefaults.standard.integer(forKey: key) >= current
    }

    public static func markComplete() {
        UserDefaults.standard.set(current, forKey: key)
    }

    /// For tests and the re-onboarding sheet later.
    public static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
