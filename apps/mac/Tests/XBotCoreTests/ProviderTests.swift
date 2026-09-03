import Foundation
import Testing
import XBotEngine
@testable import XBotCore

@Suite(.serialized)
struct ProviderKeyStoreTests {
    @Test func trimsWhitespaceAndBearerPrefix() {
        #expect(ProviderKeyStore.normalize("  sk-test  ") == "sk-test")
        #expect(ProviderKeyStore.normalize("Bearer sk-test") == "sk-test")
        #expect(ProviderKeyStore.normalize("bearer sk-test") == "sk-test")
    }
}

/// Defaults that live and die with the test, touching neither disk nor the real domain.
final class MemoryDefaults: KeyValueDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    func stringArray(forKey defaultName: String) -> [String]? {
        lock.withLock { values[defaultName] as? [String] }
    }

    func bool(forKey defaultName: String) -> Bool {
        lock.withLock { values[defaultName] as? Bool ?? false }
    }

    func integer(forKey defaultName: String) -> Int {
        lock.withLock { values[defaultName] as? Int ?? 0 }
    }

    func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { values[defaultName] = value }
    }

    func removeObject(forKey defaultName: String) {
        lock.withLock { values[defaultName] = nil }
    }
}

/// A store isolated per call, holding only the vendor keys the test names.
///
/// These used to run against `UserDefaults.standard` and the developer's real Keychain, which made
/// them order-dependent against every other suite that wrote the same keys, and dependent on
/// whether whoever ran them had ever connected a provider in the real app.
func isolatedConnectionStore(storedKeys: Set<String> = []) -> ProviderConnectionStore {
    ProviderConnectionStore(
        defaults: MemoryDefaults(),
        hasStoredKey: { storedKeys.contains($0) }
    )
}

@Suite
struct ProviderConnectionStoreTests {
    @Test func skipBlocksSendingUntilConnected() {
        let store = isolatedConnectionStore()
        #expect(!store.requiresModelForComposer())
        store.markSkipped()
        #expect(store.skippedDuringOnboarding)
        // No `if` guard any more. It was there because the real Keychain might already hold a key
        // and flip the answer; this store's keys are the ones the test names.
        #expect(store.requiresModelForComposer())
        store.markConnected("anthropic")
        #expect(!store.requiresModelForComposer())
    }

    @Test func aStoredVendorKeyCountsAsAConnection() {
        // The composer must not stay blocked for somebody who connected a provider and never
        // finished onboarding: the key is the connection, whatever the skip flag says.
        let store = isolatedConnectionStore(storedKeys: ["anthropic"])
        store.markSkipped()
        #expect(store.hasAnyConnection)
        #expect(!store.requiresModelForComposer())
    }

    @Test func ollamaNeedsNoKeyToCount() {
        // Ollama is detected, not configured, so an absent Keychain entry says nothing about it.
        // Without this, a local-only user is told to connect a model they are already running.
        let store = isolatedConnectionStore()
        #expect(!store.hasAnyConnection)
        store.markConnected("ollama")
        #expect(store.hasAnyConnection)
    }

    @Test func twoStoresDoNotShareState() {
        // The property the old enum could not have: this is what made the suite flaky.
        let a = isolatedConnectionStore()
        let b = isolatedConnectionStore()
        a.markSkipped()
        #expect(a.skippedDuringOnboarding)
        #expect(!b.skippedDuringOnboarding)
    }
}

@Suite(.serialized)
struct ModelProviderCatalogTests {
    @Test func modelChoicesFollowConnectedProviders() {
        let choices = ModelProviderCatalog.modelChoices(forConnectedProviders: ["anthropic", "openai"])
        #expect(choices.contains("claude-sonnet-4-5"))
        #expect(choices.contains("gpt-4o"))
        #expect(choices.count == 2)
    }

    @Test func selectionsBuildPickerRows() {
        let rows = ModelProviderCatalog.selections(forConnectedProviders: ["anthropic"])
        #expect(rows.count == 1)
        #expect(rows[0].provider == "Anthropic")
        #expect(rows[0].model == "claude-sonnet-4-5")
    }
}

@Suite(.serialized)
struct ModelProviderValidatorTests {
    @Test func openAIKeyValidationCountsModels() async {
        ValidatorStubProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ValidatorStubProtocol.self]
        let session = URLSession(configuration: configuration)
        ValidatorStubProtocol.register(
            status: 200,
            body: ["data": [["id": "gpt-4"], ["id": "gpt-4o"]]],
            host: "api.openai.com"
        )

        let validator = ModelProviderValidator(session: session)
        let result = await validator.validate(
            providerID: "openai",
            key: "sk-test"
        )

        guard case .valid(let count) = result else {
            Issue.record("expected valid, got \(result)")
            return
        }
        #expect(count == 2)
    }

    @Test func rejectedKeyReturnsPlainMessage() async {
        ValidatorStubProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ValidatorStubProtocol.self]
        let session = URLSession(configuration: configuration)
        ValidatorStubProtocol.register(status: 401, body: [:], host: "api.anthropic.com")

        let result = await ModelProviderValidator(session: session).validate(
            providerID: "anthropic",
            key: "bad"
        )
        guard case .invalid = result else {
            Issue.record("expected invalid")
            return
        }
    }
}

private final class ValidatorStubProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: (status: Int, body: [String: Any])] = [:]

    static func register(status: Int, body: [String: Any], host: String) {
        lock.lock()
        responses[host] = (status, body)
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        responses = [:]
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.lock.lock()
        let fixture = Self.responses[host] ?? (404, [String: Any]())
        Self.lock.unlock()
        let data = try! JSONSerialization.data(withJSONObject: fixture.body)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: fixture.status,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
