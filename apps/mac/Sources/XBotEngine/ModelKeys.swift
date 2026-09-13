import Foundation

/// The vault key a model credential lives under — the Mac app's half of a contract with the engine.
///
/// The engine's `modelKeyId` in `shared/model-selection.ts` computes the same string, and the two
/// sides share no code, only this string. Each side's tests pin the same examples, which is what keeps
/// them from drifting. Built from what a run can see: the provider and its address, so two custom
/// endpoints — both `openai-compatible` — never share a key.
public enum ModelKeyIdentity {
    public static func keyId(providerId: String, baseURL: String?) -> String {
        let provider = providerId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var address = (baseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        while address.hasSuffix("/") { address.removeLast() }
        return address.isEmpty ? "xbot-model:\(provider)" : "xbot-model:\(provider)@\(address)"
    }

    /// Every key this app wrote starts with this, so the app never touches a credential it did not.
    public static let prefix = "xbot-model:"
}

/// A live model key in the engine's vault. The value never comes back; only what identifies it.
public struct StoredModelKey: Sendable, Equatable {
    public let id: String
    public let provider: String
    public let keyId: String
    /// Set by this app when it stored the key. See `ModelKeySync` for why it exists.
    public let fingerprint: String?

    public init(id: String, provider: String, keyId: String, fingerprint: String?) {
        self.id = id
        self.provider = provider
        self.keyId = keyId
        self.fingerprint = fingerprint
    }
}
