import SwiftUI

/// A titled, collapsible block for agent settings subsections.
struct CollapsibleSettingsSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
        } label: {
            Text(title).bodyText()
        }
        .disclosureGroupStyle(.xbotSettings)
    }
}

private struct XBotSettingsDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button {
                withAnimation(Motion.standard) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack {
                    configuration.label
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 0 : -90))
                }
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
                    .padding(.leading, Space.xs)
            }
        }
    }
}

extension DisclosureGroupStyle where Self == XBotSettingsDisclosureStyle {
    fileprivate static var xbotSettings: XBotSettingsDisclosureStyle { XBotSettingsDisclosureStyle() }
}
