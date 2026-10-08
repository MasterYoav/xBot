import SwiftUI
import XBotCore

/// Search, Home and Inbox, projects with their chats, Recent, and the agents found.
struct Sidebar: View {
    let workspace: Workspace
    let addProject: () -> Void
    let hide: () -> Void
    @State private var query = ""
    @State private var expanded: Set<UUID> = []
    @State private var collapsed: Set<UUID> = []
    @State private var inboxOpen = true
    @State private var renaming: UUID?
    @State private var renameText = ""
    @FocusState private var searchFocused: Bool

    private var model: SidebarModel {
        SidebarModel(projects: workspace.projects, chats: workspace.chats, running: workspace.runningChatIDs,
                     query: query, expanded: expanded)
    }

    var body: some View {
        let model = model
        VStack(alignment: .leading, spacing: Space.s) {
            titleRow
            search
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    Button { workspace.goHome() } label: {
                        SidebarRow(String(localized: "Home"), systemImage: "house", isSelected: workspace.isHome)
                    }
                    .buttonStyle(.plain)
                    Button { inboxOpen.toggle() } label: {
                        SidebarRow(String(localized: "Inbox"), systemImage: "tray") {
                            if !model.inbox.isEmpty { MonoLabel("\(model.inbox.count)") }
                        }
                    }
                    .buttonStyle(.plain)
                    if inboxOpen || !query.isEmpty {
                        ForEach(model.inbox.prefix(SidebarModel.chatsPerProject)) { chatRow($0) }
                    }

                    sectionHeader(String(localized: "Projects"), add: addProject)
                    if model.groups.isEmpty && query.isEmpty {
                        Button(action: addProject) {
                            SidebarRow(String(localized: "Add a folder"), systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(model.groups) { group in projectSection(group) }

                    if !model.recent.isEmpty {
                        sectionHeader(String(localized: "Recent"), add: nil)
                        ForEach(model.recent) { chatRow($0, indent: false) }
                    }
                }
                .padding(.horizontal, Space.s)
            }
            .scrollIndicators(.never)
            footer
        }
        .background(Palette.sidebar)
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: workspace.searchFocusRequest) { searchFocused = true }
    }

    /// The title bar row: the traffic lights sit at its left; hide-sidebar and new-chat at its
    /// right. The empty part moves the window, as a title bar would.
    private var titleRow: some View {
        HStack(spacing: Space.xxs) {
            Spacer()
            IconButton("sidebar.left", help: String(localized: "Hide sidebar (⌃⌘S)"), action: hide)
            IconButton("square.and.pencil", help: String(localized: "New chat (⌘N)")) { workspace.startDraft(in: nil) }
        }
        .padding(.leading, Metrics.trafficLights)
        .padding(.trailing, Space.s)
        .frame(height: Metrics.titleBar)
        .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
    }

    private var search: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.textTertiary)
            TextField(String(localized: "Search"), text: $query)
                .textFieldStyle(.plain)
                .bodyText()
                .focused($searchFocused)
                .onExitCommand { query = ""; searchFocused = false }
            if query.isEmpty { MonoLabel("⌘K") }
        }
        .padding(.horizontal, Space.s)
        .frame(height: Metrics.row + Space.xs)
        .background(Palette.hover, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
        .padding(.horizontal, Space.s)
    }

    private func sectionHeader(_ title: String, add: (() -> Void)?) -> some View {
        HStack {
            Text(title).captionText().foregroundStyle(Palette.textTertiary)
            Spacer()
            if let add {
                Button(action: add) { Image(systemName: "plus").foregroundStyle(Palette.textTertiary) }
                    .buttonStyle(.plain)
                    .help(String(localized: "Add a folder"))
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.top, Space.l)
        .padding(.bottom, Space.xs)
    }

    @ViewBuilder
    private func projectSection(_ group: SidebarModel.Group) -> some View {
        let open = !collapsed.contains(group.id) || !query.isEmpty
        Button {
            if collapsed.contains(group.id) { collapsed.remove(group.id) } else { collapsed.insert(group.id) }
        } label: {
            SidebarRow(group.project.name, systemImage: open ? "folder" : "folder.fill") {
                if group.isRunning { Circle().fill(Palette.running).frame(width: Metrics.dot, height: Metrics.dot) }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(String(localized: "New Chat")) { workspace.startDraft(in: group.id) }
            Button(String(localized: "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([group.project.url]) }
            Divider()
            Button(String(localized: "Remove from xBot")) { workspace.removeProject(group.id) }
        }
        if open {
            ForEach(group.chats) { chatRow($0) }
            if group.hidden > 0 {
                Button { expanded.insert(group.id) } label: {
                    Text(String(localized: "Show all \(group.chats.count + group.hidden)"))
                        .captionText()
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: Metrics.row, alignment: .leading)
                        .padding(.leading, Space.l + Space.s * 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func chatRow(_ chat: Chat, indent: Bool = true) -> some View {
        Group {
            if renaming == chat.id {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .bodyText()
                    .padding(.horizontal, Space.s)
                    .frame(height: Metrics.row)
                    .raisedSurface(radius: Radius.small)
                    .onSubmit { workspace.rename(chat.id, to: renameText); renaming = nil }
                    .onExitCommand { renaming = nil }
            } else {
                Button { workspace.open(chat.id) } label: {
                    SidebarRow(chat.title, isSelected: workspace.selectedChatID == chat.id) {
                        if workspace.isRunning(chat.id) { ProgressView().controlSize(.mini) }
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(String(localized: "Rename")) { renameText = chat.title; renaming = chat.id }
                    Button(String(localized: "Delete Chat"), role: .destructive) { workspace.deleteChatWithUndo(chat.id) }
                }
            }
        }
        .padding(.leading, indent ? Space.l + Space.s : 0)
    }

    private var footer: some View {
        HStack(spacing: Space.m) {
            if workspace.availableHarnesses.isEmpty {
                if workspace.isDiscovering {
                    ProgressView().controlSize(.mini)
                    Text(String(localized: "Looking for agents…")).captionText().foregroundStyle(Palette.textTertiary)
                } else {
                    Text(String(localized: "No agent found")).captionText().foregroundStyle(Palette.textTertiary)
                    Button(String(localized: "Look again")) { Task { await workspace.refreshHarnesses() } }
                        .buttonStyle(.link)
                        .captionText()
                }
            } else {
                ForEach(workspace.availableHarnesses, id: \.self) { kind in
                    HStack(spacing: Space.xs) {
                        Circle().fill(Palette.agent(kind)).frame(width: Metrics.dot, height: Metrics.dot)
                        Text(kind.displayName).captionText().foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}
