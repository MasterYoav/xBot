import SwiftUI
import XBotCore

/// Rail, conversation, panel — over an aurora field, with chrome in the title bar.
public struct MainWindow: View {
    @Environment(AppState.self) private var state
    @State private var isPaletteOpen = false

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            if state.isRailVisible {
                Rail(isPaletteOpen: $isPaletteOpen)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Conversation()
                .frame(minWidth: Metrics.conversationMinimumWidth)

            if state.isPanelVisible {
                Divider().overlay(Palette.separator.opacity(0.35))
                Panel()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(
            minWidth: Metrics.minimumWindow.width,
            minHeight: Metrics.minimumWindow.height
        )
        .background {
            AuroraBackground()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                sidebarToggle(
                    isVisible: state.isRailVisible,
                    symbol: "sidebar.left",
                    label: String(localized: "Toggle agent rail")
                ) {
                    state.isRailVisible.toggle()
                }
            }
            ToolbarItem(placement: .principal) {
                TitleBarAgentTitle()
            }
            ToolbarItem(placement: .primaryAction) {
                sidebarToggle(
                    isVisible: state.isPanelVisible,
                    symbol: "sidebar.right",
                    label: String(localized: "Toggle panel")
                ) {
                    state.isPanelVisible.toggle()
                }
            }
        }
        .toolbarRole(.editor)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .overlay {
            if isPaletteOpen {
                CommandPalette(isOpen: $isPaletteOpen)
            }
        }
        .background {
            shortcuts
        }
        .background(WindowChromeConfigurator())
        .motion(Motion.panel, value: state.isRailVisible)
        .motion(Motion.panel, value: state.isPanelVisible)
        .task { await state.load() }
    }

    private func sidebarToggle(
        isVisible: Bool,
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .symbolVariant(isVisible ? .fill : .none)
                .foregroundStyle(isVisible ? Palette.textPrimary : Palette.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isVisible ? .isSelected : [])
    }

    private var shortcuts: some View {
        Group {
            Button("") { isPaletteOpen.toggle() }
                .keyboardShortcut("k", modifiers: .command)

            ForEach(Array(state.agents.prefix(9).enumerated()), id: \.element.id) { index, agent in
                Button("") { state.select(agent.id) }
                    .keyboardShortcut(
                        KeyEquivalent(Character("\(index + 1)")),
                        modifiers: .command
                    )
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}
