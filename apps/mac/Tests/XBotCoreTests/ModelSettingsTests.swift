import Foundation
import Testing
@testable import XBotCore

/// Settings → Models, with the Keychain, the network and the preference domain all injected.
///
/// The rules under test are the ones a person would notice being wrong: a bad key must not be
/// stored, disconnecting must actually remove it, and Ollama must never be presented as something
/// to configure.
@Suite @MainActor
struct ModelSettingsStateTests {
    /// A vault that keeps its keys in memory, so nothing here touches the login keychain.
    private final class MemoryVault: @unchecked Sendable {
        private let lock = NSLock()
        private var keys: [String: String] = [:]
        var failWrites = false

        var vault: ProviderKeyVault {
            ProviderKeyVault(
                save: { [self] key, provider in
                    if failWrites { throw CocoaError(.fileWriteUnknown) }
                    lock.withLock { keys[provider] = key }
                },
                key: { [self] provider in lock.withLock { keys[provider] } },
                remove: { [self] provider in
                    if failWrites { throw CocoaError(.fileWriteUnknown) }
                    lock.withLock { keys[provider] = nil }
                }
            )
        }

        func stored(_ provider: String) -> String? { lock.withLock { keys[provider] } }
        func preload(_ provider: String, _ key: String) { lock.withLock { keys[provider] = key } }
    }

    private func state(
        vault: MemoryVault,
        status: Int,
        body: [String: Any] = ["data": [["id": "a"], ["id": "b"]]]
    ) -> ModelSettingsState {
        ModelSettingsState(
            validator: ModelProviderValidator(fetch: answering(status: status, body: body)),
            vault: vault.vault,
            connections: isolatedConnectionStore()
        )
    }

    @Test func aValidKeyIsStoredAndTheRowSaysHowManyModels() async {
        let vault = MemoryVault()
        let settings = state(vault: vault, status: 200)

        await settings.connect(providerID: "openai", key: "sk-good")

        #expect(vault.stored("openai") == "sk-good")
        let row = settings.rows.first { $0.id == "openai" }
        #expect(row?.state == .connected(modelCount: 2))
    }

    /// The sequence that matters. Storing before validating leaves a rejected key in the Keychain,
    /// which unblocks the composer and then fails on the agent's first message.
    @Test func aRejectedKeyIsNeverStored() async {
        let vault = MemoryVault()
        let settings = state(vault: vault, status: 401, body: [:])

        await settings.connect(providerID: "anthropic", key: "sk-bad")

        #expect(vault.stored("anthropic") == nil)
        guard case .failed = settings.rows.first(where: { $0.id == "anthropic" })?.state else {
            Issue.record("a rejected key must leave the row in a failed state")
            return
        }
    }

    @Test func pastedWhitespaceAndABearerPrefixAreNotTheKey() async {
        let vault = MemoryVault()
        let settings = state(vault: vault, status: 200)

        await settings.connect(providerID: "openai", key: "  Bearer sk-good\n")

        #expect(vault.stored("openai") == "sk-good")
    }

    @Test func anEmptyFieldAsksForAKeyRatherThanCallingTheVendor() async {
        let vault = MemoryVault()
        let settings = state(vault: vault, status: 200)

        await settings.connect(providerID: "openai", key: "   ")

        #expect(vault.stored("openai") == nil)
        guard case .failed = settings.rows.first(where: { $0.id == "openai" })?.state else {
            Issue.record("an empty field should say so")
            return
        }
    }

    @Test func disconnectingRemovesTheKeyAndNotJustTheBadge() async {
        let vault = MemoryVault()
        let settings = state(vault: vault, status: 200)
        await settings.connect(providerID: "openai", key: "sk-good")

        settings.disconnect(providerID: "openai")

        #expect(vault.stored("openai") == nil)
        #expect(settings.rows.first { $0.id == "openai" }?.state == .notConnected)
    }

    /// A row that says "not connected" while the key is still stored is the worse failure: the
    /// person thinks they removed it and it is still there.
    @Test func aKeychainRefusalLeavesTheRowHonest() async {
        let vault = MemoryVault()
        let settings = state(vault: vault, status: 200)
        await settings.connect(providerID: "openai", key: "sk-good")
        vault.failWrites = true

        settings.disconnect(providerID: "openai")

        #expect(vault.stored("openai") == "sk-good")
        guard case .failed = settings.rows.first(where: { $0.id == "openai" })?.state else {
            Issue.record("a failed removal must not read as disconnected")
            return
        }
    }

    @Test func aKeyThatCannotBeSavedIsNotReportedAsConnected() async {
        let vault = MemoryVault()
        vault.failWrites = true
        let settings = state(vault: vault, status: 200)

        await settings.connect(providerID: "openai", key: "sk-good")

        guard case .failed(let message) = settings.rows.first(where: { $0.id == "openai" })?.state
        else {
            Issue.record("a key that could not be stored is not a connection")
            return
        }
        // docs/10-security.md: a key never reaches a message shown on screen.
        #expect(!message.contains("sk-good"))
    }

    @Test func loadShowsAProviderWhoseKeyIsAlreadyStored() {
        let vault = MemoryVault()
        vault.preload("anthropic", "sk-existing")
        let settings = state(vault: vault, status: 200)

        settings.load()

        #expect(settings.rows.first { $0.id == "anthropic" }?.isConnected == true)
        #expect(settings.rows.first { $0.id == "openai" }?.isConnected == false)
    }

    @Test func ollamaIsAskedForRatherThanConfigured() async {
        let vault = MemoryVault()
        let settings = state(
            vault: vault,
            status: 200,
            body: ["models": [["name": "llama3.1"], ["name": "qwen"], ["name": "phi"]]]
        )

        await settings.detectLocalProviders()

        let row = settings.rows.first { $0.id == "ollama" }
        #expect(row?.needsKey == false)
        #expect(row?.state == .detectedLocally(modelCount: 3))
    }

    @Test func ollamaNotRunningIsAStateRatherThanAnError() async {
        let vault = MemoryVault()
        let settings = state(vault: vault, status: 500, body: [:])

        await settings.detectLocalProviders()

        #expect(settings.rows.first { $0.id == "ollama" }?.state == .notDetected)
    }
}

/// One canned HTTP answer, captured per call rather than parked in a static.
///
/// The validator's job under test is turning a status and a body into a row state, not routing, so
/// one answer is enough — and a closure means two tests running at once cannot see each other's.
private func answering(status: Int, body: [String: Any]) -> ModelProviderValidator.Fetch {
    // Encoded out here: `[String: Any]` is not `Sendable`, and `Data` is. Serialising at the call
    // site rather than in the closure is also closer to what the validator actually receives.
    let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    return { request in
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
