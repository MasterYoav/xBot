import Foundation
import XBotBrain
import XBotRemote

/// Abilities from a phone: the same catalog as the Mac's Abilities page.
extension RemoteHost {
    /// The Mac's catalog; tests put a scripted one here.
    var abilityCatalog: AbilityCatalog {
        get { abilityCatalogOverride ?? workspace.abilities }
        set { abilityCatalogOverride = newValue }
    }

    func answerAbilities(_ message: ClientMessage) async -> (UUID?, HostMessage?) {
        let catalog = abilityCatalog
        switch message {
        case .listAbilities(let request, let refresh):
            if refresh || AbilityKind.allCases.allSatisfy({ catalog.items[$0] == nil }) { await catalog.refresh() }
            return (request, abilitiesAnswer(request))

        case .setAbility(let request, let id, let enabled):
            guard let ability = find(id) else { return (request, missing(request)) }
            guard ability.toggle != nil else {
                return (request, refusal(request, ability.fixedReason ?? String(localized: "That one can't be switched from here.")))
            }
            await catalog.setEnabled(ability, enabled)
            return (request, abilitiesAnswer(request))

        case .removeAbility(let request, let id):
            guard let ability = find(id) else { return (request, missing(request)) }
            guard ability.removal != nil else { return (request, refusal(request, String(localized: "That one can't be removed from here."))) }
            await catalog.remove(ability)
            return (request, abilitiesAnswer(request))

        case .listPlugins(let request):
            await catalog.loadMarketplace()
            return (request, abilitiesAnswer(request, plugins: true))

        case .installPlugin(let request, let id):
            if catalog.marketplace.isEmpty { await catalog.loadMarketplace() }
            guard let plugin = catalog.marketplace.first(where: { $0.id == id }) else {
                return (request, refusal(request, String(localized: "That plugin isn't in the marketplace.")))
            }
            await catalog.install(plugin)
            return (request, abilitiesAnswer(request, plugins: true))

        case .addMCP(let request, let name, let command, let arguments, let url, let agents):
            let kinds = Set(agents.compactMap(HarnessKind.init(rawValue:)))
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let target: NewMCPServer.Target?
            if let url, !url.trimmingCharacters(in: .whitespaces).isEmpty { target = .url(url.trimmingCharacters(in: .whitespaces)) }
            else if let command, !command.trimmingCharacters(in: .whitespaces).isEmpty { target = .command(command.trimmingCharacters(in: .whitespaces), arguments: arguments) }
            else { target = nil }
            guard !name.isEmpty, let target, !kinds.isEmpty else {
                return (request, refusal(request, String(localized: "A server needs a name, a command or address, and an agent.")))
            }
            guard await catalog.addMCP(NewMCPServer(name: name, target: target, agents: kinds)) else {
                return (request, refusal(request, String(localized: "The server couldn't be added.")))
            }
            return (request, abilitiesAnswer(request))

        default:
            return (nil, nil)
        }
    }

    private func find(_ id: String) -> Ability? {
        AbilityKind.allCases.lazy.compactMap { self.abilityCatalog.items[$0]?.first { $0.id == id } }.first
    }

    private func missing(_ request: UUID) -> HostMessage {
        refusal(request, String(localized: "That isn't on the Mac any more."))
    }

    private func refusal(_ request: UUID, _ reason: String) -> HostMessage {
        .reply(requestID: request, ok: false, reason: reason, chatID: nil)
    }

    private func abilitiesAnswer(_ request: UUID, plugins: Bool = false) -> HostMessage {
        let catalog = abilityCatalog
        let items = AbilityKind.allCases.flatMap { kind in
            (catalog.items[kind] ?? []).map { a in
                let status: String? = switch a.status {
                case .connected: "connected"; case .needsSignIn: "needsSignIn"; case .failed: "failed"; case .pending: "pending"; case nil: nil
                }
                return RemoteAbility(id: a.id, agent: a.agent.rawValue, kind: a.kind.rawValue, title: a.title, source: a.source,
                                     summary: a.summary, enabled: a.enabled, canSwitch: a.toggle != nil, fixedReason: a.fixedReason,
                                     status: status, canRemove: a.removal != nil)
            }
        }
        let market: [RemotePlugin]? = plugins || !catalog.marketplace.isEmpty
            ? catalog.marketplace.map { RemotePlugin(id: $0.id, agent: $0.agent.rawValue, name: $0.name, marketplace: $0.marketplace,
                                                    summary: $0.summary, installed: $0.installed) }
            : nil
        return .abilities(requestID: request, items: items, missing: catalog.missingAgents.map(\.rawValue), plugins: market)
    }
}
