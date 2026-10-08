import SwiftUI
import XBotCore

/// The tab strip, Terminal-style: full-height segments in the title bar row, the selected one the
/// colour of the content below it, each with its ⌘-number; "+" for a new chat. With the sidebar
/// hidden, the traffic lights sit here and a button brings the sidebar back.
struct TopBar: View {
    let workspace: Workspace
    let sidebarVisible: Bool
    let showSidebar: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if !sidebarVisible {
                Color.clear.frame(width: Metrics.trafficLights)
                IconButton("sidebar.left", help: String(localized: "Show sidebar (⌃⌘S)"), action: showSidebar)
                    .padding(.trailing, Space.xs)
            }
            ForEach(Array(workspace.openChatIDs.enumerated()), id: \.element) { index, id in
                if let chat = workspace.chat(id) {
                    Tab(workspace: workspace, chat: chat, number: index + 1)
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
            if let id = workspace.selectedChatID, let chat = workspace.chat(id) {
                MonoLabel(context(for: chat)).padding(.trailing, Space.m)
            }
        }
        .frame(height: Metrics.titleBar)
        // The hairline sits behind the tabs, so the selected tab — the content's colour — runs
        // straight into the content below it.
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                Palette.tabStrip
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }
        }
    }

    /// "XBOT › MASTER", or "INBOX".
    private func context(for chat: Chat) -> String {
        guard let project = workspace.projects.first(where: { $0.id == chat.projectID }) else {
            return String(localized: "Inbox")
        }
        return [project.name, workspace.branch(for: project.id)].compactMap { $0 }.joined(separator: " › ")
    }

    private struct Tab: View {
        let workspace: Workspace
        let chat: Chat
        let number: Int
        @State private var hovering = false

        var body: some View {
            let selected = workspace.selectedChatID == chat.id
            HStack(spacing: Space.s) {
                Button { workspace.close(chat.id) } label: {
                    Image(systemName: "xmark").imageScale(.small).foregroundStyle(Palette.textTertiary)
                        .frame(width: Space.l, height: Space.l)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .help(String(localized: "Close tab (⌘W)"))
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
            .background(selected ? Palette.window : (hovering ? Palette.hover : .clear))
            .overlay(alignment: .trailing) { Rectangle().fill(Palette.hairline).frame(width: 1) }
            .contentShape(Rectangle())
            .onTapGesture { workspace.open(chat.id) }
            .onHover { hovering = $0 }
            .motion(Motion.quick, value: selected)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(chat.title)
        }
    }
}
