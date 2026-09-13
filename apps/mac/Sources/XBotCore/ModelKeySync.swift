import CryptoKit
import Foundation
import XBotEngine

/// A model key the Mac holds, as the engine will need to find it.
public struct DesiredModelKey: Sendable, Equatable {
    public let providerId: String
    public let baseURL: String?
    public let plaintext: String

    public init(providerId: String, baseURL: String?, plaintext: String) {
        self.providerId = providerId
        self.baseURL = baseURL
        self.plaintext = plaintext
    }

    public var keyId: String { ModelKeyIdentity.keyId(providerId: providerId, baseURL: baseURL) }
}

/**
 Keeping the engine's vault in step with the Keychain.

 The Keychain is the source of truth (invariant 2); the vault is where a run finds a key (ADR-0002).
 Nothing connected the two — keys were read back only to show "Connected" — so no run ever reached a
 vendor with one.

 **Stores only what is missing or different.** Storing is audited, and the audit trail is append-only,
 so writing every key on every engine start would fill the one log a worried person reads with the
 app talking to itself. Whether a stored key is still the same one is answered by a fingerprint kept
 beside it: an HMAC of the key under the key-encryption key. That key already protects the ciphertext
 in the same row, so the fingerprint reveals nothing the row did not, and it cannot be checked against
 a guess by anyone who does not hold it. It needs no local record, so it stays right across restarts,
 reinstalls and a key changed while the engine was not running.

 **Revokes what was disconnected** — but only keys this app wrote, named with its own prefix. Anything
 else in the vault was put there deliberately by somebody else.
 */
public enum ModelKeySync {
    public struct Plan: Equatable, Sendable {
        public var store: [DesiredModelKey]
        /// Credential ids.
        public var revoke: [String]
    }

    public static func plan(
        desired: [DesiredModelKey],
        live: [StoredModelKey],
        fingerprint: (String) -> String
    ) -> Plan {
        let liveByKeyId = Dictionary(live.map { ($0.keyId, $0) }, uniquingKeysWith: { first, _ in first })
        let wanted = Set(desired.map(\.keyId))
        let store = desired.filter { key in
            guard let stored = liveByKeyId[key.keyId] else { return true }
            return stored.fingerprint != fingerprint(key.plaintext)
        }
        let revoke = live
            .filter { $0.keyId.hasPrefix(ModelKeyIdentity.prefix) && !wanted.contains($0.keyId) }
            .map(\.id)
        return Plan(store: store, revoke: revoke)
    }

    /// HMAC-SHA256 of the key under the key-encryption key, truncated. See the type's note.
    public static func fingerprint(of plaintext: String, keyEncryptionKey: String) -> String {
        let secret = SymmetricKey(data: Data(keyEncryptionKey.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(plaintext.utf8), using: secret)
        return mac.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Every key the Mac holds for a connected provider, as the engine will look for it.
    ///
    /// Ollama needs none and is skipped. A vendor with no key in the Keychain is skipped too: that is
    /// a provider marked connected whose key is gone, and there is nothing to send.
    public static func desired(
        connectedProviderIDs: Set<String>,
        custom: [CustomProvider],
        key: (String) -> String?
    ) -> [DesiredModelKey] {
        var keys: [DesiredModelKey] = []
        for id in connectedProviderIDs.sorted() where id != "ollama" {
            guard let routing = ModelProviderCatalog.engineRouting(for: id),
                  let plaintext = key(id), !plaintext.isEmpty
            else { continue }
            keys.append(DesiredModelKey(providerId: routing.id, baseURL: routing.baseURL, plaintext: plaintext))
        }
        for provider in custom {
            guard let plaintext = key(provider.id), !plaintext.isEmpty else { continue }
            keys.append(DesiredModelKey(providerId: "openai-compatible", baseURL: provider.baseURL, plaintext: plaintext))
        }
        return keys
    }
}
