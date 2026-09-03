import Foundation

public enum ProviderValidationResult: Sendable, Equatable {
    case valid(modelCount: Int)
    case invalid(message: String)
}

/// Cheap models-list calls to validate a key before onboarding continues.
public struct ModelProviderValidator: Sendable {
    /// One request, one answer.
    ///
    /// Injected rather than reaching for `session.data(for:)` so a test can answer without a
    /// `URLProtocol` stub. A stub class holds its fixtures in statics, which every test in a
    /// parallel suite then shares — the same shape of bug `ProviderConnectionStore` had, and it
    /// shows up here as tests that pass alone and fail together.
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let fetch: Fetch

    public init(session: URLSession = .shared) {
        self.fetch = { try await session.data(for: $0) }
    }

    public init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    public func validate(providerID: String, key: String) async -> ProviderValidationResult {
        switch providerID {
        case "anthropic":
            await validateHTTP(
                url: URL(string: "https://api.anthropic.com/v1/models")!,
                headers: [
                    "x-api-key": ProviderKeyStore.normalize(key),
                    "anthropic-version": "2023-06-01",
                ],
                countPath: ["data"]
            )
        case "openai":
            await validateHTTP(
                url: URL(string: "https://api.openai.com/v1/models")!,
                headers: ["Authorization": "Bearer \(ProviderKeyStore.normalize(key))"],
                countPath: ["data"]
            )
        case "google":
            await validateGoogle(key: key)
        case "xai":
            await validateHTTP(
                url: URL(string: "https://api.x.ai/v1/models")!,
                headers: ["Authorization": "Bearer \(ProviderKeyStore.normalize(key))"],
                countPath: ["data"]
            )
        case "ollama":
            await validateOllama()
        default:
            .invalid(message: String(localized: "Unknown provider"))
        }
    }

    public func detectOllama() async -> ProviderValidationResult? {
        switch await validateOllama() {
        case .valid(let count): .valid(modelCount: count)
        default: nil
        }
    }

    private func validateGoogle(key: String) async -> ProviderValidationResult {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        components.queryItems = [URLQueryItem(name: "key", value: ProviderKeyStore.normalize(key))]
        guard let url = components.url else {
            return .invalid(message: String(localized: "Couldn't reach Google"))
        }
        return await validateHTTP(url: url, headers: [:], countPath: ["models"])
    }

    private func validateOllama() async -> ProviderValidationResult {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else {
            return .invalid(message: String(localized: "Ollama isn't running"))
        }
        return await validateHTTP(url: url, headers: [:], countPath: ["models"])
    }

    private func validateHTTP(
        url: URL,
        headers: [String: String],
        countPath: [String]
    ) async -> ProviderValidationResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        do {
            let (data, response) = try await fetch(request)
            guard let http = response as? HTTPURLResponse else {
                return .invalid(message: String(localized: "Couldn't reach the provider"))
            }
            switch http.statusCode {
            case 200:
                guard
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    return .valid(modelCount: 1)
                }
                var value: Any? = object
                for key in countPath {
                    value = (value as? [String: Any])?[key]
                }
                guard let array = value as? [[String: Any]] else {
                    return .valid(modelCount: 1)
                }
                return .valid(modelCount: max(array.count, 1))
            case 401, 403:
                return .invalid(message: String(localized: "That key didn't work"))
            default:
                return .invalid(message: String(localized: "Couldn't verify the key"))
            }
        } catch {
            return .invalid(message: String(localized: "Couldn't reach the provider"))
        }
    }
}
