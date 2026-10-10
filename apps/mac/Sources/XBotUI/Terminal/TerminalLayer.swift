import SwiftUI
import XBotCore

/// A chat's terminal windows, floating over its right side. Dragged by the title bar, resized
/// from the bottom-left corner, raised by a click.
struct TerminalLayer: View {
    let workspace: Workspace
    let chatID: UUID
    /// The window to give the keyboard to: the newest, or the one just clicked.
    @State private var focusedID: UUID?

    private var deck: TerminalDeck { workspace.terminals }

    var body: some View {
        GeometryReader { geometry in
            let bounds = geometry.size
            ZStack(alignment: .topLeading) {
                ForEach(deck.windows(in: chatID)) { window in
                    FloatingTerminal(
                        deck: deck, window: window, bounds: bounds, focused: focusedID == window.id,
                        title: TerminalShells.shared.titles[window.id],
                        raise: {
                            deck.raise(window.id)
                            focusedID = window.id
                        },
                        newWindow: {
                            workspace.openTerminal(in: chatID)
                            focusedID = deck.windows(in: chatID).last?.id
                        },
                        close: { deck.close(window.id) }
                    )
                }
            }
            .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        }
        .onAppear { focusedID = deck.windows(in: chatID).last?.id }
        .onChange(of: deck.windows(in: chatID).map(\.id)) { _, ids in
            if let focusedID, ids.contains(focusedID) { return }
            focusedID = ids.last
        }
    }
}

private struct FloatingTerminal: View {
    let deck: TerminalDeck
    let window: TerminalWindow
    let bounds: CGSize
    let focused: Bool
    let title: String?
    let raise: () -> Void
    let newWindow: () -> Void
    let close: () -> Void
    @State private var drag: CGSize = .zero
    @State private var grow: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = CGSize(width: max(TerminalDeck.minimumSize.width, window.size.width + grow.width),
                          height: max(TerminalDeck.minimumSize.height, window.size.height + grow.height))
        let origin = Self.origin(of: window, size: size, extra: drag, in: bounds)
        VStack(spacing: 0) {
            titleBar
            ShellView(window: window, focused: focused)
                .padding(.horizontal, Space.s)
                .padding(.bottom, Space.s)
        }
        .frame(width: size.width, height: size.height)
        .background(Palette.terminalBackground, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
            .strokeBorder(focused ? Palette.accent.opacity(0.5) : Palette.hairline))
        .overlay(alignment: .bottomLeading) { resizeGrip(size) }
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .floatingShadow()
        .offset(x: origin.x, y: origin.y)
        .simultaneousGesture(TapGesture().onEnded(raise))
        .transition(reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Terminal \(window.number)"))
    }

    private var titleBar: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "terminal").imageScale(.small).foregroundStyle(Palette.textTertiary)
            Text(title ?? Self.fallbackTitle(window))
                .font(Typography.chip)
                .foregroundStyle(focused ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: Space.s)
            IconButton("plus", help: String(localized: "New terminal"), action: newWindow)
            IconButton("xmark", help: String(localized: "Close this terminal (ends its shell)"), action: close)
        }
        .padding(.leading, Space.m)
        .padding(.trailing, Space.xs)
        .frame(height: Metrics.terminalTitleBar)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if drag == .zero { raise() }
                    drag = value.translation
                }
                .onEnded { value in
                    let size = window.size
                    let landed = Self.origin(of: window, size: size, extra: value.translation, in: bounds)
                    let home = Self.home(size: size, in: bounds)
                    deck.move(window.id, to: CGSize(width: landed.x - home.x, height: landed.y - home.y))
                    drag = .zero
                }
        )
        .accessibilityAddTraits(.isHeader)
    }

    /// Bottom-left: the window hangs from the right, so it grows out to the left and down.
    private func resizeGrip(_ size: CGSize) -> some View {
        Image(systemName: "arrow.down.left")
            .font(Typography.caption)
            .foregroundStyle(Palette.textTertiary)
            .frame(width: Metrics.iconButton, height: Metrics.iconButton)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        grow = CGSize(width: -value.translation.width, height: value.translation.height)
                    }
                    .onEnded { _ in
                        // The home spot hangs from the right edge, so that edge stays put.
                        deck.resize(window.id, to: size)
                        grow = .zero
                    }
            )
            .help(String(localized: "Drag to resize"))
    }

    /// Where a window of `size` sits with no offset: the chat's top-right corner, inset.
    static func home(size: CGSize, in bounds: CGSize) -> CGPoint {
        CGPoint(x: bounds.width - size.width - Space.l, y: Space.l)
    }

    /// Its top-left corner, kept on screen enough to grab the title bar again.
    static func origin(of window: TerminalWindow, size: CGSize, extra: CGSize, in bounds: CGSize) -> CGPoint {
        let home = home(size: size, in: bounds)
        let x = home.x + window.offset.width + extra.width
        let y = home.y + window.offset.height + extra.height
        let keep: CGFloat = 80
        return CGPoint(x: min(max(x, keep - size.width), bounds.width - keep),
                       y: min(max(y, 0), max(bounds.height - Metrics.terminalTitleBar, 0)))
    }

    static func fallbackTitle(_ window: TerminalWindow) -> String {
        let shell = (TerminalShells.loginShell as NSString).lastPathComponent
        return "\(shell) — \(window.directory.lastPathComponent)"
    }
}

/// Bottom-right of a chat: shows its terminals, and hides them on the second press.
struct TerminalToggle: View {
    let workspace: Workspace
    let chatID: UUID

    var body: some View {
        let shown = workspace.terminals.isShown(chatID)
        let count = workspace.terminals.windows(in: chatID).count
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0)) { workspace.toggleTerminals(in: chatID) }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: "terminal")
                if count > 0 { Text(verbatim: "\(count)").font(Typography.label) }
            }
            .foregroundStyle(shown ? Palette.textInverse : Palette.textSecondary)
            .padding(.horizontal, Space.m)
            .frame(height: Metrics.chipHeight + Space.xs)
            .background(Capsule().fill(shown ? Palette.accent : Palette.raised))
            .overlay(Capsule().strokeBorder(Palette.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .keyboardShortcut("`", modifiers: .control)
        .help(shown ? String(localized: "Hide terminals (⌃`)") : String(localized: "Show terminals (⌃`)"))
        .accessibilityLabel(shown ? String(localized: "Hide terminals") : String(localized: "Show terminals"))
    }
}

/// Feedback on pointer-down.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.15, bounce: 0), value: configuration.isPressed)
    }
}
