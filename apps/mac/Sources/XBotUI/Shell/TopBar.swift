import SwiftUI
import XBotCore

/// Open chats as pill tabs, and where the selected chat works — the window's drag area too.
struct TopBar: View {
    let workspace: Workspace

    var body: some View {
        HStack(spacing: Space.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xxs) {
                    ForEach(workspace.openChatIDs, id: \.self) { id in
                        if let chat = workspace.chat(id) { Tab(workspace: workspace, chat: chat) }
                    }
                }
            }
            Spacer(minLength: Space.m)
            if let id = workspace.selectedChatID, let chat = workspace.chat(id) {
                MonoLabel(context(for: chat))
            }
        }
        .padding(.horizontal, Space.m)
        .frame(height: Metrics.topBar)
        .background(Palette.window.gesture(WindowDragGesture()))
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
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
        @State private var hovering = false

        var body: some View {
            let selected = workspace.selectedChatID == chat.id
            HStack(spacing: Space.xs) {
                if workspace.isRunning(chat.id) {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle().fill(Palette.agent(chat.harness)).frame(width: Metrics.dot, height: Metrics.dot)
                }
                Text(chat.title).font(Typography.chip).lineLimit(1)
                    .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                if hovering || selected {
                    Button { workspace.close(chat.id) } label: {
                        Image(systemName: "xmark").imageScale(.small).foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Close tab"))
                }
            }
            .padding(.horizontal, Space.s + 2)
            .frame(height: Metrics.chipHeight)
            .frame(maxWidth: Metrics.tabMaxWidth)
            .background(selected ? Palette.raised : (hovering ? Palette.hover : .clear), in: Capsule())
            .overlay { if selected { Capsule().strokeBorder(Palette.hairline) } }
            .contentShape(Capsule())
            .onTapGesture { workspace.open(chat.id) }
            .onHover { hovering = $0 }
            .motion(Motion.quick, value: selected)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(chat.title)
        }
    }
}
