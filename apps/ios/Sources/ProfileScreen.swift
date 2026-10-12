import SwiftUI
import XBotRemote

/// The Mac's Profile page: who, what the agents did, and how much of each plan is left.
struct ProfileScreen: View {
    let client: RemoteClient
    @State private var profile: RemoteProfile?
    @State private var refreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let profile {
                        person(profile)
                        if !profile.usage.isEmpty { usage(profile.usage) }
                        if let stats = profile.stats, stats.lifetime == 0 && stats.tokensByAgent.isEmpty {
                            ContentUnavailableView(String(localized: "No agent history yet"), systemImage: "chart.bar",
                                                   description: Text(String(localized: "Once your agents have worked on this Mac, their activity shows here.")))
                        } else if let stats = profile.stats {
                            strip(stats)
                            Heatmap(days: stats.days)
                            if !stats.tokensByAgent.isEmpty { agents(stats) }
                            if !stats.projects.isEmpty { ranking(String(localized: "Projects"), stats.projects, unit: String(localized: "tokens")) }
                            if !stats.tools.isEmpty { ranking(String(localized: "Top tools"), stats.tools, unit: String(localized: "uses")) }
                            if !stats.skills.isEmpty { ranking(String(localized: "Skills"), stats.skills, unit: String(localized: "uses")) }
                        } else {
                            ProgressView(String(localized: "Reading your history…")).padding(.top, 30)
                        }
                    } else {
                        ProgressView().padding(.top, 80)
                    }
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await load(refresh: true) }
            .closable()
            .navigationTitle(String(localized: "Profile"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load(refresh: false) }
    }

    private func load(refresh: Bool) async {
        if case .profile(_, let found) = await client.call({ .getProfile(requestID: $0, refresh: refresh) }) { profile = found }
    }

    private func person(_ p: RemoteProfile) -> some View {
        VStack(spacing: 6) {
            Group {
                if let data = p.picture, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Text(String(p.name.prefix(1))).font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.accent)
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(Circle())
            Text(p.name).font(.title2.bold())
            Text(verbatim: "@\(p.username)").foregroundStyle(.secondary)
        }
    }

    private func strip(_ s: RemoteProfile.Stats) -> some View {
        HStack(spacing: 0) {
            stat(Self.compact(s.lifetime), String(localized: "Lifetime tokens"))
            stat(Self.compact(s.peak), String(localized: "Best day"))
            stat("\(s.currentStreak)", String(localized: "Day streak"))
            stat("\(s.longestStreak)", String(localized: "Longest"))
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func agents(_ s: RemoteProfile.Stats) -> some View {
        card(String(localized: "Agents")) {
            ForEach(s.tokensByAgent.sorted { $0.value > $1.value }, id: \.key) { agent, tokens in
                HStack {
                    Circle().fill(Theme.agentColor(agent)).frame(width: 8, height: 8)
                    Text(client.agent(agent)?.name ?? agent)
                    Spacer()
                    Text(String(localized: "\(Self.compact(tokens)) tokens · \(s.tasksByAgent[agent] ?? 0) tasks"))
                        .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if s.planRuns > 0 {
                Text(String(localized: "\(s.planRuns) plans run")).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func ranking(_ title: String, _ items: [RemoteCount], unit: String) -> some View {
        let top = max(items.first?.count ?? 1, 1)
        return card(title) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.name).lineLimit(1)
                        Spacer()
                        Text("\(Self.compact(item.count)) \(unit)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    GeometryReader { g in
                        Capsule().fill(Theme.accent.opacity(0.7)).frame(width: max(4, g.size.width * CGFloat(item.count) / CGFloat(top)))
                    }
                    .frame(height: 5)
                }
            }
        }
    }

    private func usage(_ list: [RemoteUsage]) -> some View {
        card(String(localized: "Plan usage")) {
            ForEach(list) { u in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(client.agent(u.agent)?.name ?? u.agent).font(.subheadline.weight(.semibold))
                        if let plan = u.plan { Text(plan.capitalized).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text(u.updatedAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.tertiary)
                    }
                    if let used = u.fiveHourUsed { meter(String(localized: "5 hours"), used, u.fiveHourResets) }
                    if let used = u.weeklyUsed { meter(String(localized: "Week"), used, u.weeklyResets) }
                }
            }
        }
    }

    private func meter(_ label: String, _ used: Double, _ resets: Date?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.footnote)
                Spacer()
                Text(String(localized: "\(Int((100 - used).rounded()))% left")).font(.footnote.monospacedDigit())
                    .foregroundStyle(used > 85 ? .red : .secondary)
            }
            ProgressView(value: min(max(used, 0), 100), total: 100).tint(used > 85 ? .red : Theme.accent)
            if let resets {
                Text(resets > .now ? String(localized: "Resets \(resets.formatted(.relative(presentation: .named)))")
                                   : String(localized: "Reset since; updates on the agent's next run"))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    static func compact(_ n: Int) -> String {
        n.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
}

/// The last 26 weeks, a square per day, darker for busier days.
private struct Heatmap: View {
    let days: [String: Int]
    private let weeks = 26

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today) - calendar.firstWeekday
        let start = calendar.date(byAdding: .day, value: -((weeks - 1) * 7 + (weekday + 7) % 7), to: today) ?? today
        let peak = max(days.values.max() ?? 1, 1)
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Activity")).font(.headline)
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { day in
                            let date = calendar.date(byAdding: .day, value: week * 7 + day, to: start) ?? today
                            let value = days[formatter.string(from: date)] ?? 0
                            RoundedRectangle(cornerRadius: 2)
                                .fill(date > today ? Color.clear : value == 0 ? Color(.systemGray5) : Theme.accent.opacity(0.25 + 0.75 * Double(value) / Double(peak)))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Activity over the last 26 weeks"))
    }
}
