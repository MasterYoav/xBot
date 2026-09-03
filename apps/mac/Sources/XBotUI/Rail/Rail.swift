import SwiftUI
import XBotCore

/// The 68pt vertical rail. Structural, so it takes the heaviest material.
public struct Rail: View {
    @Environment(AppState.self) private var state
    @Binding private var isPaletteOpen: Bool

    public init(isPaletteOpen: Binding<Bool>) {
        self._isPaletteOpen = isPaletteOpen
    }

    public var body: some View {
        VStack(spacing: Space.s) {
            ForEach(state.agents) { agent in
                RailItem(
                    agent: agent,
                    isSelected: agent.id == state.selectedAgentID,
                    activity: agent.id == state.workingAgentID ? .working : .idle
                ) {
                    // Selection is applied on the intent, not after the conversation loads. The
                    // fill must never wait on a request.
                    state.select(agent.id)
                }
            }

            Button {
                isPaletteOpen = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(XBotButtonStyle())
            .accessibilityLabel(String(localized: "New agent"))

            Spacer()

            // The way into settings, and the only one that does not need a keyboard. This was an
            // inert `person.crop.circle` — a control-shaped thing that did nothing, which is worse
            // than no control at all.
            Button {
                withAnimation(Motion.panel) { state.isShowingSettings.toggle() }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .symbolVariant(state.isShowingSettings ? .fill : .none)
                    .foregroundStyle(
                        state.isShowingSettings ? Palette.textPrimary : Palette.textSecondary
                    )
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(XBotButtonStyle())
            .padding(.bottom, Space.m)
            .accessibilityLabel(String(localized: "Settings"))
            .accessibilityAddTraits(state.isShowingSettings ? .isSelected : [])
        }
        .padding(.top, Space.m)
        .frame(width: Metrics.railWidth)
        .frame(maxHeight: .infinity)
        .frostedGlass(opaqueFallback: Palette.railBackground)
        .motion(Motion.quick, value: state.selectedAgentID)
    }
}
