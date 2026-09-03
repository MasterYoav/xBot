import Foundation

/// The bearer token that guards loopback. Generated once, held in the Keychain, never logged.
public enum EngineTokenStore: Sendable {
    private static let service = "dev.xbot.engine-token"

    /// Returns the persisted token, creating one on first access.
    public static func token() throws -> String {
        try KeychainSecretStore.string(service: service)
    }

    /// Forget it. Only uninstall calls this — a new one is generated on next use.
    public static func remove() throws {
        try KeychainSecretStore.remove(service: service, account: "default")
    }
}
