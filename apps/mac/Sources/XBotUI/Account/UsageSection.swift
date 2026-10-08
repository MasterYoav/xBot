import SwiftUI
import XBotCore

/// "Usage remaining": per agent, the five-hour and weekly windows — what is left and when it
/// resets. Claude Code's come from its own turns; Codex's are read from its logs each minute.
struct UsageSection: View {
    let workspace: Workspace
    @AppStorage("usageExpanded") private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Button { withAnimation(Motion.quick) { expanded.toggle() } } label: {
                HStack {
                    Label(String(localized: "Usage remaining"), systemImage: "gauge.with.dots.needle.33percent")
                        .bodyText()
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(Palette.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: Space.m) {
                        ForEach(agents, id: \.self) { agent($0, now: context.date) }
                        if let newest = workspace.usage.values.map(\.updatedAt).max() {
                            Text(UsageText.updated(newest, now: context.date))
                                .captionText()
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.s)
        .task {
            while !Task.isCancelled {
                await workspace.refreshCodexUsage()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// The installed agents, or both before they have been looked for.
    private var agents: [HarnessKind] {
        workspace.availableHarnesses.isEmpty ? HarnessKind.allCases : workspace.availableHarnesses
    }

    private func agent(_ kind: HarnessKind, now: Date) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Circle().fill(Palette.agent(kind)).frame(width: Metrics.dot, height: Metrics.dot)
                Text(kind.displayName).captionText().foregroundStyle(Palette.textSecondary)
            }
            if let limits = workspace.usage[kind]?.limits {
                window(String(localized: "5h"), limits.fiveHour, now: now)
                window(String(localized: "Weekly"), limits.weekly, now: now)
            } else {
                Text(kind == .claude
                     ? String(localized: "Run a turn to see Claude Code's usage.")
                     : String(localized: "No Codex usage yet."))
                    .captionText()
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func window(_ title: String, _ window: RateWindow?, now: Date) -> some View {
        HStack(spacing: Space.s) {
            Text(title).bodyText().foregroundStyle(Palette.textPrimary)
            Spacer()
            Text(window.map(UsageText.remaining) ?? "—").font(Typography.mono).foregroundStyle(Palette.textPrimary)
            Text(window.map { UsageText.resets($0.resetsAt, now: now) } ?? "")
                .captionText()
                .foregroundStyle(Palette.textTertiary)
                .frame(width: Space.xxl * 2 + Space.s, alignment: .trailing)
        }
    }
}
