import SwiftUI
import XBotCore

/// How this agent reaches the engine — built-in for every xBot agent in v1.
public struct AgentConnectionSection: View {
    @State private var isExpanded = false

    public init() {}

    public var body: some View {
        CollapsibleSettingsSection(
            title: String(localized: "Connection"),
            isExpanded: $isExpanded
        ) {
            Text(
                String(
                    localized:
                        "Runs on this deployment's own engine. Nothing to connect and nothing to authenticate — its tool calls use the deployment's own credential."
                )
            )
            .captionText()
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
