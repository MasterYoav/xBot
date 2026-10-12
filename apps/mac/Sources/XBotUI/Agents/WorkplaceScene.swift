import SwiftUI
import XBotCore

/// The Agents page's world, with this Mac's crew in it.
struct WorkplaceScene: View {
    let workspace: Workspace
    var edit: (Agent) -> Void = { _ in }

    static let height = WorldStage.height

    var body: some View {
        WorldStage(setting: workspace.workplace, residents: workspace.agents.map { workspace.resident($0) },
                   open: { workspace.openLatestChat(with: $0) },
                   newChat: { workspace.talk(to: $0) },
                   edit: { id in if let agent = workspace.agents.first(where: { $0.id == id }) { edit(agent) } })
    }
}
