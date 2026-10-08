import SwiftUI
import XBotCore

/// The right-hand column for the project in view: its files, and its git changes.
struct InspectorView: View {
    let workspace: Workspace
    let project: Project

    var body: some View {
        Text(project.name)
    }
}
