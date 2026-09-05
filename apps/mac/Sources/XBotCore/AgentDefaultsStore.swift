import Foundation
import XBotEngine

/// Defaults applied when a new agent is created from the rail or command palette.
public enum AgentDefaultsStore: Sendable {
    private static let descriptionKey = "xbot.agentDefaults.roleDescription"
    private static let modelKey = "xbot.agentDefaults.modelSelection"

    public static func roleDescription(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: descriptionKey) ?? ""
    }

    public static func saveRoleDescription(_ text: String, defaults: UserDefaults = .standard) {
        defaults.set(text, forKey: descriptionKey)
    }

    public static func defaultModel(defaults: UserDefaults = .standard) -> ModelSelection? {
        guard let dict = defaults.dictionary(forKey: modelKey) else { return nil }
        guard let providerID = dict["providerId"] as? String,
              let model = dict["model"] as? String
        else { return nil }
        let baseURL = dict["baseURL"] as? String
        return ModelSelection(
            provider: ModelSelection.displayName(providerID: providerID, baseURL: baseURL),
            providerID: providerID,
            model: model,
            baseURL: baseURL,
            capabilities: dict["capabilities"] as? [String] ?? []
        )
    }

    public static func saveDefaultModel(_ model: ModelSelection?, defaults: UserDefaults = .standard) {
        guard let model else {
            defaults.removeObject(forKey: modelKey)
            return
        }
        var dict = model.wireFormat
        if !model.capabilities.isEmpty {
            dict["capabilities"] = model.capabilities
        }
        defaults.set(dict, forKey: modelKey)
    }

    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: descriptionKey)
        defaults.removeObject(forKey: modelKey)
    }
}
