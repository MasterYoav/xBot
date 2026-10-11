import SwiftUI
import XBotCore

/// A small window into the crew's world. Every animated face shares one row;
/// the scenery opens the world, faces open chats, and + opens the hiring flow.
struct AgentsSidebarSection: View {
    let workspace: Workspace
    @State private var hovered: UUID?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !MotionGate.shared.isLive)) { _ in
            let crew = workspace.agents
            if !crew.isEmpty {
                VStack(alignment: .leading, spacing: Space.s) {
                    header
                    HStack(spacing: Space.xs) {
                        ForEach(crew) { agent in
                            Button { workspace.openLatestChat(with: agent.id) } label: {
                                AgentFace(agent: agent, size: 24, status: workspace.status(of: agent.id))
                                    .scaleEffect(hovered == agent.id ? 1.15 : 1)
                                    .motion(Motion.quick, value: hovered)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovered = $0 ? agent.id : nil }
                            .help("\(agent.name) — \(line(workspace.status(of: agent.id), agent))")
                            .accessibilityLabel(String(localized: "Open chat with \(agent.name)"))
                        }
                        Button { workspace.showAgents(hiring: true) } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.white)
                                .frame(width: Space.l + Space.xs, height: Space.xl)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Hire an agent"))
                        .accessibilityLabel(String(localized: "Hire an agent"))
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, Space.xxs)
                }
                .padding(.horizontal, Space.s)
                .padding(.top, Space.l)
                .padding(.bottom, Space.s)
                // A sibling underlay, not a parent tap gesture: face/+ actions
                // cannot bubble into world navigation or become nested buttons.
                .background {
                    Button { workspace.showAgents() } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Open agent world"))
                    .help(workspace.workplace.title)
                }
                .background { SidebarWorldBackdrop(setting: workspace.workplace) }
                .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1).allowsHitTesting(false) }
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1).allowsHitTesting(false) }
                // Sidebar's list has an inset; this world alone reaches its edges.
                .padding(.horizontal, -Space.s)
            }
        }
    }

    private var header: some View {
        HStack(spacing: Space.xs) {
            Text(String(localized: "Agents")).captionText().foregroundStyle(.white)
            let busy = workspace.agents.filter { workspace.status(of: $0.id).isWorking }.count
            if busy > 0 {
                Text(String(localized: "\(busy) working")).font(Typography.mono).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s)
        .allowsHitTesting(false)
    }

    private func line(_ status: AgentStatus, _ agent: Agent) -> String {
        switch status {
        case .working(let activity, _): activity ?? String(localized: "Working…")
        case .done: String(localized: "Done — tap to read")
        case .idle: agent.role
        }
    }
}

/// Render the same art as the full world at miniature scale rather than inventing
/// a second theme for the sidebar. The animated agent faces stay unscaled above it.
private struct SidebarWorldBackdrop: View {
    let setting: WorkplaceSetting
    @State private var stillDate = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let scale = max(0.01, geometry.size.height / WorkplaceScene.height)
            let artWidth = geometry.size.width / scale
            TimelineView(.animation(minimumInterval: 0.1, paused: reduceMotion || !MotionGate.shared.isLive)) { clock in
                WorldScenery(setting: setting, date: reduceMotion ? stillDate : clock.date, width: artWidth)
                    .frame(width: artWidth, height: WorkplaceScene.height)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .clipped()
                    .overlay(.black.opacity(0.3))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
