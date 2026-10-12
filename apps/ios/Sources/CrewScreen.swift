import SwiftUI
import XBotRemote

/// The crew, like the Mac's Agents page: who's here, what they're doing, and a way to talk to them.
struct CrewScreen: View {
    let client: RemoteClient
    @State private var members: [RemoteCrewMember]?
    @State private var parts: [RemoteAvatarPart] = []
    @State private var editing: RemoteCrewMember?
    @State private var talking: RemoteCrewMember?
    @State private var path: [Route] = []
    @State private var lastLetGo: String?

    enum Route: Hashable {
        case member(UUID)
        case chat(UUID, String)
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(members ?? []) { member in
                        NavigationLink(value: Route.member(member.id)) { CrewCard(member: member) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { talking = member } label: { Label(String(localized: "Message"), systemImage: "bubble.left") }
                                Button { editing = member } label: { Label(String(localized: "Edit"), systemImage: "pencil") }
                                if !member.isHeadMaster {
                                    Button(role: .destructive) { Task { await letGo(member) } } label: { Label(String(localized: "Let go"), systemImage: "person.badge.minus") }
                                }
                            }
                    }
                }
                .padding()
            }
            .overlay { if members == nil { ProgressView() } }
            .refreshable { await load() }
            .navigationTitle(String(localized: "Agents"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = newMember() } label: { Image(systemName: "person.badge.plus") }
                        .accessibilityLabel(String(localized: "Hire"))
                        .disabled(parts.isEmpty || client.agents.isEmpty)
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .member(let id):
                    if let member = members?.first(where: { $0.id == id }) {
                        CrewDetail(client: client, member: member, edit: { editing = member }, talk: { talking = member },
                                   letGo: { path.removeAll(); Task { await letGo(member) } })
                    }
                case .chat(let id, let name):
                    ChatScreen(client: client, chatID: id, fallbackTitle: name)
                }
            }
            .sheet(item: $editing) { member in
                CrewEditor(client: client, member: member, parts: parts, isNew: !(members ?? []).contains { $0.id == member.id }) { answer in
                    apply(answer)
                    editing = nil
                }
            }
            .sheet(item: $talking) { member in
                TalkSheet(client: client, member: member) { chatID in
                    talking = nil
                    path.append(.chat(chatID, member.name))
                }
                .presentationDetents([.medium])
            }
        }
        .overlay(alignment: .bottom) {
            if let lastLetGo {
                UndoBanner(text: String(localized: "\(lastLetGo) left")) { Task { await undo() } } dismiss: { self.lastLetGo = nil }
            }
        }
        .animation(.snappy, value: lastLetGo)
        .task { await load() }
        .task {
            // Who's working changes on the Mac: keep it fresh while on screen.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await load(quiet: true)
            }
        }
    }

    private func newMember() -> RemoteCrewMember {
        var look: [String: Int] = [:]
        for part in parts { look[part.key] = Int.random(in: 0..<max(part.count, 1)) }
        return RemoteCrewMember(name: "", avatar: RemoteAvatar(parts: look), agent: client.agents.first?.id ?? "claude")
    }

    private func apply(_ answer: HostMessage?) {
        guard case .crew(_, let list, let looks) = answer else { return }
        members = list
        parts = looks
    }

    private func load(quiet: Bool = false) async {
        let answer = await client.call(quiet: quiet) { .listCrew(requestID: $0) }
        if answer == nil, members == nil { members = [] }
        apply(answer)
    }

    private func letGo(_ member: RemoteCrewMember) async {
        let answer = await client.call { .deleteCrew(requestID: $0, memberID: member.id) }
        if answer != nil { lastLetGo = member.name }
        apply(answer)
    }

    private func undo() async {
        lastLetGo = nil
        apply(await client.call { .undoDeleteCrew(requestID: $0) })
    }
}

/// The sprite, crisp at any size.
struct Sprite: View {
    let image: Data?
    var height: CGFloat = 72

    var body: some View {
        if let image, let picture = UIImage(data: image) {
            Image(uiImage: picture).interpolation(.none).resizable().scaledToFit().frame(height: height)
        } else {
            Image(systemName: "person.fill").font(.system(size: height * 0.5)).foregroundStyle(.secondary).frame(height: height)
        }
    }
}

private struct CrewCard: View {
    let member: RemoteCrewMember

    var body: some View {
        VStack(spacing: 8) {
            Sprite(image: member.image, height: 76)
                .padding(.top, 14)
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(member.name).font(.headline).lineLimit(1)
                    if member.isHeadMaster { Image(systemName: "crown.fill").font(.caption2).foregroundStyle(.yellow) }
                }
                Text(member.role.isEmpty ? " " : member.role).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            CrewStatus(member: member).padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))
        .accessibilityElement(children: .combine)
    }
}

struct CrewStatus: View {
    let member: RemoteCrewMember

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 8)
    }

    private var color: Color {
        switch member.status { case "working": .orange; case "done": .green; default: Color(.systemGray3) }
    }

    private var text: String {
        switch member.status {
        case "working": member.activity.map { String(localized: "Working · \($0)") } ?? String(localized: "Working")
        case "done": String(localized: "Done")
        default: String(localized: "Free")
        }
    }
}

private struct CrewDetail: View {
    let client: RemoteClient
    let member: RemoteCrewMember
    let edit: () -> Void
    let talk: () -> Void
    let letGo: () -> Void
    @State private var confirming = false

