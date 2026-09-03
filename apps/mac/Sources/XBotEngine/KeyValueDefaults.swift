import Foundation

/// The four defaults operations this app's stores actually use.
///
/// `UserDefaults` already has all four with these signatures, so its conformance is empty and the
/// app is unchanged. The point is the other implementation: a test needs somewhere to put a value
/// that is neither the developer's real preferences nor a throwaway `suiteName`, because a suite
/// name is a plist on disk and a test that makes one makes it on every run.
public protocol KeyValueDefaults: AnyObject {
    func stringArray(forKey defaultName: String) -> [String]?
    func bool(forKey defaultName: String) -> Bool
    func integer(forKey defaultName: String) -> Int
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: KeyValueDefaults {}
