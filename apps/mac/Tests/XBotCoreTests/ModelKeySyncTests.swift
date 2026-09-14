import Foundation
import Testing
import XBotEngine
@testable import XBotCore

/// Model keys reaching the engine's vault. See docs/plans/managed-bot-and-model-keys.md.
@Suite
struct ModelKeyIdentityTests {
    /// The same examples the engine pins in `server/tests/agent-model-keys.test.ts`. The two sides
    /// share only this string, so these examples are the contract.
    @Test func matchesTheEnginesKeyIds() {
        #expect(ModelKeyIdentity.keyId(providerId: "anthropic", baseURL: nil) == "xbot-model:anthropic")
        #expect(
            ModelKeyIdentity.keyId(providerId: "openai-compatible", baseURL: "https://api.x.ai/v1")
                == "xbot-model:openai-compatible@https://api.x.ai/v1"
        )
        #expect(
            ModelKeyIdentity.keyId(providerId: "openai-compatible", baseURL: " https://openrouter.ai/api/v1/ ")
                == "xbot-model:openai-compatible@https://openrouter.ai/api/v1"
        )
        #expect(ModelKeyIdentity.keyId(providerId: " Anthropic ", baseURL: nil) == "xbot-model:anthropic")
        #expect(ModelKeyIdentity.keyId(providerId: "openai", baseURL: "") == "xbot-model:openai")
    }
}

@Suite
struct ModelKeySyncPlanTests {
    private let fingerprint: (String) -> String = { ModelKeySync.fingerprint(of: $0, keyEncryptionKey: "kek") }
    private let anthropic = DesiredModelKey(providerId: "anthropic", baseURL: nil, plaintext: "sk-ant-1")

    private func stored(_ key: DesiredModelKey, fingerprint: String? = nil, id: String = "c1") -> StoredModelKey {
        StoredModelKey(id: id, provider: key.providerId, keyId: key.keyId, fingerprint: fingerprint ?? self.fingerprint(key.plaintext))
    }

    @Test func aKeyTheVaultDoesNotHaveIsStored() {
        let plan = ModelKeySync.plan(desired: [anthropic], live: [], fingerprint: fingerprint)
        #expect(plan.store == [anthropic])
        #expect(plan.revoke.isEmpty)
    }

    /// Storing is audited and the trail is append-only, so an unchanged key is never written again.
    @Test func anUnchangedKeyIsNotWrittenAgain() {
        let plan = ModelKeySync.plan(desired: [anthropic], live: [stored(anthropic)], fingerprint: fingerprint)
        #expect(plan.store.isEmpty)
        #expect(plan.revoke.isEmpty)
    }

    /// A key replaced while the engine was not running is still noticed, with no local record.
    @Test func aChangedKeyIsStoredAgain() {
        let replaced = DesiredModelKey(providerId: "anthropic", baseURL: nil, plaintext: "sk-ant-2")
        let plan = ModelKeySync.plan(desired: [replaced], live: [stored(anthropic)], fingerprint: fingerprint)
        #expect(plan.store == [replaced])
    }

    @Test func aDisconnectedKeyIsRevoked() {
        let plan = ModelKeySync.plan(desired: [], live: [stored(anthropic, id: "gone")], fingerprint: fingerprint)
        #expect(plan.revoke == ["gone"])
    }

    /// A credential somebody put in the vault by other means is theirs, and a sync never touches it.
    @Test func aKeyThisAppDidNotWriteIsNeverRevoked() {
        let foreign = StoredModelKey(id: "admin", provider: "openai", keyId: "openai-api-key", fingerprint: nil)
        let plan = ModelKeySync.plan(desired: [], live: [foreign], fingerprint: fingerprint)
        #expect(plan.revoke.isEmpty)
    }
}

