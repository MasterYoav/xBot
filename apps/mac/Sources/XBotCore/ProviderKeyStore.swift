import Foundation

/// Vendor API keys. Keychain only — never UserDefaults, never logs.
public enum ProviderKeyStore: Sendable {
    private static let service = "dev.xbot.provider-key"

    public static func normalize(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("bearer ") {
            trimmed = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    public static func save(_ key: String, for providerID: String) throws {
        let normalized = normalize(key)
        guard !normalized.isEmpty else { return }
        try KeychainSecretStore.write(normalized, service: service, account: providerID)
    }

    public static func key(for providerID: String) throws -> String? {
        try KeychainSecretStore.readExisting(service: service, account: providerID)
    }

    public static func remove(providerID: String) throws {
        try KeychainSecretStore.remove(service: service, account: providerID)
    }
}
