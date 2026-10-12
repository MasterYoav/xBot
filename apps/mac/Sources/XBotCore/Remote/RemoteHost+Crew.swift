import Foundation
import XBotBrain
import XBotRemote

/// The crew from a phone: list, hire, edit, talk to, let go (and undo), and the look's preview.
extension RemoteHost {
    func answerCrew(_ message: ClientMessage) -> (UUID?, HostMessage?) {
        switch message {
        case .listCrew(let request):
            return (request, crewAnswer(request))

        case .saveCrew(let request, let remote):
            guard let harness = HarnessKind(rawValue: remote.agent) else {
                return (request, refusal(request, String(localized: "That agent isn't known on the Mac.")))
            }
            if let projectID = remote.projectID, !workspace.projects.contains(where: { $0.id == projectID }) {
                return (request, refusal(request, String(localized: "That project isn't on the Mac any more.")))
            }
            let name = remote.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return (request, refusal(request, String(localized: "They need a name."))) }
            var agent = workspace.agent(remote.id) ?? { var hired = workspace.hire(); hired.id = remote.id; return hired }()
            agent.name = name
            agent.role = remote.role
            agent.instructions = remote.instructions
            agent.avatar = Self.avatar(remote.avatar, over: agent.avatar)
            agent.harness = harness
            agent.model = remote.model
            agent.projectID = remote.projectID
            workspace.saveAgent(agent)
            return (request, crewAnswer(request))

        case .deleteCrew(let request, let id):
            guard let agent = workspace.agent(id) else { return (request, refusal(request, String(localized: "They aren't on the Mac any more."))) }
            guard !agent.isHeadMaster, let undo = workspace.deleteAgent(id) else {
                return (request, refusal(request, String(localized: "\(agent.name) founded the place and stays.")))
            }
            undoCrewDelete = undo
            return (request, crewAnswer(request))

        case .undoDeleteCrew(let request):
            guard let undo = undoCrewDelete else { return (request, refusal(request, String(localized: "Nothing to bring back."))) }
            undoCrewDelete = nil
            undo()
            return (request, crewAnswer(request))

        case .talkTo(let request, let id, let text):
            guard let agent = workspace.agent(id) else { return (request, refusal(request, String(localized: "They aren't on the Mac any more."))) }
            guard workspace.availableHarnesses.contains(agent.harness) else {
                return (request, refusal(request, String(localized: "\(agent.harness.displayName) isn't installed on the Mac.")))
            }
            guard let chat = workspace.startChat(with: agent, in: agent.projectID, select: false) else {
                return (request, refusal(request, String(localized: "The chat couldn't be started.")))
            }
            workspace.markSeen(id)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { _ = workspace.send(text, in: chat.id) }
            return (request, .reply(requestID: request, ok: true, reason: nil, chatID: chat.id))

        case .drawAvatar(let request, let remote):
            return (request, .avatarImage(requestID: request, image: drawAvatar?(Self.avatar(remote, over: AgentAvatar()))))

        default:
            return (nil, nil)
        }
    }

    private func refusal(_ request: UUID, _ reason: String) -> HostMessage {
        .reply(requestID: request, ok: false, reason: reason, chatID: nil)
    }

    private func crewAnswer(_ request: UUID) -> HostMessage {
        let members = workspace.agents.map { agent -> RemoteCrewMember in
            let status = workspace.status(of: agent.id)
            let (word, activity): (String, String?) = switch status {
            case .idle: ("idle", nil)
            case .working(let activity, _): ("working", activity)
            case .done: ("done", nil)
            }
            return RemoteCrewMember(
                id: agent.id, name: agent.name, role: agent.role, instructions: agent.instructions,
                avatar: Self.remote(agent.avatar), agent: agent.harness.rawValue, model: agent.model, projectID: agent.projectID,
                isHeadMaster: agent.isHeadMaster, status: word, activity: activity, image: drawAvatar?(agent.avatar))
        }
        let parts = AgentAvatar.Part.allCases.map { RemoteAvatarPart(key: $0.rawValue, title: $0.title, count: $0.count) }
        return .crew(requestID: request, members: members, parts: parts)
    }

    static func remote(_ avatar: AgentAvatar) -> RemoteAvatar {
        RemoteAvatar(parts: Dictionary(uniqueKeysWithValues: AgentAvatar.Part.allCases.map { ($0.rawValue, avatar[$0]) }))
    }

    /// The phone's choices over `base`, each kept within what the sprite draws.
    static func avatar(_ remote: RemoteAvatar, over base: AgentAvatar) -> AgentAvatar {
        var avatar = base
        for part in AgentAvatar.Part.allCases {
            if let value = remote.parts[part.rawValue] { avatar[part] = ((value % part.count) + part.count) % part.count }
        }
        return avatar
    }
}
