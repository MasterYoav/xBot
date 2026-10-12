import Foundation

extension Workspace {
    static let workplaceKey = "workplace"

    public var workplace: WorkplaceSetting {
        get {
            access(keyPath: \.workplaceRevision)
            return defaults.string(forKey: Self.workplaceKey).flatMap(WorkplaceSetting.init(rawValue:)) ?? .village
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.workplaceKey)
            workplaceRevision += 1
        }
    }
}

extension Workspace {
    /// An agent as the world draws it.
    public func resident(_ agent: Agent) -> WorldResident {
        let status: WorldResident.Status = switch status(of: agent.id) {
        case .working(let activity, _): .working(activity)
        case .done: .done
        case .idle: .idle
        }
        return WorldResident(id: agent.id, name: agent.name, role: agent.role, avatar: agent.avatar,
                             isHeadMaster: agent.isHeadMaster, status: status)
    }
}
