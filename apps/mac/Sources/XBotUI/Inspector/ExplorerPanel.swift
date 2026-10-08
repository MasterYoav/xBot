import SwiftUI
import XBotCore

struct ExplorerPanel: View {
    let workspace: Workspace
    let project: Project
    let git: ProjectGit

    var body: some View {
        Text(project.name).frame(maxHeight: .infinity)
    }
}
