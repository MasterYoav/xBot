import Foundation
import XBotEngine

/// The loopback port the engine last bound, so relaunch does not walk the range again.
///
/// Injected storage rather than a hard `UserDefaults.standard`, for the reason
/// `ProviderConnectionStore` documents: three tests wrote this one key, Swift Testing ran their
/// suites in parallel, and a port saved by one arrived in the middle of another's read — the
/// expectation failed with 49152 where 49180 had just been written.
public struct EnginePortStore: Sendable {
    public static let key = "dev.xbot.enginePort"

    /// `UserDefaults` is documented thread-safe but is not marked `Sendable`.
    nonisolated(unsafe) private let defaults: any KeyValueDefaults

    public init(defaults: any KeyValueDefaults = UserDefaults.standard) {
        self.defaults = defaults
    }

    public static let shared = EnginePortStore()

    public func load() -> UInt16? {
        let value = defaults.integer(forKey: Self.key)
        guard value > 0, value <= Int(UInt16.max) else { return nil }
        return UInt16(value)
    }

    public func save(_ port: UInt16) {
        defaults.set(Int(port), forKey: Self.key)
    }
}
