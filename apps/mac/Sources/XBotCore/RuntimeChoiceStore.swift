import Foundation

/// Which container runtime path onboarding chose — for diagnostics and re-onboarding.
public enum RuntimeChoiceStore: Sendable {
    public enum Choice: String, Sendable {
        case detected
        case colimaInstalled
        case dockerManual
    }

    private static let key = "xbot.chosenRuntime"

    public static var choice: Choice? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return Choice(rawValue: raw)
    }

    public static func markDetected() {
        UserDefaults.standard.set(Choice.detected.rawValue, forKey: key)
    }

    public static func markColimaInstalled() {
        UserDefaults.standard.set(Choice.colimaInstalled.rawValue, forKey: key)
    }

    public static func markDockerManual() {
        UserDefaults.standard.set(Choice.dockerManual.rawValue, forKey: key)
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
