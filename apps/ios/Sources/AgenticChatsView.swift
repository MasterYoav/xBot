import SwiftUI
import XBotRemote
import XBotWorld

/// Agentic Mode's only root screen, like Telegram's chat list: the Mac and how it's reached on
/// top, HeadMaster pinned first ("Ask me anything"), then everyone on the crew, most recent first.
struct AgenticChatsView: View {
    let client: RemoteClient
    let open: (UUID) -> Void
    let settings: () -> Void
    let hire: () -> Void
    @State private var query = ""

    struct Row: Identifiable {
        let id: UUID
        let name: String
        let role: String
        let avatar: AgentAvatar
        let isHeadMaster: Bool
        let thread: RemoteChat?
    }

    private var rows: [Row] {
        let threads = client.threads
        var rows: [Row] = (client.world?.residents ?? []).map {
            Row(id: $0.id, name: $0.name, role: $0.role, avatar: $0.avatar.look, isHeadMaster: $0.isHeadMaster, thread: threads[$0.id])
        }
        // Not connected yet: the threads the cache knows, without faces.
        if rows.isEmpty {
            rows = threads.map { id, chat in Row(id: id, name: chat.crewName ?? chat.title, role: "", avatar: AgentAvatar(),
                                                 isHeadMaster: false, thread: chat) }
        }
        rows.sort { a, b in
            if a.isHeadMaster != b.isHeadMaster { return a.isHeadMaster }
            return (a.thread?.updatedAt ?? .distantPast) > (b.thread?.updatedAt ?? .distantPast)
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return rows }
        return rows.filter { row in
            [row.name, row.role, row.thread?.preview ?? ""].contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        List {
            ForEach(rows) { row in
                Button { open(row.id) } label: { AgenticChatRow(client: client, row: row) }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: Glass.margin, bottom: 8, trailing: Glass.margin))
                    .listRowSeparatorTint(Color(.separator).opacity(0.5))
                    .listRowSeparator(row.id == rows.first?.id ? .hidden : .automatic, edges: .top)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 66 }
                    .accessibilityIdentifier("thread-\(row.name)")
            }
            if rows.isEmpty, query.isEmpty {
                ContentUnavailableView(String(localized: "Looking for your crew"), systemImage: "person.3",
                                       description: Text(String(localized: "They appear once xBot on your Mac answers.")))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: String(localized: "Search"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: settings) { Image(systemName: "gearshape") }
                    .accessibilityLabel(String(localized: "Settings"))
            }
            ToolbarItem(placement: .principal) { MacHeader(client: client) }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: hire) { Image(systemName: "person.badge.plus") }
                    .accessibilityLabel(String(localized: "Hire someone"))
            }
        }
    }
}

/// The Mac's name over a dot and how it's reached.
private struct MacHeader: View {
    let client: RemoteClient

    var body: some View {
        VStack(spacing: 1) {
            Text(client.macName ?? String(localized: "Your Mac")).font(.headline).lineLimit(1)
            HStack(spacing: 5) {
                Circle().fill(LinkStatus.color(client)).frame(width: 7, height: 7)
                Text(lane).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LinkStatus.text(client))
        .accessibilityIdentifier("link-status")
    }

    private var lane: String {
        switch client.link {
        case .local: String(localized: "same Wi-Fi")
        case .cloud: String(localized: "through iCloud")
        case .searching: String(localized: "connecting…")
        case .unpaired, .unreachable: String(localized: "offline")
        }
    }
}

private struct AgenticChatRow: View {
    let client: RemoteClient
    let row: AgenticChatsView.Row

    private var running: Bool { row.thread?.isRunning == true }
    private var unread: Bool { row.thread.map(client.isUnread) ?? false }

    var body: some View {
        HStack(spacing: 12) {
            AgentFace(avatar: row.avatar, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(row.name).font(.body.weight(.semibold)).lineLimit(1)
                    if row.isHeadMaster { Image(systemName: "crown.fill").font(.caption2).foregroundStyle(.yellow) }
                    Spacer(minLength: 6)
                    if let thread = row.thread {
                        Text(ChatTime.short(thread.updatedAt)).font(.subheadline)
                            .foregroundStyle(unread ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    }
                }
                HStack(alignment: .top, spacing: 6) {
                    Group {
                        if running {
                            Text(String(localized: "typing…")).foregroundStyle(Theme.accent)
                        } else {
                            Text(preview).foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if unread {
                        Circle().fill(Theme.accent).frame(width: 11, height: 11).padding(.top, 4)
                            .accessibilityLabel(String(localized: "Unread"))
                    } else if row.isHeadMaster {
                        Image(systemName: "pin.fill").font(.caption).foregroundStyle(.tertiary).rotationEffect(.degrees(45)).padding(.top, 3)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var preview: String {
        if let text = row.thread?.preview { return text }
        if row.isHeadMaster { return String(localized: "Ask me anything") }
        return row.role.isEmpty ? String(localized: "Say hello") : row.role
    }
}
