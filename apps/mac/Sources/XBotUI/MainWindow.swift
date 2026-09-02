import SwiftUI
import XBotCore

/// Rail, conversation, panel.
public struct MainWindow: View {
    @Environment(AppState.self) private var state
    @State private var isPaletteOpen = false

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            let panelIsOverlay = geometry.size.width < Metrics.panelCollapsesBelow

            HStack(spacing: 0) {
                Rail()
                Conversation()
                    .overlay(alignment: .topTrailing) { panelToggle }

                // Below ~1100pt the panel stops being a column and becomes an overlay: at that
                // width a 320pt column leaves the conversation too narrow to read comfortably,
                // and a cramped conversation is a worse trade than a covered one.
                if state.isPanelVisible && !panelIsOverlay {
                    Divider().overlay(Palette.separator)
                    Panel()
                }
            }
            .overlay(alignment: .trailing) {
                if state.isPanelVisible && panelIsOverlay {
                    Panel()
                        .shadow(color: .black.opacity(0.18), radius: 16, x: -4)
                }
            }
            .motion(Motion.panel, value: state.isPanelVisible)
        }
        .frame(
            minWidth: Metrics.minimumWindow.width,
            minHeight: Metrics.minimumWindow.height
        )
        .overlay {
            if isPaletteOpen {
                CommandPalette(isOpen: $isPaletteOpen)
            }
        }
        .background {
            // Keyboard shortcuts live on zero-size buttons rather than in a menu, because this
            // package has no menu bar yet and a shortcut nobody can reach is not a shortcut.
            shortcuts
        }
        .task { await state.load() }
    }

    @ViewBuilder
    private var panelToggle: some View {
        if !state.isPanelVisible {
            Button {
                state.isPanelVisible = true
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
            }
            .buttonStyle(XBotButtonStyle())
            .padding(Space.m)
            .accessibilityLabel(String(localized: "Show panel"))
        }
    }

    private var shortcuts: some View {
        Group {
            Button("") { isPaletteOpen.toggle() }
                .keyboardShortcut("k", modifiers: .command)

            // ⌘1–⌘9 select an agent, as the command palette advertises.
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
