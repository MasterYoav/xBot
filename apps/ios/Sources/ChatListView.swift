import SwiftUI
import XBotRemote

/// Chats, as on the Mac's sidebar: Recent (no project) and each project.
struct ChatListView: View {
    let client: RemoteClient
    @Binding var selection: Destination?
    let showSettings: () -> Void
    let compose: (UUID?, String) -> Void
    let addProject: () -> Void
    @State private var query = ""
    @State private var renaming: RemoteChat?
    @State private var deleting: RemoteChat?

    private var shown: [RemoteChat] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? client.chats : client.chats.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List(selection: $selection) {
            if query.isEmpty {
                Section {
                    NavigationLink(value: Destination.notes) { Label(String(localized: "Notes"), systemImage: "note.text") }
                    NavigationLink(value: Destination.automations) { Label(String(localized: "Automations"), systemImage: "bolt.horizontal") }
                    NavigationLink(value: Destination.agents) { Label(String(localized: "Agents"), systemImage: "person.3") }
                }
            }
            let loose = shown.filter { $0.projectID == nil }
            if !loose.isEmpty {
                Section(String(localized: "Recent")) { ForEach(loose) { row($0) } }
            }
            ForEach(client.projects) { project in
                let theirs = shown.filter { $0.projectID == project.id }
                if !theirs.isEmpty || query.isEmpty {
                    Section(project.name) {
                        NavigationLink(value: Destination.project(project.id)) {
                            Label(String(localized: "Files and changes"), systemImage: "folder")
                                .foregroundStyle(Color.accentColor)
                        }
                        .accessibilityLabel(String(localized: "\(project.name): files and changes"))
                        ForEach(theirs) { row($0) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: String(localized: "Search chats"))
        .overlay {
            if client.chats.isEmpty {
                if client.link == .local || client.link == .cloud {
                    ContentUnavailableView(String(localized: "No chats yet"), systemImage: "bubble.left.and.bubble.right",
                                           description: Text(String(localized: "Start one with ✎.")))
                } else {
                    ContentUnavailableView {
                        Label(String(localized: "Connecting"), systemImage: "antenna.radiowaves.left.and.right")
                    } description: { LinkStatus(client: client) }
                }
            }
        }
        .navigationTitle(String(localized: "Chats"))
        .safeAreaInset(edge: .top, spacing: 0) {
            LinkStatus(client: client).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 6)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: showSettings) { Image(systemName: "gearshape") }.accessibilityLabel(String(localized: "Settings"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { compose(nil, "") } label: { Label(String(localized: "New chat"), systemImage: "square.and.pencil") }
                    Button(action: addProject) { Label(String(localized: "Add a project…"), systemImage: "folder.badge.plus") }
                } label: { Image(systemName: "square.and.pencil") } primaryAction: { compose(nil, "") }
                    .accessibilityLabel(String(localized: "New chat"))
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(client.agents.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let gone = client.lastDeleted {
                UndoBanner(text: String(localized: "Deleted “\(gone.title)”")) {
                    Task { await client.undoDelete() }
                } dismiss: { client.forgetDeleted() }
                .id(gone.id)
            }
        }
        .animation(.snappy, value: client.lastDeleted?.id)
        .renameAlert(chat: $renaming, client: client)
        .confirmationDialog(String(localized: "Delete “\(deleting?.title ?? "")”?"),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button(String(localized: "Delete"), role: .destructive) {
                if let chat = deleting { remove(chat) }
            }
        } message: {
            Text(String(localized: "It's deleted on your Mac too. You can undo right after."))
        }

    }

    private func row(_ chat: RemoteChat) -> some View {
        NavigationLink(value: Destination.chat(chat.id)) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.agentColor(chat.agent).opacity(0.15)).frame(width: 36, height: 36)
                    if chat.isRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(String((chat.crewName ?? chat.agentName).prefix(1))).font(.subheadline.bold())
                            .foregroundStyle(Theme.agentColor(chat.agent))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.title).font(.body.weight(.medium)).lineLimit(1)
                    Text(subtitle(chat)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(chat.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow)).font(.caption).foregroundStyle(.tertiary)
                    .lineLimit(1).fixedSize()
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { remove(chat) } label: { Label(String(localized: "Delete"), systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button { renaming = chat } label: { Label(String(localized: "Rename"), systemImage: "pencil") }.tint(.indigo)
        }
        .contextMenu {
            Button { renaming = chat } label: { Label(String(localized: "Rename"), systemImage: "pencil") }
            Button(role: .destructive) { deleting = chat } label: { Label(String(localized: "Delete"), systemImage: "trash") }
        }
        .accessibilityLabel("\(chat.title), \(subtitle(chat))\(chat.isRunning ? String(localized: ", working") : "")")
    }

    private func remove(_ chat: RemoteChat) {
        if selection == .chat(chat.id) { selection = nil }
        Task { await client.delete(chat.id) }
    }

    private func subtitle(_ chat: RemoteChat) -> String {
        if chat.isRunning { return String(localized: "\(chat.crewName ?? chat.agentName) is working…") }
        return chat.crewName.map { "\($0) · \(chat.agentName)" } ?? chat.agentName
    }
}

/// A new chat: where, which agent, and the first message.
struct NewChatSheet: View {
    let client: RemoteClient
    var initialProject: UUID?
    var initialText = ""
    let started: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var projectID: UUID?
    @State private var settings = ComposerSettings()
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Ask anything…"), text: $text, axis: .vertical)
                        .lineLimit(3...10)
                        .focused($focused)
                        .accessibilityIdentifier("new-chat-text")
                }
                Section {
                    Picker(String(localized: "Project"), selection: $projectID) {
                        Text(String(localized: "No project")).tag(UUID?.none)
                        ForEach(client.projects) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    ComposerSettingsRows(client: client, settings: $settings)
                }
            }
            .navigationTitle(String(localized: "New chat"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Send")) { Task { await start() } }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .onAppear {
                settings.agent = client.agents.first?.id
                projectID = initialProject
                if text.isEmpty { text = initialText }
                focused = true
            }
        }
    }

    private func start() async {
        sending = true
        defer { sending = false }
        if let id = await client.newChat(in: projectID, text: text, settings: settings.remote) { started(id) }
    }
}

/// "Deleted …  Undo" at the bottom, gone after a few seconds.
struct UndoBanner: View {
    let text: String
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash").foregroundStyle(.secondary)
            Text(text).font(.subheadline).lineLimit(1)
            Spacer(minLength: 8)
            Button(String(localized: "Undo"), action: undo).font(.subheadline.bold())
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 16).padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task {
            try? await Task.sleep(for: .seconds(6))
            dismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: String(localized: "Undo"), undo)
    }
}

extension View {
    /// The "Rename chat" alert with a text field.
    func renameAlert(chat: Binding<RemoteChat?>, client: RemoteClient) -> some View {
        modifier(RenameAlert(chat: chat, client: client))
    }
}

private struct RenameAlert: ViewModifier {
    @Binding var chat: RemoteChat?
    let client: RemoteClient
    @State private var title = ""

    func body(content: Content) -> some View {
        content
            .alert(String(localized: "Rename chat"), isPresented: Binding(get: { chat != nil }, set: { if !$0 { chat = nil } })) {
                TextField(String(localized: "Name"), text: $title)
                Button(String(localized: "Cancel"), role: .cancel) { chat = nil }
                Button(String(localized: "Rename")) {
                    if let id = chat?.id { let t = title; Task { await client.rename(id, to: t) } }
                    chat = nil
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .onChange(of: chat?.id) { title = chat?.title ?? "" }
    }
}
