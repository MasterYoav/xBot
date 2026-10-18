import SwiftUI
import XBotRemote
import XBotWorld

/// Agentic Mode: no tabs and no Places, just a chat with each crew member, who do the work on the
/// Mac. Light by design: no world, no animation beyond the system's. See the Agentic Mode spec.
struct AgenticRoot: View {
    let client: RemoteClient
    /// Settings is shown by the root view, so it stays open when the mode changes.
    @Binding var settings: Bool
    @State private var path: [UUID] = []
    @State private var hiring = false

    var body: some View {
        NavigationStack(path: $path) {
            AgenticChatsView(client: client, open: { path.append($0) }, settings: { settings = true }, hire: { hiring = true })
                .navigationDestination(for: UUID.self) { memberID in
                    AgenticThreadView(client: client, memberID: memberID) { other in
                        // A hand-off card: their thread, on top of this one (back returns here).
                        if other != memberID { path.append(other) }
                    }
                }
        }
        .sheet(isPresented: $hiring) { HireSheet(client: client) }
        .alert(String(localized: "Your Mac said no"), isPresented: Binding(get: { client.notice != nil }, set: { (shown: Bool) in if !shown { client.notice = nil } })) {
            Button(String(localized: "OK")) { client.notice = nil }
        } message: {
            Text(client.notice ?? "")
        }
        #if DEBUG
        // Screenshots: `SIMCTL_CHILD_XBOT_AGENTIC_OPEN=HeadMaster` opens that member's thread.
        .task(id: client.world?.residents.count ?? 0) {
            guard path.isEmpty, let name = ProcessInfo.processInfo.environment["XBOT_AGENTIC_OPEN"],
                  let member = client.world?.residents.first(where: { $0.name == name }) else { return }
            path = [member.id]
        }
        #endif
    }
}

/// A crew member's face: their pixel head on their colour, in a circle. Still, never animated.
struct AgentFace: View {
    let avatar: AgentAvatar
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            Circle().fill(AvatarPalette.tile(avatar).gradient)
            AvatarSprite(avatar: avatar, frame: AvatarSprite.Frame(headOnly: true), pixel: size / 22)
                .offset(y: size * 0.06)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// Short, Messages-style times: 14:05 today, Yesterday, Tue, 12/10/26.
enum ChatTime {
    static func short(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}

/// Someone to hire: the suggested agents, one tap each.
struct HireSheet: View {
    let client: RemoteClient
    @State private var hiring: String?
    @Environment(\.dismiss) private var dismiss

    private var suggestions: [SuggestedAgent] {
        let names = Set((client.world?.residents ?? []).map { $0.name.lowercased() })
        return SuggestedAgent.all.filter { !names.contains($0.name.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(String(localized: "They join your crew on the Mac, each with their own chat here."))
                        .font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(suggestions) { suggestion in
                            SuggestionCard(suggestion: suggestion, hiring: hiring == suggestion.id) {
                                Task { await hire(suggestion) }
                            }
                            .disabled(client.agents.isEmpty || hiring != nil)
                        }
                    }
                }
                .padding(.horizontal, Glass.margin)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "Hire someone"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done")) { dismiss() } } }
            .task { await client.loadCrew() }
        }
    }

    private func hire(_ suggestion: SuggestedAgent) async {
        hiring = suggestion.id
        defer { hiring = nil }
        let agent = client.agents.first { $0.id == "claude" }?.id ?? client.agents.first?.id ?? "claude"
        var member = suggestion.member(agent: agent, parts: client.avatarParts)
        member.managerID = OrgChart.suggestedManager(role: member.role, id: member.id, among: (client.crew ?? []).map(\.orgMember))
        let hire = member
        client.applyCrew(await client.call { .saveCrew(requestID: $0, member: hire) })
    }
}
