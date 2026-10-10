import SwiftUI
import XBotCore

/// The window: the sidebar, a top bar of open chats, and Home or a chat.
public struct RootView: View {
    @Bindable private var workspace: Workspace
    @State private var addingProject = false
    @State private var columns: NavigationSplitViewVisibility = .all
    @AppStorage("inspectorShown") private var inspectorShown = false
    @AppStorage("inspectorWidth") private var inspectorWidth = Double(Metrics.inspectorIdealWidth)
    @State private var dragStartWidth: Double?
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
            // The files-and-changes column is drawn here, beside the content, rather than with
            // SwiftUI's .inspector: under this window's hidden title bar, the inspector's own split
            // view went into an endless layout pass (an AppKit exception) when it opened or when the
            // sidebar moved while it was open.
            HStack(spacing: 0) {
                ZStack(alignment: .top) {
                    Backdrop(workspace.isHome && workspace.page == .main ? .home : .chat)
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
                            case .agents:
                                AgentsView(workspace: workspace)
                            case .abilities:
                                AbilitiesView(workspace: workspace)
                            case .notes:
                                NotesView(workspace: workspace, addProject: { addingProject = true })
                            case .main:
                                if let id = workspace.selectedChatID, let chat = workspace.chat(id) {
                                    ChatView(workspace: workspace, chat: chat, composer: composer).id(chat.id)
                                        .overlay {
                                            if workspace.terminals.isShown(chat.id) {
                                                TerminalLayer(workspace: workspace, chatID: chat.id).id(chat.id)
                                            }
                                        }
                                        .overlay(alignment: .bottomTrailing) {
                                            TerminalToggle(workspace: workspace, chatID: chat.id)
                                                .padding(Space.l)
                                        }
                                } else {
                                    HomeView(workspace: workspace, composer: composer, addProject: { addingProject = true })
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .belowTitleBar()
                    }
                }
                if showsInspector, let project = workspace.contextProject {
                    inspectorHandle
                    InspectorView(workspace: workspace, project: project)
                        .frame(width: inspectorWidth)
                        .transition(.move(edge: .trailing))
                }
            }
            .background(Palette.window)
            .ignoresSafeArea(.container, edges: .top)
            .animation(Motion.panel, value: showsInspector)
        }
        .overlay(alignment: .bottom) { ToastHost(center: workspace.toasts) }
        .fileImporter(isPresented: $addingProject, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                let project = workspace.addProject(at: url)
                workspace.startDraft(in: project.id)
            }
        }
        .task { await workspace.refreshHarnesses() }
        .onAppear {
            // The deck decides when a shell ends; a shell that exits on its own closes its window.
            let deck = workspace.terminals
            deck.onEnd = { TerminalShells.shared.end($0) }
            TerminalShells.shared.closeWindow = { deck.close($0) }
        }
        // The profile's history: read at launch, then every hour.
        .task {
            while !Task.isCancelled {
                await workspace.indexHistory()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    private var showsInspector: Bool { inspectorShown && workspace.contextProject != nil }

    /// The hairline between the content and the column; drag it to resize the column.
    private var inspectorHandle: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: Space.s)
                    .contentShape(Rectangle())
                    .pointerStyle(.columnResize)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let start = dragStartWidth ?? inspectorWidth
                                dragStartWidth = start
                                inspectorWidth = min(max(start - value.translation.width, Metrics.inspectorWidth.lowerBound),
                                                     Metrics.inspectorWidth.upperBound)
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
            }
    }
}
