import SwiftUI
import XBotEngine

/// One agent in the rail.
public struct RailItem: View {
    private let agent: Agent
    private let isSelected: Bool
    private let hasUnread: Bool
    private let activity: AgentAvatar.Activity
    private let action: () -> Void

    public init(
        agent: Agent,
        isSelected: Bool,
        hasUnread: Bool = false,
        activity: AgentAvatar.Activity = .idle,
        action: @escaping () -> Void
    ) {
        self.agent = agent
        self.isSelected = isSelected
        self.hasUnread = hasUnread
        self.activity = activity
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            AgentAvatar(agent: agent, size: .medium, activity: activity)
                .padding(Space.xs)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Radius.avatar + Space.xs, style: .continuous)
                            .fill(Palette.elevatedSurface)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if hasUnread && activity == .idle {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                            .offset(x: -1, y: 1)
                    }
                }
        }
        .buttonStyle(XBotButtonStyle())
        .help(agent.name)
        .accessibilityLabel(agent.name)
        .accessibilityValue(agent.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
