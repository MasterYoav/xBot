import Foundation

/// Semver-ish comparison for `minimumAppVersion` checks on engine manifests.
public enum AppVersion: Sendable {
    /// True when `app` is greater than or equal to `minimum` (numeric dot segments).
    public static func satisfies(app: String, minimum: String) -> Bool {
        compare(app, minimum) >= 0
    }

    public static func compare(_ app: String, _ minimum: String) -> Int {
        let appParts = app.split(separator: ".").compactMap { Int($0) }
        let minimumParts = minimum.split(separator: ".").compactMap { Int($0) }
        let count = max(appParts.count, minimumParts.count)
        for index in 0..<count {
            let appValue = index < appParts.count ? appParts[index] : 0
            let minimumValue = index < minimumParts.count ? minimumParts[index] : 0
            if appValue != minimumValue {
                return appValue < minimumValue ? -1 : 1
            }
        }
        return 0
    }
}
