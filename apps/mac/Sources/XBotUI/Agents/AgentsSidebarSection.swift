import SwiftUI
import XBotCore

/// The sidebar's crew: the member who matters most right now in a pill (alive: blinking,
/// breathing, a ring while working, what they're doing), over everyone else's faces.
struct AgentsSidebarSection: View {
    let workspace: Workspace
    @State private var hovered: UUID?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let crew = workspace.agents
            if let featured = featured(crew) {
                let status = workspace.status(of: featured.id)
                VStack(alignment: .leading, spacing: Space.s) {
                    header
                    Button { workspace.openLatestChat(with: featured.id) } label: {
                        HStack(spacing: Space.s) {
                            AgentFace(agent: featured, size: 34, status: status)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(featured.name).emphasisText().foregroundStyle(Palette.textPrimary).lineLimit(1)
                                Text(line(status, featured)).captionText()
                                    .foregroundStyle(status.isWorking ? Palette.accent : Palette.textTertiary)
                                    .lineLimit(1)
                                    .contentTransition(.opacity)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").imageScale(.small).foregroundStyle(Palette.textTertiary)
                        }
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, Space.xs + 1)
                        .background(Capsule().fill(Palette.hover))
                        .overlay(Capsule().strokeBorder(Palette.hairline))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(featured.role)
                    .accessibilityLabel("\(featured.name), \(line(status, featured))")
                    HStack(spacing: Space.xs) {
                        ForEach(crew.filter { $0.id != featured.id }) { agent in
                            Button { workspace.openLatestChat(with: agent.id) } label: {
                                AgentFace(agent: agent, size: 24, status: workspace.status(of: agent.id))
                                    .scaleEffect(hovered == agent.id ? 1.15 : 1)
                                    .animation(.spring(duration: 0.25, bounce: 0.5), value: hovered)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovered = $0 ? agent.id : nil }
                            .help("\(agent.name) — \(line(workspace.status(of: agent.id), agent))")
                        }
                        Button { workspace.showAgents() } label: {
                            Text(String(localized: "All")).captionText().foregroundStyle(Palette.textSecondary)
                                .padding(.horizontal, Space.xs)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, Space.xs)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button { workspace.showAgents() } label: {
                HStack(spacing: Space.xs) {
                    Text(String(localized: "Agents")).captionText()
                        .foregroundStyle(workspace.page == .agents ? Palette.textPrimary : Palette.textTertiary)
                    let busy = workspace.agents.filter { workspace.status(of: $0.id).isWorking }.count
                    if busy > 0 { MonoLabel(String(localized: "\(busy) working")) }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button { workspace.showAgents(hiring: true) } label: {
                Image(systemName: "plus").foregroundStyle(Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Hire an agent"))
        }
        .padding(.horizontal, Space.s)
        .padding(.top, Space.l)
    }

    /// Whoever's working, else whoever just finished, else the one in view, else HeadMaster.
    private func featured(_ crew: [Agent]) -> Agent? {
        let statuses = crew.map { ($0, workspace.status(of: $0.id)) }
        if let busy = statuses.first(where: { $0.1.isWorking }) { return busy.0 }
        if let done = statuses.first(where: { $0.1 == .done }) { return done.0 }
        if let inView = workspace.agent(workspace.selectedChatID.flatMap { workspace.chat($0)?.agentID }) { return inView }
        return crew.first(where: \.isHeadMaster) ?? crew.first
    }

    private func line(_ status: AgentStatus, _ agent: Agent) -> String {
        switch status {
        case .working(let activity, _): activity ?? String(localized: "Working…")
        case .done: String(localized: "Done — tap to read")
        case .idle: agent.role
        }
    }
}
