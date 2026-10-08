import SwiftUI
import XBotCore

/// Your profile: who you are, and what you and your agents have done together — built from the
/// agents' own history on this Mac. After ChatGPT's profile page, in xBot's tokens.
struct ProfileView: View {
    let workspace: Workspace
    private let identity = Identity.shared
    @State private var mode = ProfileStats.Mode.daily
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                person
                if let history = workspace.history {
                    let stats = ProfileStats(days: history.days, today: .now, calendar: .current)
                    statsStrip(stats, history)
                    if !history.projects.isEmpty { showcase(history) }
                    activity(history)
                    if !history.tools.isEmpty { topTools(history) }
                    insights(history)
                    missing(history)
                } else {
                    VStack(spacing: Space.s) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "Reading your history…")).captionText().foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.top, Space.xxl)
                }
            }
            .frame(maxWidth: Metrics.readingWidth)
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.xxl)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            Button(String(localized: "Edit")) { editing = true }
                .buttonStyle(QuietButtonStyle())
                .padding(Space.m)
        }
        .sheet(isPresented: $editing) { EditProfileSheet(identity: identity) }
        .task { await workspace.indexHistory() }
    }

    // MARK: Sections

    private var person: some View {
        VStack(spacing: Space.s) {
            Avatar(identity: identity, size: Metrics.avatarLarge)
            Text(identity.name).heroText().foregroundStyle(Palette.textPrimary)
            Text(verbatim: "@\(identity.username)").bodyText().foregroundStyle(Palette.textTertiary)
        }
    }

    private func statsStrip(_ stats: ProfileStats, _ history: HistorySummary) -> some View {
        HStack(spacing: 0) {
            stat(compact(stats.lifetime), String(localized: "Lifetime tokens"),
                 help: String(localized: "Input, output and cached tokens, as your agents count them."))
            divider
            stat(compact(stats.peak), String(localized: "Peak tokens"), help: String(localized: "Your busiest day."))
            divider
            stat(duration(history.longestTask), String(localized: "Longest task"))
            divider
            stat(days(stats.longestStreak), String(localized: "Longest streak"))
            divider
            stat(days(stats.currentStreak), String(localized: "Current streak"))
        }
        .padding(.vertical, Space.l)
        .raisedSurface()
        .cardShadow()
    }

    private var divider: some View { Rectangle().fill(Palette.hairline).frame(width: 1, height: Space.xxl + Space.s) }

    private func stat(_ value: String, _ label: String, help: String? = nil) -> some View {
        VStack(spacing: Space.xs) {
            Text(value).titleText().foregroundStyle(Palette.textPrimary).monospacedDigit()
            HStack(spacing: Space.xxs) {
                Text(label).captionText().foregroundStyle(Palette.textTertiary).lineLimit(1)
                if let help {
                    Image(systemName: "questionmark.circle").imageScale(.small).foregroundStyle(Palette.textTertiary).help(help)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func showcase(_ history: HistorySummary) -> some View {
        section(String(localized: "Showcase")) {
            HStack(spacing: Space.m) {
                ForEach(history.projects.prefix(3), id: \.path) { project in
                    VStack(alignment: .leading, spacing: Space.s) {
                        Image(systemName: "folder").foregroundStyle(Palette.accent)
                        Text(URL(filePath: project.path).lastPathComponent).emphasisText()
                            .foregroundStyle(Palette.textPrimary).lineLimit(1)
                        Text(String(localized: "\(compact(project.tokens)) tokens")).captionText()
                            .foregroundStyle(Palette.textSecondary)
                        Text(project.lastActive.formatted(.relative(presentation: .named))).captionText()
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.m)
                    .raisedSurface()
                    .help(project.path)
                }
            }
        }
    }

    private func activity(_ history: HistorySummary) -> some View {
        section(String(localized: "Token activity"), trailing: {
            Picker("", selection: $mode) {
                Text(String(localized: "Daily")).tag(ProfileStats.Mode.daily)
                Text(String(localized: "Weekly")).tag(ProfileStats.Mode.weekly)
                Text(String(localized: "Cumulative")).tag(ProfileStats.Mode.cumulative)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }) {
            Heatmap(cells: ProfileStats.heatmap(history.days, mode: mode, today: .now, calendar: .current))
                .padding(Space.m)
                .frame(maxWidth: .infinity)
                .raisedSurface()
        }
    }

    private func topTools(_ history: HistorySummary) -> some View {
        section(String(localized: "Top tools")) {
            HStack(spacing: Space.s) {
                ForEach(history.tools.prefix(9), id: \.name) { tool in
                    VStack(spacing: Space.xs) {
                        Image(systemName: ToolLabel.symbol(tool.name))
                            .font(Typography.title)
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: Metrics.toolTile, height: Metrics.toolTile)
                            .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                        Text(tool.name).captionText().foregroundStyle(Palette.textTertiary).lineLimit(1)
                            .frame(width: Metrics.toolTile + Space.s)
                    }
                    .help(String(localized: "\(tool.name) · used \(tool.count) times"))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func insights(_ history: HistorySummary) -> some View {
        let effort = ProfileStats.topEffort(history.efforts)
        let agent = history.tasksByAgent.max { $0.value < $1.value }?.key
        let rows: [(String, String)] = [
            (String(localized: "Most used reasoning"), effort.map { "\($0.effort.title) · \($0.percent)%" } ?? "—"),
            (String(localized: "Most used agent"), agent?.displayName ?? "—"),
            (String(localized: "Plan mode runs"), "\(workspace.planRunCount)"),
            (String(localized: "Skills explored"), "\(history.skills.count)"),
            (String(localized: "Total skills used"), "\(history.skills.map(\.count).reduce(0, +))"),
        ]
        return section(String(localized: "Insights")) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack {
                        Text(row.0).bodyText().foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Text(row.1).emphasisText().foregroundStyle(Palette.textPrimary)
                    }
                    .padding(.horizontal, Space.m)
                    .frame(height: Metrics.row + Space.s)
                    if index < rows.count - 1 { Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, Space.m) }
                }
            }
            .raisedSurface()
        }
    }

    @ViewBuilder
    private func missing(_ history: HistorySummary) -> some View {
        let absent = HarnessKind.allCases.filter { !history.found.contains($0) }
        if !absent.isEmpty {
            VStack(spacing: Space.xxs) {
                ForEach(absent, id: \.self) { kind in
                    Text(String(localized: "No \(kind.displayName) history found.")).captionText()
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }

    private func section<Content: View, Trailing: View>(
        _ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text(title).titleText().foregroundStyle(Palette.textPrimary)
                Spacer()
                trailing()
            }
            content()
        }
    }

    // MARK: Formatting

    /// "7.2B", "380M", "45K".
    private func compact(_ n: Int) -> String {
        n.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    private func duration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private func days(_ n: Int) -> String { n == 1 ? String(localized: "1 day") : String(localized: "\(n) days") }
}
