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

    // MARK: - custom providers

    private func settings(
        vault: MemoryVault,
        custom: CustomProviderStore,
        status: Int
    ) -> ModelSettingsState {
        ModelSettingsState(
            validator: ModelProviderValidator(
                fetch: answering(status: status, body: ["data": [["id": "m"]]])
            ),
            vault: vault.vault,
            connections: isolatedConnectionStore(),
            customStore: custom
        )
    }

    @Test func aCustomEndpointIsCheckedBeforeItIsStored() async {
        let vault = MemoryVault()
        let custom = CustomProviderStore(defaults: MemoryDefaults())
        let settings = settings(vault: vault, custom: custom, status: 200)

        let added = await settings.addCustomProvider(
            name: "Work gateway",
            baseURL: "https://ai.corp.example/v1",
            model: "gpt-4o",
            key: "sk-gateway"
        )

        #expect(added)
        #expect(settings.custom.first?.name == "Work gateway")
        #expect(vault.stored(settings.custom.first?.id ?? "") == "sk-gateway")
    }

    @Test func anEndpointThatDoesNotAnswerIsNotAdded() async {
        // Storing it anyway would put a provider in the agent picker that every message fails on.
        let vault = MemoryVault()
        let custom = CustomProviderStore(defaults: MemoryDefaults())
        let settings = settings(vault: vault, custom: custom, status: 500)

        let added = await settings.addCustomProvider(
            name: "Broken",
            baseURL: "https://nothing.example/v1",
            model: "m",
            key: ""
        )

        #expect(!added)
        #expect(settings.custom.isEmpty)
        #expect(settings.customProblem != nil)
    }

    /// A local endpoint needs no key, and demanding one would rule out the case this row exists for.
    @Test func aLocalEndpointWithNoKeyIsFine() async {
        let vault = MemoryVault()
        let custom = CustomProviderStore(defaults: MemoryDefaults())
        let settings = settings(vault: vault, custom: custom, status: 200)

        let added = await settings.addCustomProvider(
            name: "LM Studio",
            baseURL: "http://localhost:1234/v1",
            model: "local-model",
            key: ""
        )

        #expect(added)
        #expect(settings.custom.count == 1)
    }

    /// A key to a plain-http address on another machine crosses the network in clear text.
    @Test func aKeyToAnInsecureAddressIsRefusedBeforeAnyRequest() async {
        let vault = MemoryVault()
        let custom = CustomProviderStore(defaults: MemoryDefaults())
        let settings = settings(vault: vault, custom: custom, status: 200)

        let added = await settings.addCustomProvider(
            name: "Gateway",
            baseURL: "http://ai.corp.example/v1",
            model: "m",
            key: "sk-secret"
        )

        #expect(!added)
        #expect(settings.custom.isEmpty)
        // Nothing was written, and the key never left the app.
        #expect(vault.stored("sk-secret") == nil)
        #expect(settings.customProblem?.contains("https://") == true)
    }

    @Test func removingACustomProviderTakesItsKeyToo() async {
        let vault = MemoryVault()
        let custom = CustomProviderStore(defaults: MemoryDefaults())
        let settings = settings(vault: vault, custom: custom, status: 200)
        _ = await settings.addCustomProvider(
            name: "Gateway",
            baseURL: "https://ai.corp.example/v1",
            model: "m",
            key: "sk-gateway"
        )
        let id = try! #require(settings.custom.first?.id)

        settings.removeCustomProvider(id: id)

        #expect(settings.custom.isEmpty)
        // An orphaned key is one no screen can ever show or delete.
        #expect(vault.stored(id) == nil)
    }

    @Test func customProvidersSurviveAReload() async {
        let vault = MemoryVault()
        let custom = CustomProviderStore(defaults: MemoryDefaults())
        let first = settings(vault: vault, custom: custom, status: 200)
        _ = await first.addCustomProvider(
            name: "Gateway",
            baseURL: "https://ai.corp.example/v1",
            model: "m",
            key: ""
        )

        let second = settings(vault: vault, custom: custom, status: 200)
        second.load()

        #expect(second.custom.map(\.name) == ["Gateway"])
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
