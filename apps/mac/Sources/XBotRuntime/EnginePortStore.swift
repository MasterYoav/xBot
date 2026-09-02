import Foundation

/// The loopback port the engine last bound, so relaunch does not walk the range again.
enum EnginePortStore {
    static let key = "dev.xbot.enginePort"

    static func load() -> UInt16? {
        let value = UserDefaults.standard.integer(forKey: key)
        guard value > 0, value <= Int(UInt16.max) else { return nil }
        return UInt16(value)
    }

    static func save(_ port: UInt16) {
        UserDefaults.standard.set(Int(port), forKey: key)
    }
}
