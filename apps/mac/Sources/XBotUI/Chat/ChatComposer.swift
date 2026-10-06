import SwiftUI
import XBotBrain
import XBotCore

/// The input. ⏎ sends; ⌥⏎ is a new line. The agent, model and permission chips sit under it.
struct ChatComposer: View {
    let workspace: Workspace
    let chat: Chat
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            TextField(String(localized: "Ask, build, plan…"), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .bodyText()
                .lineLimit(1...8)
                .focused($focused)
                .onSubmit(send)
            HStack(spacing: Space.s) {
                Menu(chat.harness.displayName) {
                    ForEach(workspace.availableHarnesses, id: \.self) { kind in
                        Button(kind.displayName) { workspace.setHarness(kind, for: chat.id) }
                    }
                }
                .fixedSize()
                if chat.harness.models.count > 1 {
                    Menu(chat.model ?? String(localized: "Default model")) {
                        ForEach(chat.harness.models, id: \.self) { model in
                            Button(model ?? String(localized: "Default model")) { workspace.setModel(model, for: chat.id) }
                        }
                    }
                    .fixedSize()
                }
                Menu {
                    ForEach(PermissionMode.allCases, id: \.self) { mode in
                        Button { workspace.setMode(mode, for: chat.id) } label: {
                            Label(mode.title, systemImage: mode.symbol)
                        }
                    }
                } label: {
                    Label(chat.mode.title, systemImage: chat.mode.symbol)
                }
                .fixedSize()
                Spacer()
                if let reason = workspace.sendBlockedReason(chat.id) {
                    Text(reason).captionText().foregroundStyle(Palette.textSecondary)
                }
                if workspace.isRunning(chat.id) {
                    Button { workspace.stop(chat.id) } label: { Image(systemName: "stop.circle.fill") }
                        .buttonStyle(.borderless)
                        .keyboardShortcut(".", modifiers: .command)
                        .help(String(localized: "Stop"))
                } else {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill") }
                        .buttonStyle(.borderless)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || workspace.sendBlockedReason(chat.id) != nil)
                        .help(String(localized: "Send"))
                }
            }
            .controlSize(.small)
            .menuStyle(.borderlessButton)
        }
        .padding(Space.m)
        .background(Palette.elevatedSurface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(Palette.separator))
        .padding(Space.l)
        .frame(maxWidth: Metrics.readingWidth)
        .onAppear { focused = true }
    }

    private func send() {
        // Cleared only when the workspace took it: a refused send keeps what was typed.
        if workspace.send(text, in: chat.id) { text = "" }
    }
}

extension PermissionMode {
    var title: String {
        switch self {
        case .readOnly: String(localized: "Read only")
        case .editFiles: String(localized: "Can edit")
        case .fullAccess: String(localized: "Full access")
        }
    }

    var symbol: String {
        switch self {
        case .readOnly: "eye"
        case .editFiles: "pencil"
        case .fullAccess: "bolt"
        }
    }
}
