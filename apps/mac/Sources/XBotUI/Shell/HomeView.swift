import SwiftUI
import XBotCore

struct HomeView: View {
    let workspace: Workspace
    let composer: Namespace.ID
    let addProject: () -> Void

    var body: some View { EmptyState(workspace: workspace, addProject: addProject) }
}
