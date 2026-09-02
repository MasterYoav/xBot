import Foundation

/// The bearer token that guards loopback. Generated once, held in the Keychain, never logged.
public enum EngineTokenStore: Sendable {
    private static let service = "dev.xbot.engine-token"

    /// Returns the persisted token, creating one on first access.
    public static func token() throws -> String {
        try KeychainSecretStore.string(service: service)
    }
}
