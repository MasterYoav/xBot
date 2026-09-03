import Foundation
import XBotEngine

public struct ModelProviderOption: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let needsKey: Bool

    public init(id: String, name: String, subtitle: String, needsKey: Bool) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.needsKey = needsKey
    }
}

public enum ModelProviderCatalog: Sendable {
    public static let all: [ModelProviderOption] = [
        ModelProviderOption(
            id: "anthropic",
            name: String(localized: "Anthropic"),
            subtitle: String(localized: "Claude"),
            needsKey: true
        ),
        ModelProviderOption(
            id: "openai",
            name: String(localized: "OpenAI"),
            subtitle: String(localized: "GPT"),
            needsKey: true
        ),
        ModelProviderOption(
            id: "google",
            name: String(localized: "Google"),
            subtitle: String(localized: "Gemini"),
            needsKey: true
        ),
        ModelProviderOption(
            id: "xai",
            name: String(localized: "xAI"),
            subtitle: String(localized: "Grok"),
            needsKey: true
        ),
        ModelProviderOption(
            id: "ollama",
            name: String(localized: "Ollama"),
            subtitle: String(localized: "Runs on your Mac, no key needed"),
            needsKey: false
        ),
    ]

    public static func option(id: String) -> ModelProviderOption? {
        all.first { $0.id == id }
    }

    /// Plain-language vendor name for the Keychain sentence in onboarding.
    public static func vendorName(for providerID: String) -> String {
        option(id: providerID)?.name ?? providerID
    }

    /// Models offered in agent settings for connected providers (M2 client-side prep).
    public static func modelChoices(forConnectedProviders providerIDs: Set<String>) -> [String] {
        providerIDs.compactMap { id in
            switch id {
            case "anthropic": "claude-sonnet-4-5"
            case "openai": "gpt-4o"
            case "google": "gemini-2.0-flash"
            case "xai": "grok-2"
            case "ollama": "llama3.1"
            default: nil
            }
        }
    }

    /// How a catalogue row reaches the engine's router: a provider id, and a base URL when the
    /// router needs one.
    ///
    /// The two vocabularies differ on purpose. The catalogue is what a person picks from — "xAI",
    /// "Ollama" — while the router has one `openai-compatible` adapter that reaches both, and a
    /// dozen others, through a base URL. Mapping here rather than in the engine keeps the router's
    /// provider list short and keeps vendor branding out of it.
    ///
    /// ⚠️ Ollama's address is the host's, seen from inside the container: `localhost` there is the
    /// container's own loopback, not the Mac's. `host.docker.internal` is what Docker Desktop and
    /// Colima provide, and the runtime driver already passes it as the tool callback host. Apple's
    /// Containerization framework networks differently — tracked in docs/07-container-runtime.md.
    public static func engineRouting(for providerID: String) -> (id: String, baseURL: String?)? {
        switch providerID {
        case "anthropic", "openai", "google": (id: providerID, baseURL: nil)
        case "xai": (id: "openai-compatible", baseURL: "https://api.x.ai/v1")
        case "ollama":
            (id: "openai-compatible", baseURL: "http://host.docker.internal:11434/v1")
        default: nil
        }
    }

    /// A provider the person added by hand, as the router sees it.
    ///
    /// Always `openai-compatible`: that is the whole point of the custom row. The endpoint carries
    /// the identity, so the base URL is what distinguishes one from another.
    public static func selection(for custom: CustomProvider) -> ModelSelection {
        ModelSelection(
            provider: custom.name,
            providerID: "openai-compatible",
            model: custom.model,
            baseURL: custom.baseURL,
            // Not claimed. An arbitrary endpoint's capabilities are not knowable from here, and
            // docs/04 is explicit that silently degrading an agent to text-only is the worst
            // outcome — better to promise nothing than to promise tools it may not have.
            capabilities: []
        )
    }

    /// Picker rows when the engine has not published a model list yet (M5 fallback).
    public static func selections(forConnectedProviders providerIDs: Set<String>) -> [ModelSelection] {
        providerIDs.compactMap { id in
            guard let option = option(id: id),
                  let model = modelChoices(forConnectedProviders: [id]).first,
                  let routing = engineRouting(for: id)
            else { return nil }
            return ModelSelection(
                provider: option.name,
                providerID: routing.id,
                model: model,
                baseURL: routing.baseURL,
                capabilities: ["tools"]
            )
        }
    }

    /// Every model the agent picker can offer: the connected vendors, plus what was added by hand.
    public static func selections(
        forConnectedProviders providerIDs: Set<String>,
        custom: [CustomProvider]
    ) -> [ModelSelection] {
        selections(forConnectedProviders: providerIDs) + custom.map(selection(for:))
    }
}
