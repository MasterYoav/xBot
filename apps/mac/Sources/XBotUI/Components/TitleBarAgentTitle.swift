import SwiftUI
import XBotCore
import XBotEngine

/// The unified title bar: current agent identity instead of the app name.
struct TitleBarAgentTitle: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: Space.s) {
            if let agent = state.selectedAgent {
                AgentAvatar(agent: agent, size: .small)
                Text(agent.name)
                    .bodyEmphasis()
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                Text(String(localized: "xBot"))
                    .bodyEmphasis()
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .background(.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(titleAccessibilityLabel)
    }

    private var titleAccessibilityLabel: String {
        if let agent = state.selectedAgent {
            return agent.name
        }
        return String(localized: "xBot")
    }
}
