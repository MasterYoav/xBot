import SwiftUI
import XBotCore

/// The window: the sidebar, a top bar of open chats, and Home or a chat.
public struct RootView: View {
    @Bindable private var workspace: Workspace
    @State private var addingProject = false
    @Namespace private var composer

    public init(workspace: Workspace) { self.workspace = workspace }

    public var body: some View {
        NavigationSplitView {
            Sidebar(workspace: workspace, addProject: { addingProject = true })
                .navigationSplitViewColumnWidth(
                    min: Metrics.sidebarWidth.lowerBound, ideal: Metrics.sidebarIdealWidth,
                    max: Metrics.sidebarWidth.upperBound
                )
                .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                TopBar(workspace: workspace)
                if let problem = workspace.problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .captionText()
                        .foregroundStyle(Palette.failure)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, Space.s)
                        .background(Palette.failureTint)
                }
                ZStack {
                    if let id = workspace.selectedChatID, let chat = workspace.chat(id) {
                        ChatView(workspace: workspace, chat: chat, composer: composer).id(chat.id)
                    } else {
                        HomeView(workspace: workspace, composer: composer, addProject: { addingProject = true })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Palette.window)
            .toolbar(.hidden, for: .windowToolbar)
        }
        .overlay(alignment: .bottom) { ToastHost(center: workspace.toasts) }
        .fileImporter(isPresented: $addingProject, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                let project = workspace.addProject(at: url)
                workspace.startDraft(in: project.id)
            }
        }
        .task { await workspace.refreshHarnesses() }
    }
}