@Suite
struct ModelKeySyncSourceTests {
    @Test func vendorsAreRoutedAsTheEngineSeesThem() {
        let keys = ModelKeySync.desired(
            connectedProviderIDs: ["anthropic", "xai", "ollama"],
            custom: [],
            key: { "key-for-\($0)" }
        )
        #expect(keys.contains(DesiredModelKey(providerId: "anthropic", baseURL: nil, plaintext: "key-for-anthropic")))
        #expect(keys.contains(DesiredModelKey(providerId: "openai-compatible", baseURL: "https://api.x.ai/v1", plaintext: "key-for-xai")))
        // Ollama needs no key.
        #expect(!keys.contains { $0.plaintext == "key-for-ollama" })
    }

    @Test func aProviderWithNoKeyInTheKeychainSendsNothing() {
        let keys = ModelKeySync.desired(connectedProviderIDs: ["openai"], custom: [], key: { _ in nil })
        #expect(keys.isEmpty)
    }

    @Test func customEndpointsAreKeyedByTheirAddress() {
        let custom = CustomProvider(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", model: "x")
        let keys = ModelKeySync.desired(connectedProviderIDs: [], custom: [custom], key: { $0 == custom.id ? "or-key" : nil })
        #expect(keys == [DesiredModelKey(providerId: "openai-compatible", baseURL: "https://openrouter.ai/api/v1", plaintext: "or-key")])
    }

    @Test func theFingerprintIsKeyedAndNeverTheKey() {
        let a = ModelKeySync.fingerprint(of: "sk-ant-secret", keyEncryptionKey: "kek-1")
        #expect(a == ModelKeySync.fingerprint(of: "sk-ant-secret", keyEncryptionKey: "kek-1"))
        #expect(a != ModelKeySync.fingerprint(of: "sk-ant-other", keyEncryptionKey: "kek-1"))
        // Without the key-encryption key it cannot be checked against a guess.
        #expect(a != ModelKeySync.fingerprint(of: "sk-ant-secret", keyEncryptionKey: "kek-2"))
        #expect(!a.contains("secret"))
    }
}

@MainActor
@Suite
struct AppModelKeySyncTests {
    final class Keys: @unchecked Sendable {
        var current: [DesiredModelKey] = []
    }

    @Test func unreadableKeychainDoesNotRevokeAVaultKey() async throws {
        let engine = StubEngineClient(tokenDelay: .zero)
        try await engine.storeModelKey("existing", providerId: "anthropic", baseURL: nil, fingerprint: "old")
        let state = AppState(engine: engine)
        await state.load()
        state.overrideModelKeysForTesting { throw EngineError.notRunning }
        await state.syncModelKeys()
        #expect(await engine.vaultValues["xbot-model:anthropic"] == "existing")
        #expect(state.modelKeySyncProblem != nil)
        #expect(!state.canSend)
        state.overrideModelKeysForTesting { [] }
        await state.syncModelKeys()
        #expect(state.modelKeySyncProblem == nil)
        #expect(state.canSend)
    }

    @Test func keysReachTheVaultOnceAndFollowChanges() async throws {
        let engine = StubEngineClient(tokenDelay: .zero)
        let keys = Keys()
        keys.current = [DesiredModelKey(providerId: "anthropic", baseURL: nil, plaintext: "sk-ant-1")]
        let state = AppState(engine: engine)
        state.overrideModelKeysForTesting({ keys.current })

        await state.syncModelKeys()
        #expect(await engine.vaultValues["xbot-model:anthropic"] == "sk-ant-1")
        #expect(await engine.vaultWrites == 1)

        // Nothing changed: nothing written, so the audit trail does not fill with the app's echo.
        await state.syncModelKeys()
        #expect(await engine.vaultWrites == 1)

        keys.current = [DesiredModelKey(providerId: "anthropic", baseURL: nil, plaintext: "sk-ant-2")]
        await state.syncModelKeys()
        #expect(await engine.vaultValues["xbot-model:anthropic"] == "sk-ant-2")
        #expect(await engine.vaultWrites == 2)

        keys.current = []
        await state.syncModelKeys()
        #expect(await engine.vaultValues["xbot-model:anthropic"] == nil)
    }
}
