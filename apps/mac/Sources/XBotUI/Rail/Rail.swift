import SwiftUI
import XBotCore

/// The 68pt vertical rail. Structural, so it takes the heaviest material.
public struct Rail: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        VStack(spacing: Space.s) {
            ForEach(state.agents) { agent in
                RailItem(
                    agent: agent,
                    isSelected: agent.id == state.selectedAgentID
                ) {
                    // Selection is applied on the intent, not after the conversation loads. The
                    // fill must never wait on a request.
                    state.select(agent.id)
                }
            }

            Button {
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(XBotButtonStyle())
            .accessibilityLabel(String(localized: "New agent"))

            Spacer()

            Image(systemName: "person.crop.circle")
                .font(.system(size: 22))
                .foregroundStyle(Palette.textSecondary)
                .padding(.bottom, Space.m)
                .accessibilityLabel(String(localized: "You"))
        }
        .padding(.top, Space.m)
        .frame(width: Metrics.railWidth)
        .frame(maxHeight: .infinity)
        .xbotMaterial(Materials.rail, opaqueFallback: Palette.railBackground)
        .motion(Motion.quick, value: state.selectedAgentID)
    }
}
