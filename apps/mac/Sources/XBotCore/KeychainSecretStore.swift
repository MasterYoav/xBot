import Foundation
import Security

enum KeychainSecretStore {
    enum Error: Swift.Error {
        case randomFailed(OSStatus)
        case readFailed(OSStatus)
        case writeFailed(OSStatus)
    }

    static func string(service: String, account: String = "default") throws -> String {
        if let existing = try read(service: service, account: account) { return existing }
        let fresh = try generate()
        try save(fresh, service: service, account: account)
        return fresh
    }

    /// Read a user-supplied secret. Does not generate one.
    static func readExisting(service: String, account: String) throws -> String? {
        try read(service: service, account: account)
    }

    /// Write or replace a user-supplied secret.
    static func write(_ value: String, service: String, account: String) throws {
        try save(value, service: service, account: account)
    }

    static func remove(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error.writeFailed(status)
        }
    }

    private static func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw Error.randomFailed(status)
        }
        return Data(bytes).base64EncodedString()
    }

    private static func read(service: String, account: String) throws -> String? {
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
            throw Error.readFailed(status)
        }
        return string
    }

    private static func save(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
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
                throw Error.writeFailed(updateStatus)
            }
        default:
            throw Error.writeFailed(addStatus)
        }
    }
}
