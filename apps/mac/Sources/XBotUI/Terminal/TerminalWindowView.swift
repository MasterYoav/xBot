import SwiftUI
import XBotCore

/// A chat's terminal: one window floating over its right side, with a tab per shell. Tabs work
/// like the main ones (× on hover, + for another, drag to reorder); the empty part of the strip
/// moves the window; its left, right and bottom edges and bottom corners resize it.
struct TerminalWindowView: View {
    let workspace: Workspace
    let chatID: UUID
    /// The live move or resize, until the gesture ends and it's committed to the deck.
    @State private var live: (offset: CGSize, size: CGSize)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var deck: TerminalDeck { workspace.terminals }

    var body: some View {
        GeometryReader { geometry in
            if let panel = deck.panel(chatID) {
                let bounds = geometry.size
                let size = live?.size ?? panel.size
                let offset = live?.offset ?? panel.offset
                let origin = Self.origin(offset: offset, size: size, in: bounds)
                VStack(spacing: 0) {
                    TerminalTabStrip(
                        workspace: workspace, chatID: chatID, panel: panel,
                        moveWindow: { translation in
                            live = (CGSize(width: panel.offset.width + translation.width,
                                           height: panel.offset.height + translation.height), panel.size)
                        },
                        endMove: { commit(panel, bounds: bounds) }
                    )
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                    if let selected = panel.tabs.first(where: { $0.id == panel.selectedTabID }) {
                        ShellView(window: selected, focused: true)
                            .id(selected.id)
                            .padding(.horizontal, Space.s)
                            .padding(.vertical, Space.xs)
                    }
                }
                .frame(width: size.width, height: size.height)
                .background(Palette.terminalBackground, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(Palette.hairline))
                .overlay { resizeHandles(panel, bounds: bounds) }
                .floatingShadow()
                .offset(x: origin.x, y: origin.y)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(String(localized: "Terminal"))
            }
        }
    }

    // MARK: Resizing

    private enum Edge { case left, right, bottom, bottomLeft, bottomRight }

    private func resizeHandles(_ panel: TerminalPanel, bounds: CGSize) -> some View {
        let grip = Metrics.resizeGrip
        return ZStack {
            handle(.left, panel, bounds).frame(width: grip).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.top, Metrics.terminalTitleBar)
            handle(.right, panel, bounds).frame(width: grip).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.top, Metrics.terminalTitleBar)
            handle(.bottom, panel, bounds).frame(height: grip).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            handle(.bottomLeft, panel, bounds).frame(width: grip * 2, height: grip * 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            handle(.bottomRight, panel, bounds).frame(width: grip * 2, height: grip * 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    private func handle(_ edge: Edge, _ panel: TerminalPanel, _ bounds: CGSize) -> some View {
        let position: FrameResizePosition = switch edge {
        case .left: .leading
        case .right: .trailing
        case .bottom: .bottom
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
        return Color.clear
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: position))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in live = Self.resized(panel, edge: edge, by: value.translation) }
                    .onEnded { _ in commit(panel, bounds: bounds) }
            )
    }

    /// The window hangs from the chat's right edge, so its offset says where the right edge is:
    /// growing to the left keeps it; growing to the right moves it by as much.
    private static func resized(_ panel: TerminalPanel, edge: Edge, by delta: CGSize) -> (CGSize, CGSize) {
        let min = TerminalDeck.minimumSize
        var size = panel.size
        var offset = panel.offset
        if [.left, .bottomLeft].contains(edge) { size.width = max(min.width, panel.size.width - delta.width) }
        if [.right, .bottomRight].contains(edge) {
            size.width = max(min.width, panel.size.width + delta.width)
            offset.width += size.width - panel.size.width
        }
        if [.bottom, .bottomLeft, .bottomRight].contains(edge) { size.height = max(min.height, panel.size.height + delta.height) }
        return (offset, size)
    }

    private func commit(_ panel: TerminalPanel, bounds: CGSize) {
        guard let live else { return }
        // Kept where its tab strip can still be grabbed.
        let origin = Self.origin(offset: live.offset, size: live.size, in: bounds)
        let home = Self.home(size: live.size, in: bounds)
        deck.setFrame(chatID, offset: CGSize(width: origin.x - home.x, height: origin.y - home.y), size: live.size)
        self.live = nil
    }

    // MARK: Placement

    /// Where a window of `size` sits with no offset: the chat's top-right corner, inset.
    static func home(size: CGSize, in bounds: CGSize) -> CGPoint {
        CGPoint(x: bounds.width - size.width - Space.l, y: Space.l)
    }

    /// Its top-left corner, kept on screen enough to grab the strip again.
    static func origin(offset: CGSize, size: CGSize, in bounds: CGSize) -> CGPoint {
        let home = home(size: size, in: bounds)
        let keep: CGFloat = 80
        return CGPoint(x: min(max(home.x + offset.width, keep - size.width), bounds.width - keep),
                       y: min(max(home.y + offset.height, 0), max(bounds.height - Metrics.terminalTitleBar, 0)))
    }
}

// MARK: - Tabs

