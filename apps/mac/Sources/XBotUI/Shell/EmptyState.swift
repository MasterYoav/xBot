import SwiftUI
import XBotCore

struct EmptyState: View {
    let workspace: Workspace
    let addProject: () -> Void

    var body: some View {
        VStack(spacing: Space.l) {
            AppMarkView()
            if workspace.isDiscovering, workspace.availableHarnesses.isEmpty {
                ProgressView().controlSize(.small)
                Text(String(localized: "Looking for your agents…"))
                    .bodyText()
                    .foregroundStyle(Palette.textSecondary)
            } else if workspace.availableHarnesses.isEmpty {
                Text(String(localized: "xBot works through an AI agent you already have."))
                    .titleText()
                Text(String(localized: "Install Claude Code or Codex and sign in, then come back. xBot will find it."))
                    .bodyText()
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: Space.m) {
                    Link(String(localized: "Get Claude Code"), destination: URL(string: "https://claude.com/product/claude-code")!)
                    Link(String(localized: "Get Codex"), destination: URL(string: "https://developers.openai.com/codex")!)
                }
                Button(String(localized: "Look Again")) { Task { await workspace.refreshHarnesses() } }
                    .buttonStyle(.borderedProminent)
            } else {
                Text(String(localized: "What are we working on?")).titleText()
                HStack(spacing: Space.m) {
                    Button(String(localized: "New Chat")) { workspace.newChat(in: nil) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("n", modifiers: .command)
                    Button(String(localized: "Add a Project Folder…"), action: addProject)
                }
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
