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
            if let onboarding = workspace.onboarding, onboarding.showsReminder {
                FinishSettingUpRow(onboarding: onboarding)
                    .frame(maxWidth: Metrics.composerWidth)
            }
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
            Text(String(localized: "Install Claude Code, Codex, Antigravity or GitHub Copilot and sign in, then come back. xBot will find it."))
                .bodyText()
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            // One row when it fits; a column in a narrow window.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.m) { installLinks }
                VStack(spacing: Space.s) { installLinks }
            }
            .font(Typography.chip)
            .tint(Palette.accent)
            Button(String(localized: "Look again")) { Task { await workspace.refreshHarnesses() } }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    /// Where to get each CLI xBot drives, in `HarnessKind` order.
    @ViewBuilder private var installLinks: some View {
        Link(String(localized: "Get Claude Code"), destination: URL(string: "https://claude.com/product/claude-code")!)
        Link(String(localized: "Get Codex"), destination: URL(string: "https://developers.openai.com/codex")!)
        Link(String(localized: "Get Antigravity"), destination: URL(string: "https://antigravity.google")!)
        Link(String(localized: "Get GitHub Copilot"), destination: URL(string: "https://github.com/github/copilot-cli")!)
    }
}

/// While the tour was skipped and not finished: a quiet row to pick it up again, or dismiss.
private struct FinishSettingUpRow: View {
    let onboarding: OnboardingModel

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "sparkles")
                .font(Typography.emphasis)
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Finish setting up")).emphasisText()
                Text(String(localized: "Your agents, file access and your iPhone, in the welcome tour."))
                    .captionText().foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: Space.s)
            Button(String(localized: "Continue")) { onboarding.reopen() }
                .buttonStyle(QuietButtonStyle())
            IconButton("xmark", help: String(localized: "Dismiss")) { onboarding.dismissReminder() }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .raisedSurface()
        .cardShadow()
    }
}
