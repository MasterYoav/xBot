import SwiftUI
import XBotCore

/// "What should we work on?" — the composer, and four ways in.
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
                Text(String(localized: "What should we work on?")).heroText().foregroundStyle(Palette.textPrimary)
                Composer(workspace: workspace, target: .draft, namespace: composer, addProject: addProject)
                    .frame(maxWidth: Metrics.composerWidth)
                HStack(spacing: Space.m) {
                    ForEach(Suggestion.allCases, id: \.self) { suggestion in
                        SuggestionCard(suggestion: suggestion) { workspace.use(suggestion) }
                    }
                }
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

private struct SuggestionCard: View {
    let suggestion: Suggestion
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s) {
                Image(systemName: suggestion.symbol).font(Typography.title).foregroundStyle(Palette.accent)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(suggestion.title).bodyText().foregroundStyle(Palette.textPrimary)
                    Text(suggestion.subtitle).bodyText().foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: Metrics.suggestionHeight)
            .raisedSurface()
            .background(hovering ? Palette.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .cardShadow()
            .offset(y: hovering ? -1 : 0)
        }
        .buttonStyle(XBotButtonStyle())
        .onHover { hovering = $0 }
        .motion(Motion.quick, value: hovering)
    }
}