/// The window's tab strip, made like the top bar's: the selected tab a soft segment, × on hover,
/// + after the last, drag a tab along the strip to move it; the empty end moves the window.
private struct TerminalTabStrip: View {
    let workspace: Workspace
    let chatID: UUID
    let panel: TerminalPanel
    let moveWindow: (CGSize) -> Void
    let endMove: () -> Void
    @State private var frames: [UUID: CGRect] = [:]
    @State private var drag: TabDrag?

    private struct TabDrag: Equatable {
        let id: UUID
        let grab: CGFloat
        var pointer: CGFloat
    }

    private var deck: TerminalDeck { workspace.terminals }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(panel.tabs) { tab in
                let dragging = drag?.id == tab.id
                TerminalTabView(
                    tab: tab, selected: panel.selectedTabID == tab.id, lifted: dragging,
                    title: TerminalShells.shared.titles[tab.id],
                    select: { deck.select(tab.id) }, close: { deck.closeTab(tab.id) }
                )
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames[tab.id] = $0 }
                .offset(x: dragging ? offset(for: tab.id) : 0)
                .zIndex(dragging ? 1 : 0)
                .gesture(reorder(tab.id))
            }
            IconButton("plus", help: String(localized: "New terminal tab")) { workspace.openTerminal(in: chatID) }
                .padding(.horizontal, Space.xs)
            // The empty end of the strip moves the window.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { moveWindow($0.translation) }
                        .onEnded { _ in endMove() }
                )
            IconButton("minus", help: String(localized: "Hide terminal (⌃`)")) { workspace.toggleTerminals(in: chatID) }
                .padding(.trailing, Space.xs)
        }
        .padding(.leading, Space.xs)
        .frame(height: Metrics.terminalTitleBar)
        .animation(Motion.panel, value: panel.tabs.map(\.id))
    }

    private func offset(for id: UUID) -> CGFloat {
        guard let drag, let frame = frames[id] else { return 0 }
        return drag.pointer - drag.grab - frame.minX
    }

    /// As in the top bar: neighbours slide aside as the dragged tab's middle passes theirs.
    private func reorder(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: Space.xs, coordinateSpace: .global)
            .onChanged { value in
                guard let frame = frames[id] else { return }
                if drag?.id != id {
                    drag = TabDrag(id: id, grab: value.startLocation.x - frame.minX, pointer: value.location.x)
                    deck.select(id)
                }
                drag?.pointer = value.location.x
                guard let drag else { return }
                let middle = drag.pointer - drag.grab + frame.width / 2
                let ids = panel.tabs.map(\.id)
                let target = ids.filter { $0 != id && (frames[$0]?.midX ?? .infinity) < middle }.count
                if ids.firstIndex(of: id) != target { deck.moveTab(id, to: target) }
            }
            .onEnded { _ in withAnimation(Motion.panel) { drag = nil } }
    }
}

private struct TerminalTabView: View {
    let tab: TerminalTab
    let selected: Bool
    let lifted: Bool
    let title: String?
    let select: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Space.s) {
            // Room for the ×, laid over the tab as in the top bar so its click can't select the tab.
            Color.clear.frame(width: Space.l, height: Space.l)
            Spacer(minLength: 0)
            Image(systemName: "terminal").imageScale(.small).foregroundStyle(Palette.textTertiary)
            Text(Self.short(title) ?? String(localized: "Terminal \(tab.number)"))
                .font(Typography.chip)
                .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s)
        .frame(minWidth: Metrics.terminalTabMinWidth, maxWidth: Metrics.terminalTabMaxWidth, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(selected ? Palette.tabSelected : (hovering ? Palette.hover : .clear))
        )
        .padding(.vertical, Space.xs)
        .padding(.horizontal, Space.xxs)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .overlay(alignment: .leading) {
            Button(action: close) {
                Image(systemName: "xmark").imageScale(.small).foregroundStyle(Palette.textTertiary)
                    .frame(width: Space.l, height: Space.l)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, Space.s + Space.xxs)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .help(String(localized: "Close tab (ends its shell)"))
            .accessibilityLabel(String(localized: "Close terminal \(tab.number)"))
        }
        .onHover { hovering = $0 }
        .shadow(color: .black.opacity(lifted ? 0.10 : 0), radius: 12, y: 8)
        .scaleEffect(lifted ? 1.03 : 1)
        .motion(Motion.quick, value: selected)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(Self.short(title) ?? String(localized: "Terminal \(tab.number)"))
    }

    /// Shells title themselves "user@host:~/a/b/c": a tab has room for the end of the path.
    static func short(_ title: String?) -> String? {
        guard let title, !title.isEmpty else { return nil }
        if let colon = title.lastIndex(of: ":"), title[..<colon].contains("@") {
            let path = title[title.index(after: colon)...]
            return path.split(separator: "/").last.map(String.init) ?? String(path)
        }
        return title
    }
}

/// Bottom-right of a chat: shows its terminal, and hides it on the second press.
struct TerminalToggle: View {
    let workspace: Workspace
    let chatID: UUID

    var body: some View {
        let shown = workspace.terminals.isShown(chatID)
        let count = workspace.terminals.tabs(in: chatID).count
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
        .help(shown ? String(localized: "Hide terminal (⌃`)") : String(localized: "Show terminal (⌃`)"))
        .accessibilityLabel(shown ? String(localized: "Hide terminal") : String(localized: "Show terminal"))
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
