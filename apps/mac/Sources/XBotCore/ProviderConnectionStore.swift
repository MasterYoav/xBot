import Foundation
import XBotEngine

/// Which model providers the user has connected — separate from the keys themselves.
///
/// A value with its storage injected rather than an enum reaching for `UserDefaults.standard`.
/// Two reasons, and the second is the one that bit:
///
/// 1. This is the persistence seam for the Models settings pane. Every pane added to Settings
///    persists something, and a store that can only read the one live domain is a store whose
///    behaviour cannot be asserted without changing the developer's own preferences.
/// 2. `UserDefaults.standard` is process-wide, and Swift Testing runs suites in parallel. Two
///    suites that both wrote here raced: one called `reset()` between another's write and its
///    read, so `skippedDuringOnboarding` came back false roughly one run in three. Serialising
///    the suites would have hidden it; giving each caller its own domain removes it.
///
/// The Keychain probe is injected for the same reason. `hasAnyConnection` asks whether any vendor
/// key is stored, which under test reaches the developer's real Keychain — so whether the suite
/// passed depended on whether whoever ran it had ever connected a provider in the real app.
///
/// The injected type is `KeyValueDefaults`, not `UserDefaults`, so a test can hold its state in
/// memory. Handing tests a `UserDefaults(suiteName:)` would leave a plist in `~/Library/
/// Preferences` for every store every run, which trades a flaky test for a litter problem.
public struct ProviderConnectionStore: Sendable {
    /// `UserDefaults` is documented thread-safe but is not marked `Sendable`, so strict
    /// concurrency needs telling. The unchecked part is Apple's guarantee, not an assumption.
    nonisolated(unsafe) private let defaults: any KeyValueDefaults
    private let hasStoredKey: @Sendable (String) -> Bool

    private static let connectedKey = "xbot.connectedProviders"
    private static let skippedKey = "xbot.modelSkippedDuringOnboarding"

    public init(
        defaults: any KeyValueDefaults = UserDefaults.standard,
        hasStoredKey: @escaping @Sendable (String) -> Bool = {
            (try? ProviderKeyStore.key(for: $0)) != nil
        }
    ) {
        self.defaults = defaults
        self.hasStoredKey = hasStoredKey
    }

    /// The app's own connections, on the live preference domain and the real Keychain.
    public static let shared = ProviderConnectionStore()

    public var connectedProviderIDs: Set<String> {
        Set(defaults.stringArray(forKey: Self.connectedKey) ?? [])
    }

    public var skippedDuringOnboarding: Bool {
        defaults.bool(forKey: Self.skippedKey)
    }

    public func markConnected(_ providerID: String) {
        var ids = connectedProviderIDs
        ids.insert(providerID)
        defaults.set(Array(ids), forKey: Self.connectedKey)
        defaults.set(false, forKey: Self.skippedKey)
    }

    public func markSkipped() {
        defaults.set(true, forKey: Self.skippedKey)
    }

    /// Whether the composer may send — at least one provider is connected.
    public func canSendMessages() -> Bool {
        hasAnyConnection
    }

    /// After onboarding skip with no key, the composer stays disabled until a model is connected.
    public func requiresModelForComposer() -> Bool {
        skippedDuringOnboarding && !hasAnyConnection
    }

    public var hasAnyConnection: Bool {
        if !connectedProviderIDs.isEmpty { return true }
        // Ollama is excluded because it needs no key: its presence is detected, not stored, so a
        // missing Keychain entry says nothing about whether it is there.
        return ModelProviderCatalog.all
            .map(\.id)
            .filter { $0 != "ollama" }
            .contains(where: hasStoredKey)
    }

    public func reset() {
        defaults.removeObject(forKey: Self.connectedKey)
        defaults.removeObject(forKey: Self.skippedKey)
    }
}
