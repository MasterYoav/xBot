import SwiftUI
import XBotCore

/// Recurring scheduled tasks. Empty for now — the engine has them; the app has not surfaced them.
public struct RoutinesSection: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        PanelSectionBody(String(localized: "Routines")) {
            Text(String(localized: "Routines are recurring tasks this agent runs on a schedule."))
                .bodyText()
                .foregroundStyle(Palette.textSecondary)

            Button {
            } label: {
                Text(String(localized: "Create Routine"))
                    .bodyEmphasis()
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .background(
                        Palette.elevatedSurface,
                        in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    )
            }
            .buttonStyle(XBotButtonStyle())
        }
    }
}
