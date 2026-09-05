import Foundation
import Observation
import XBotEngine

/// Settings → Agents: defaults for agents created after this screen is saved.
@MainActor
@Observable
public final class AgentDefaultsState {
    public var defaultDescription = ""
    public var defaultModelID: String?

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() {
        defaultDescription = AgentDefaultsStore.roleDescription(defaults: defaults)
        defaultModelID = AgentDefaultsStore.defaultModel(defaults: defaults)?.wireIdentity
    }

    public func save(models: [ModelSelection]) {
        AgentDefaultsStore.saveRoleDescription(
            defaultDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            defaults: defaults
        )
        let model = models.first { $0.wireIdentity == defaultModelID }
        AgentDefaultsStore.saveDefaultModel(model, defaults: defaults)
    }

    public func draft(named name: String) -> AgentDraft {
        let trimmed = defaultDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return AgentDraft(
            name: name,
            roleDescription: trimmed,
            model: AgentDefaultsStore.defaultModel(defaults: defaults)
        )
    }
}

extension ModelSelection {
    /// Stable picker identity across provider display names.
    public var wireIdentity: String {
        "\(providerID)|\(model)|\(baseURL ?? "")"
    }
}
