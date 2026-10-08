import SwiftUI
import XBotCore

/// The window: the sidebar, a top bar of open chats, and Home or a chat.
public struct RootView: View {
    @Bindable private var workspace: Workspace
    @State private var addingProject = false
    @State private var columns: NavigationSplitViewVisibility = .all
    @Namespace private var composer

    public init(workspace: Workspace) { self.workspace = workspace }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar(workspace: workspace, addProject: { addingProject = true },
                    hide: { withAnimation(Motion.panel) { columns = .detailOnly } })
                .navigationSplitViewColumnWidth(
                    min: Metrics.sidebarWidth.lowerBound, ideal: Metrics.sidebarIdealWidth,
                    max: Metrics.sidebarWidth.upperBound
                )
                .toolbar(removing: .sidebarToggle)
                .toolbar(removing: .title)
        } detail: {
            VStack(spacing: 0) {
                TopBar(workspace: workspace, sidebarVisible: columns != .detailOnly,
                       showSidebar: { withAnimation(Motion.panel) { columns = .all } })
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
                    Backdrop(workspace.isHome ? .home : .chat)
                    if let id = workspace.selectedChatID, let chat = workspace.chat(id) {
                        ChatView(workspace: workspace, chat: chat, composer: composer).id(chat.id)
                    } else {
                        HomeView(workspace: workspace, composer: composer, addProject: { addingProject = true })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Palette.window)
            .ignoresSafeArea(.container, edges: .top)
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
