import SwiftUI
import XBotCore
import XBotWorld

/// Step 10: the world the crew lives in (the Agents page's own setting) and the theme (Settings ›
/// Appearance's).
struct WorldsStepView: View {
    let workspace: Workspace

    var body: some View {
        StepPage(copy: .of(.worlds)) {
            WorldsScene()
        } controls: {
            VStack(alignment: .leading, spacing: Space.m) {
                Text(String(localized: "World")).labelText().foregroundStyle(Palette.textTertiary)
                // Two columns: three would cut "Underwater Kingdom" short in the controls' width.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 2),
                          alignment: .leading, spacing: Space.s) {
                    ForEach(WorkplaceSetting.allCases, id: \.self) { world in worldChoice(world) }
                }
                Text(String(localized: "Appearance")).labelText().foregroundStyle(Palette.textTertiary)
                    .padding(.top, Space.xs)
                Picker(String(localized: "Appearance"), selection: Binding(
                    get: { Appearance.shared.theme },
                    set: { (theme: Appearance.Theme) in Appearance.shared.theme = theme }
                )) {
                    ForEach(Appearance.Theme.allCases, id: \.self) { theme in Text(theme.title).tag(theme) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private func worldChoice(_ world: WorkplaceSetting) -> some View {
        let chosen = workspace.workplace == world
        return Button {
            withAnimation(Motion.standard) { workspace.workplace = world }
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: world.symbol).frame(width: Space.l)
                Text(world.title).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .font(Typography.chip)
            .foregroundStyle(chosen ? Palette.accent : Palette.textSecondary)
            .padding(.horizontal, Space.s)
            .frame(height: Metrics.row + Space.xs)
            .background(chosen ? Palette.accentTint : Palette.raised,
                        in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .strokeBorder(chosen ? Palette.accent.opacity(0.5) : Palette.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(XBotButtonStyle())
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
