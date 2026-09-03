import Foundation

/// Reading and writing vendor keys, as three closures rather than a hard call to the Keychain.
///
/// The Keychain is a process-wide, machine-wide store. Code that reaches it directly can only be
/// tested by writing to the developer's own login keychain — which prompts, persists between runs,
/// and makes whether a test passes depend on what is already on the machine. This is the seam that
/// lets a test say what keys exist.
///
/// Closures rather than a protocol because there are three operations and exactly two
/// implementations, and a protocol would be the longer way to write the same thing.
public struct ProviderKeyVault: Sendable {
    public var save: @Sendable (_ key: String, _ providerID: String) throws -> Void
    public var key: @Sendable (_ providerID: String) throws -> String?
    public var remove: @Sendable (_ providerID: String) throws -> Void

    public init(
        save: @escaping @Sendable (String, String) throws -> Void,
        key: @escaping @Sendable (String) throws -> String?,
        remove: @escaping @Sendable (String) throws -> Void
    ) {
        self.save = save
        self.key = key
        self.remove = remove
    }

    /// The real one. Keys live in the macOS Keychain and nowhere else — see docs/10-security.md.
    public static let keychain = ProviderKeyVault(
        save: { try ProviderKeyStore.save($0, for: $1) },
        key: { try ProviderKeyStore.key(for: $0) },
        remove: { try ProviderKeyStore.remove(providerID: $0) }
    )
}
