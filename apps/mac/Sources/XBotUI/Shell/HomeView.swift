import SwiftUI
import XBotCore

/// A new chat before its first message: the composer on its own. (Home's greeting and suggestion
/// cards were taken out on request: they got in the way more than they helped.)
struct HomeView: View {
    let workspace: Workspace
    let composer: Namespace.ID
    let addProject: () -> Void

    var body: some View {
        VStack(spacing: Space.xl) {
            Spacer(minLength: Space.xl)
            if workspace.availableHarnesses.isEmpty && !workspace.isDiscovering {
                noAgent
            } else {
                Composer(workspace: workspace, target: .draft, namespace: composer, addProject: addProject)
                    .frame(maxWidth: Metrics.composerWidth)
            }
            Spacer(minLength: Space.xl)
            Spacer(minLength: Space.xl)
        }
        .padding(.horizontal, Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noAgent: some View {
        VStack(spacing: Space.m) {
            AppMarkView(size: Space.xxl + Space.l)
            Text(String(localized: "xBot works through an agent you already have.")).titleText()
            Text(String(localized: "Install Claude Code or Codex and sign in, then come back. xBot will find it."))
                .bodyText()
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: Space.m) {
                Link(String(localized: "Get Claude Code"), destination: URL(string: "https://claude.com/product/claude-code")!)
                Link(String(localized: "Get Codex"), destination: URL(string: "https://developers.openai.com/codex")!)
            }
            .font(Typography.chip)
            .tint(Palette.accent)
            Button(String(localized: "Look again")) { Task { await workspace.refreshHarnesses() } }
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}
