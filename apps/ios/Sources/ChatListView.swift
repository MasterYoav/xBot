import SwiftUI
import XBotRemote

/// Chats, as on the Mac's sidebar: Recent (no project) and each project.
struct ChatListView: View {
    let client: RemoteClient
    @Binding var selection: UUID?
    let showSettings: () -> Void
    @State private var composing = false
    @State private var query = ""

    private var shown: [RemoteChat] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? client.chats : client.chats.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List(selection: $selection) {
            let loose = shown.filter { $0.projectID == nil }
            if !loose.isEmpty {
                Section(String(localized: "Recent")) { ForEach(loose) { row($0) } }
            }
            ForEach(client.projects) { project in
                let theirs = shown.filter { $0.projectID == project.id }
                if !theirs.isEmpty {
                    Section(project.name) { ForEach(theirs) { row($0) } }
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
                Button { composing = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel(String(localized: "New chat"))
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(client.agents.isEmpty)
            }
        }
        .sheet(isPresented: $composing) {
            NewChatSheet(client: client) { id in
                composing = false
                selection = id
            }
        }
    }

    private func row(_ chat: RemoteChat) -> some View {
        NavigationLink(value: chat.id) {
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
        .accessibilityLabel("\(chat.title), \(subtitle(chat))\(chat.isRunning ? String(localized: ", working") : "")")
    }

    private func subtitle(_ chat: RemoteChat) -> String {
        if chat.isRunning { return String(localized: "\(chat.crewName ?? chat.agentName) is working…") }
        return chat.crewName.map { "\($0) · \(chat.agentName)" } ?? chat.agentName
    }
}

/// A new chat: where, which agent, and the first message.
struct NewChatSheet: View {
    let client: RemoteClient
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
