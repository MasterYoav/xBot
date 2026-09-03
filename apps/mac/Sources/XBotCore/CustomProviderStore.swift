import Foundation
import XBotEngine

/// A provider the person added themselves: a name, an endpoint, and optionally a key.
///
/// One of these covers OpenRouter, Groq, Together, Fireworks, DeepSeek, Mistral, LM Studio, vLLM,
/// llama.cpp and any corporate gateway, because they all speak the OpenAI API. docs/04 calls this
/// the row that turns "every AI" from a roadmap item into a text field.
public struct CustomProvider: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public var name: String
    public var baseURL: String
    /// The model to send. An endpoint names its own catalogue, so this is typed, not picked.
    public var model: String

    public init(id: String = "custom:\(UUID().uuidString)", name: String, baseURL: String, model: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
    }
}

public enum CustomProviderProblem: Sendable, Equatable {
    case nameMissing
    case urlMissing
    case urlMalformed
    /// A key would cross the network in clear text. See `insecureKeyOverPlainHTTP`.
    case insecureKeyOverPlainHTTP
}

/// The custom providers this person has added.
///
/// Names and endpoints live in the preference domain; keys never do — those go to the Keychain
/// through `ProviderKeyVault`, keyed by the provider's id, exactly like a vendor key.
public struct CustomProviderStore: Sendable {
    /// `UserDefaults` is documented thread-safe but is not marked `Sendable`.
    nonisolated(unsafe) private let defaults: any KeyValueDefaults

    private static let key = "xbot.customProviders"

    public init(defaults: any KeyValueDefaults = UserDefaults.standard) {
        self.defaults = defaults
    }

    public static let shared = CustomProviderStore()

    public var all: [CustomProvider] {
        // Stored as JSON strings rather than a dictionary array, because `stringArray(forKey:)` is
        // the accessor this app's defaults seam exposes and a custom provider is a small record.
        (defaults.stringArray(forKey: Self.key) ?? []).compactMap {
            guard let data = $0.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(CustomProvider.self, from: data)
        }
    }

    public func add(_ provider: CustomProvider) {
        var providers = all.filter { $0.id != provider.id }
        providers.append(provider)
        write(providers)
    }

    public func remove(id: String) {
        write(all.filter { $0.id != id })
    }

    private func write(_ providers: [CustomProvider]) {
        let encoded = providers.compactMap { provider -> String? in
            guard let data = try? JSONEncoder().encode(provider) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        defaults.set(encoded, forKey: Self.key)
    }

    /// What is wrong with what was typed, or nothing.
    ///
    /// ⚠️ The last case is a security rule, not a nicety. A key sent to a plain-`http` address
    /// crosses the network in clear text, and the whole point of the Keychain is that the key is
    /// not readable by anything that has not been asked. Loopback is exempt because it never leaves
    /// the machine, and that is exactly where a local Ollama or LM Studio lives — refusing there
    /// would block the one case the person is most likely to have.
    public static func problem(
        name: String,
        baseURL: String,
        hasKey: Bool
    ) -> CustomProviderProblem? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .nameMissing
        }
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .urlMissing }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty,
              scheme == "http" || scheme == "https"
        else { return .urlMalformed }

        if hasKey, scheme == "http", !Self.isLoopback(host) {
            return .insecureKeyOverPlainHTTP
        }
        return nil
    }

    static func isLoopback(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1", "host.docker.internal"].contains(host.lowercased())
    }
}
