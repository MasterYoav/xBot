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

    /// Picker rows when the engine has not published a model list yet (M5 fallback).
    public static func selections(forConnectedProviders providerIDs: Set<String>) -> [ModelSelection] {
        providerIDs.compactMap { id in
            guard let option = option(id: id),
                  let model = modelChoices(forConnectedProviders: [id]).first
            else { return nil }
            return ModelSelection(provider: option.name, model: model, capabilities: ["tools"])
        }
    }
}
