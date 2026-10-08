import SwiftUI
import XBotCore

/// The window: the sidebar, a top bar of open chats, and Home or a chat.
public struct RootView: View {
    @Bindable private var workspace: Workspace
    @State private var addingProject = false
    @State private var columns: NavigationSplitViewVisibility = .all
    @AppStorage("inspectorShown") private var inspectorShown = false
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
            ZStack(alignment: .top) {
                Backdrop(workspace.isHome ? .home : .chat)
                VStack(spacing: 0) {
                    TopBar(workspace: workspace, sidebarVisible: columns != .detailOnly,
                           showSidebar: { withAnimation(Motion.panel) { columns = .all } },
                           inspectorShown: $inspectorShown, inspectorAvailable: workspace.contextProject != nil)
                    if let problem = workspace.problem {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .captionText()
                            .foregroundStyle(Palette.failure)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Space.m)
                            .padding(.vertical, Space.s)
                            .background(Palette.failureTint)
                    }
                    Group {
                        switch workspace.page {
                        case .diff(let projectID, let file):
                            if let project = workspace.projects.first(where: { $0.id == projectID }),
                               let git = workspace.git(for: project) {
                                DiffView(workspace: workspace, git: git, file: file)
                            }
                        case .profile:
                            ProfileView(workspace: workspace)
                        case .main:
                            if let id = workspace.selectedChatID, let chat = workspace.chat(id) {
                                ChatView(workspace: workspace, chat: chat, composer: composer).id(chat.id)
                            } else {
                                HomeView(workspace: workspace, composer: composer, addProject: { addingProject = true })
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Palette.window)
            .ignoresSafeArea(.container, edges: .top)
            .inspector(isPresented: Binding(
                get: { inspectorShown && workspace.contextProject != nil },
                set: { inspectorShown = $0 }
            )) {
                if let project = workspace.contextProject {
                    InspectorView(workspace: workspace, project: project)
                        .inspectorColumnWidth(
                            min: Metrics.inspectorWidth.lowerBound, ideal: Metrics.inspectorIdealWidth,
                            max: Metrics.inspectorWidth.upperBound
                        )
                }
            }
        }
        .overlay(alignment: .bottom) { ToastHost(center: workspace.toasts) }
        .fileImporter(isPresented: $addingProject, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                let project = workspace.addProject(at: url)
                workspace.startDraft(in: project.id)
            }
        }
        .task { await workspace.refreshHarnesses() }
        // The profile's history: read at launch, then every hour.
        .task {
            while !Task.isCancelled {
                await workspace.indexHistory()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }
}
