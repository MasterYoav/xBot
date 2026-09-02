import Foundation
import Security

/// The bearer token that guards loopback. Generated once, held in the Keychain, never logged.
public enum EngineTokenStore: Sendable {
    private static let service = "dev.xbot.engine-token"
    private static let account = "default"

    /// Returns the persisted token, creating one on first access.
    public static func token() throws -> String {
        if let existing = try read() { return existing }
        let fresh = try generate()
        try save(fresh)
        return fresh
    }

    private static func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainError.randomFailed(status)
        }
        return Data(bytes).base64EncodedString()
    }

    private static func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
            let string = String(data: data, encoding: .utf8)
        else {
            throw KeychainError.readFailed(status)
        }
        return string
    }

    private static func save(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let addStatus = SecItemAdd(
            query.merging(attributes) { _, new in new } as CFDictionary,
            nil
        )
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError.writeFailed(updateStatus)
            }
        default:
            throw KeychainError.writeFailed(addStatus)
        }
    }

    enum KeychainError: Error {
        case randomFailed(OSStatus)
        case readFailed(OSStatus)
        case writeFailed(OSStatus)
    }
}
