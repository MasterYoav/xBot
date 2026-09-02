import Foundation

/// Encrypts the engine's credential vault. Generated once per install, held in the Keychain.
public enum KeyEncryptionKeyStore: Sendable {
    private static let service = "dev.xbot.key-encryption-key"

    public static func key() throws -> String {
        try KeychainSecretStore.string(service: service)
    }
}