    private var theirChats: [RemoteChat] { client.chats.filter { $0.crewName == member.name } }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Sprite(image: member.image, height: 140)
                    Text(member.role.isEmpty ? String(localized: "No role yet") : member.role).foregroundStyle(.secondary)
                    CrewStatus(member: member)
                    Button(action: talk) {
                        Label(String(localized: "Message \(member.name)"), systemImage: "bubble.left.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section(String(localized: "Works on")) {
                LabeledContent(String(localized: "Agent"), value: client.agent(member.agent)?.name ?? member.agent)
                LabeledContent(String(localized: "Home project"), value: client.project(member.projectID)?.name ?? String(localized: "None"))
            }
            if !member.instructions.isEmpty {
                Section(String(localized: "Instructions")) { Text(member.instructions).font(.callout) }
            }
            if !theirChats.isEmpty {
                Section(String(localized: "Chats")) {
                    ForEach(theirChats) { chat in
                        NavigationLink(value: CrewScreen.Route.chat(chat.id, chat.title)) {
                            VStack(alignment: .leading) {
                                Text(chat.title).lineLimit(1)
                                Text(chat.updatedAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !member.isHeadMaster {
                Section { Button(String(localized: "Let \(member.name) go"), role: .destructive) { confirming = true } }
            }
        }
        .navigationTitle(member.name)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "Edit"), action: edit) } }
        .confirmationDialog(String(localized: "Let \(member.name) go?"), isPresented: $confirming, titleVisibility: .visible) {
            Button(String(localized: "Let go"), role: .destructive, action: letGo)
        } message: { Text(String(localized: "Their chats stay. You can undo right after.")) }
    }
}

/// Hire or change someone: who they are, what they work on, and how they look.
private struct CrewEditor: View {
    let client: RemoteClient
    @State var member: RemoteCrewMember
    let parts: [RemoteAvatarPart]
    let isNew: Bool
    let done: (HostMessage?) -> Void
    @State private var preview: Data?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Sprite(image: preview ?? member.image, height: 120)
                        Spacer()
                    }
                    .overlay(alignment: .topTrailing) {
                        Button { shuffle() } label: { Image(systemName: "shuffle") }
                            .accessibilityLabel(String(localized: "Shuffle the look"))
                    }
                    ForEach(parts) { part in
                        Stepper(value: Binding(get: { member.avatar.parts[part.key] ?? 0 },
                                               set: { member.avatar.parts[part.key] = (($0 % part.count) + part.count) % part.count }),
                                in: -1...part.count) {
                            HStack {
                                Text(part.title)
                                Spacer()
                                Text("\((member.avatar.parts[part.key] ?? 0) + 1)/\(part.count)").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                } header: { Text(String(localized: "Look")) }
                Section(String(localized: "Who")) {
                    TextField(String(localized: "Name"), text: $member.name)
                    TextField(String(localized: "Role, like “Writer”"), text: $member.role)
                    TextField(String(localized: "Instructions"), text: $member.instructions, axis: .vertical).lineLimit(3...8)
                }
                Section(String(localized: "Works on")) {
                    Picker(String(localized: "Agent"), selection: $member.agent) {
                        ForEach(client.agents) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: member.agent) { member.model = nil }
                    if let agent = client.agent(member.agent), !agent.models.isEmpty {
                        Picker(String(localized: "Model"), selection: $member.model) {
                            Text(String(localized: "Default")).tag(String?.none)
                            ForEach(agent.models) { Text($0.name).tag(String?.some($0.id)) }
                        }
                    }
                    Picker(String(localized: "Home project"), selection: $member.projectID) {
                        Text(String(localized: "None")).tag(UUID?.none)
                        ForEach(client.projects) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
            }
            .navigationTitle(isNew ? String(localized: "Hire someone") : member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? String(localized: "Hire") : String(localized: "Save")) {
                        saving = true
                        Task {
                            let answer = await client.call { .saveCrew(requestID: $0, member: member) }
                            saving = false
                            if answer != nil { done(answer) }
                        }
                    }
                    .disabled(saving || member.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("save-crew")
                }
            }
            .task(id: member.avatar) {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                if case .avatarImage(_, let png) = await client.call(quiet: true, { .drawAvatar(requestID: $0, avatar: member.avatar) }) {
                    preview = png
                }
            }
        }
    }

    private func shuffle() {
        for part in parts { member.avatar.parts[part.key] = Int.random(in: 0..<max(part.count, 1)) }
    }
}

/// The first message to someone; opens the chat.
private struct TalkSheet: View {
    let client: RemoteClient
    let member: RemoteCrewMember
    let started: (UUID) -> Void
    @State private var text = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Sprite(image: member.image, height: 44)
                    VStack(alignment: .leading) {
                        Text(member.name).font(.headline)
                        Text(member.role).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                TextField(String(localized: "What should \(member.name) do?"), text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($focused)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    .accessibilityIdentifier("talk-text")
                Spacer()
            }
            .padding()
            .navigationTitle(String(localized: "New chat"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Send")) {
                        sending = true
                        Task {
                            let answer = await client.request { .talkTo(requestID: $0, memberID: member.id, text: text) }
                            sending = false
                            if answer.ok, let id = answer.chatID { started(id) } else { client.notice = answer.reason }
                        }
                    }
                    .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}
