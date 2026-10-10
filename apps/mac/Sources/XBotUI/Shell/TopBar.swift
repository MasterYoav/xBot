import SwiftUI
import XBotCore

/// The tab strip in the title bar row, with nothing behind it: the backdrop runs up under the tabs.
/// The selected tab is a soft translucent segment; each has its ⌘-number; "+" for a new chat; the
/// right end toggles files and changes. With the sidebar hidden, the traffic lights sit here and a
/// button brings the sidebar back.
struct TopBar: View {
    let workspace: Workspace
    let sidebarVisible: Bool
    let showSidebar: () -> Void
    @Binding var inspectorShown: Bool
    let inspectorAvailable: Bool
    /// Where each tab is laid out in the strip, measured, for reordering by drag.
    @State private var frames: [UUID: CGRect] = [:]
    @State private var drag: TabDrag?

    /// A tab being dragged: which one, and where in it the pointer took hold.
    private struct TabDrag: Equatable {
        let id: UUID
        let grab: CGFloat
        var pointer: CGFloat
    }

    var body: some View {
        HStack(spacing: 0) {
            if !sidebarVisible {
                Color.clear.frame(width: Metrics.trafficLights)
                IconButton("sidebar.left", help: String(localized: "Show sidebar (⌃⌘S)"), action: showSidebar)
                    .padding(.trailing, Space.xs)
            }
            ForEach(Array(workspace.openChatIDs.enumerated()), id: \.element) { index, id in
                if let chat = workspace.chat(id) {
                    let dragging = drag?.id == id
                    Tab(workspace: workspace, chat: chat, number: index + 1, lifted: dragging)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames[id] = $0 }
                        // Under the pointer while dragged; measured from where the tab is laid out
                        // now, so it stays put under the pointer as its neighbours move past it.
                        .offset(x: dragging ? offset(for: id) : 0)
                        .zIndex(dragging ? 1 : 0)
                        .gesture(reorder(id))
                }
            }
            IconButton("plus", help: String(localized: "New chat (⌘N)")) {
                workspace.startDraft(in: workspace.selectedChatID.flatMap { workspace.chat($0)?.projectID })
            }
            .padding(.horizontal, Space.xs)
            Color.clear
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
            IconButton(
                "sidebar.right",
                help: inspectorAvailable
                    ? String(localized: "Files and changes (⌥⌘0)")
                    : String(localized: "Choose a project to see its files and changes.")
            ) { inspectorShown.toggle() }
            .disabled(!inspectorAvailable)
            .padding(.trailing, Space.s)
        }
        .frame(height: Metrics.titleBar)
        .animation(Motion.panel, value: workspace.openChatIDs)
    }

    private func offset(for id: UUID) -> CGFloat {
        guard let drag, let frame = frames[id] else { return 0 }
        return drag.pointer - drag.grab - frame.minX
    }

    /**
     Hold a tab and drag it along the strip to move it. Its neighbours slide aside as its middle
     passes theirs, so the order is always the one that would land on release. A few points of
     travel before it starts, so a click still just selects the tab.
     */
    private func reorder(_ id: UUID) -> some Gesture {
        // Global, not a space named on the strip: measured in one, the dragged tab's own offset fed
        // back into the pointer's position and it stayed put however far the pointer went.
        DragGesture(minimumDistance: Space.xs, coordinateSpace: .global)
            .onChanged { value in
                guard let frame = frames[id] else { return }
                if drag?.id != id {
                    drag = TabDrag(id: id, grab: value.startLocation.x - frame.minX, pointer: value.location.x)
                }
                drag?.pointer = value.location.x
                guard let drag else { return }
                let middle = drag.pointer - drag.grab + frame.width / 2
                let others = workspace.openChatIDs.filter { $0 != id }
                let target = others.filter { (frames[$0]?.midX ?? .infinity) < middle }.count
                if workspace.openChatIDs.firstIndex(of: id) != target {
                    workspace.moveTab(id, to: target)
                }
            }
            .onEnded { _ in
                withAnimation(Motion.panel) { drag = nil }
            }
    }

    private struct Tab: View {
        let workspace: Workspace
        let chat: Chat
        let number: Int
        var lifted = false
        @State private var hovering = false

        var body: some View {
            let selected = workspace.selectedChatID == chat.id
            HStack(spacing: Space.s) {
                // Room for the ×, which is laid over the tab rather than inside it: inside, a click
                // on it reached the tab's own tap as well, which reopened the chat it had just closed.
                Color.clear.frame(width: Space.l, height: Space.l)
                Spacer(minLength: 0)
                if workspace.isRunning(chat.id) {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle().fill(Palette.agent(chat.harness)).frame(width: Metrics.dot, height: Metrics.dot)
                }
                Text(chat.title)
                    .font(Typography.chip)
                    .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if number <= 9 {
                    Text(verbatim: "⌘\(number)").font(Typography.chip).foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.horizontal, Space.s)
            .frame(minWidth: Metrics.tabMinWidth, maxWidth: Metrics.tabMaxWidth, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(selected ? Palette.tabSelected : (hovering ? Palette.hover : .clear))
            )
            .padding(.vertical, Space.xs)
            .padding(.horizontal, Space.xxs)
            .contentShape(Rectangle())
            .onTapGesture { workspace.open(chat.id) }
            .overlay(alignment: .leading) {
                Button { workspace.close(chat.id) } label: {
                    Image(systemName: "xmark").imageScale(.small).foregroundStyle(Palette.textTertiary)
                        .frame(width: Space.l, height: Space.l)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, Space.s + Space.xxs)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .help(String(localized: "Close tab (⌘W)"))
                .accessibilityLabel(String(localized: "Close \(chat.title)"))
            }
            .onHover { hovering = $0 }
            // Lifted off the strip while dragged.
            .shadow(color: .black.opacity(lifted ? 0.10 : 0), radius: 12, y: 8)
            .scaleEffect(lifted ? 1.03 : 1)
            .motion(Motion.quick, value: selected)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(chat.title)
        }
    }
}
