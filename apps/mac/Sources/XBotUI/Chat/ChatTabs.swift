import SwiftUI
import XBotCore

/// Open chats as tabs. Closing a tab does not stop its turn or delete it.
struct ChatTabs: View {
    let workspace: Workspace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                ForEach(workspace.openChatIDs, id: \.self) { id in
                    if let chat = workspace.chat(id) { tab(chat) }
                }
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
        }
        .background(Palette.inset)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func tab(_ chat: Chat) -> some View {
        let selected = workspace.selectedChatID == chat.id
        return HStack(spacing: Space.xs) {
            if workspace.isRunning(chat.id) { ProgressView().controlSize(.mini) }
            Text(chat.title).captionText().lineLimit(1)
            Spacer(minLength: Space.xs)
            Button { workspace.close(chat.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(String(localized: "Close tab"))
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .frame(width: Metrics.tabMaxWidth)
        .background(
            selected ? Palette.raised : .clear,
            in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture { workspace.open(chat.id) }
        .motion(Motion.quick, value: selected)
    }
}
