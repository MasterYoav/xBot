import SwiftUI
import XBotCore

/// The window: projects and chats on the left, the open chats on the right.
public struct RootView: View {
    @Bindable private var workspace: Workspace
    @State private var addingProject = false

    public init(workspace: Workspace) { self.workspace = workspace }

    public var body: some View {
        NavigationSplitView {
            Sidebar(workspace: workspace, addProject: { addingProject = true })
                .navigationSplitViewColumnWidth(
                    min: Metrics.sidebarWidth.lowerBound,
                    ideal: Metrics.sidebarIdealWidth,
                    max: Metrics.sidebarWidth.upperBound
                )
        } detail: {
            VStack(spacing: 0) {
                if let problem = workspace.problem {
                    Text(problem)
                        .captionText()
                        .foregroundStyle(Palette.stateFailed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.s)
                        .background(Palette.panelBackground)
                }
                if let id = workspace.selectedChatID, let chat = workspace.chat(id) {
                    ChatTabs(workspace: workspace)
                    ChatView(workspace: workspace, chat: chat).id(chat.id)
                } else {
                    EmptyState(workspace: workspace, addProject: { addingProject = true })
                }
            }
            .background(Palette.windowBackground)
        }
        .fileImporter(isPresented: $addingProject, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                let project = workspace.addProject(at: url)
                workspace.newChat(in: project.id)
            }
        }
        .task { await workspace.refreshHarnesses() }
    }
}
