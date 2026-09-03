import SwiftUI
import XBotCore

/// The right-hand panel: parallel, non-blocking, no scrim.
///
/// It sits beside the conversation rather than over it, which is why both are readable at once.
/// A scrim would say "deal with me first", and none of these four sections is that.
public struct Panel: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        @Bindable var state = state

        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.separator)

            switch state.panelSection {
            case .screen: ScreenSection()
            case .activity: ActivitySection()
            case .routines: RoutinesSection()
            case .settings: AgentSettingsSection()
            }
        }
        .frame(width: Metrics.panelWidth.lowerBound)
        .frame(maxHeight: .infinity)
        .frostedGlass(opaqueFallback: Palette.panelBackground)
        // Enters and exits to the right, always. A panel that slid in from the right and faded
        // out in place would read as two different objects.
        .transition(.move(edge: .trailing))
    }

    private var header: some View {
        @Bindable var state = state

        return HStack(spacing: Space.s) {
            Picker("", selection: $state.panelSection) {
                ForEach(AppState.PanelSection.allCases) { section in
                    Image(systemName: section.symbol)
                        .help(section.title)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Button {
                state.isPanelVisible = false
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
            .buttonStyle(XBotButtonStyle())
            .accessibilityLabel(String(localized: "Hide panel"))
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
    }
}

/// A titled block inside the panel.
public struct PanelSectionBody<Content: View>: View {
    private let title: String
    private let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                Text(title)
                    .captionText()
                    .foregroundStyle(Palette.textSecondary)
                    .textCase(.uppercase)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.l)
        }
    }
}
