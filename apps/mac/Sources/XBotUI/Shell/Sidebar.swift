import SwiftUI
import XBotCore

struct Sidebar: View {
    let workspace: Workspace
    let addProject: () -> Void
    @State private var pendingDelete: Chat?

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(chats(in: nil)) { row($0) }
            } header: {
                header(String(localized: "Inbox"), systemImage: "tray", project: nil)
            }
            ForEach(workspace.projects) { project in
                Section {
                    ForEach(chats(in: project.id)) { row($0) }
                } header: {
                    header(project.name, systemImage: "folder", project: project.id)
                        .contextMenu {
                            Button(String(localized: "Show in Finder")) {
                                NSWorkspace.shared.activateFileViewerSelecting([project.url])
                            }
                            Button(String(localized: "Remove from xBot")) { workspace.removeProject(project.id) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button(action: addProject) {
                    Label(String(localized: "Add Project"), systemImage: "folder.badge.plus")
                }
                .help(String(localized: "Add a folder to work in"))
            }
        }
        .confirmationDialog(
            String(localized: "Delete this chat?"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { chat in
            Button(String(localized: "Delete Chat"), role: .destructive) { workspace.deleteChat(chat.id) }
        } message: { _ in
            Text(String(localized: "The conversation is removed from xBot. Files the agent changed stay as they are."))
        }
    }

    private var selection: Binding<UUID?> {
        Binding(get: { workspace.selectedChatID }, set: { if let id = $0 { workspace.open(id) } })
    }

    private func chats(in project: UUID?) -> [Chat] {
        workspace.chats.filter { $0.projectID == project }
    }

    private func header(_ title: String, systemImage: String, project: UUID?) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Button { workspace.newChat(in: project) } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.borderless)
                .help(String(localized: "New chat"))
                .disabled(workspace.availableHarnesses.isEmpty)
        }
    }

    private func row(_ chat: Chat) -> some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(chat.title).bodyText().lineLimit(1)
                Text(chat.harness.displayName).captionText().foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            if workspace.isRunning(chat.id) {
                ProgressView().controlSize(.small)
            } else {
                Text(chat.updatedAt, format: .relative(presentation: .named, unitsStyle: .narrow))
                    .captionText()
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .tag(chat.id)
        .contextMenu {
            Button(String(localized: "Delete Chat…"), role: .destructive) { pendingDelete = chat }
        }
    }
}
