import SwiftUI
import XBotRemote

/// Home: how much of the plan is left, who's working, the latest chats, and the other places.
struct HomeScreen: View {
    let client: RemoteClient
    let nav: Navigator
    let tools: Namespace.ID
    @State private var usage: [RemoteUsage] = []

    private var running: [RemoteChat] { client.chats.filter(\.isRunning) }
    private var today: [RemoteChat] { client.chats.filter { Calendar.current.isDateInToday($0.updatedAt) } }
    private var working: [RemoteResident] { client.world?.residents.filter { $0.status == "working" } ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                HStack(spacing: 12) {
                    MetricTile(title: String(localized: "Working"), symbol: "waveform", tint: Glass.glow, value: "\(running.count)",
                               detail: running.isEmpty ? String(localized: "All quiet") : String(localized: "chats running")) {
                        nav.tab = .agents
                    }
                    MetricTile(title: String(localized: "Today"), symbol: "bubble.left.and.text.bubble.right.fill", tint: Glass.violet,
                               value: "\(today.count)", detail: String(localized: "chats")) {
                        nav.tab = .chats
                    }
                }
                if !running.isEmpty { workingCard }
                if !client.chats.isEmpty {
                    SectionTitle(title: String(localized: "Recent")) { nav.tab = .chats }
                    recentCard
                }
                SectionTitle(title: String(localized: "Places"))
                places
            }
            .padding(.horizontal, Glass.margin)
            .padding(.bottom, 30)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .background(alignment: .top) {
            RadialGradient(colors: [glowColor.opacity(0.24), .clear], center: .top, startRadius: 10, endRadius: 420)
                .frame(height: 520).ignoresSafeArea().allowsHitTesting(false)
        }
        .refreshable { await loadUsage(refresh: true) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { macMenu }
            ToolbarItem(placement: .topBarTrailing) {
                Button { nav.newChat() } label: { Image(systemName: "plus") }
                    .accessibilityLabel(String(localized: "New chat"))
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(client.agents.isEmpty)
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button { nav.settings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel(String(localized: "Settings"))
            }
        }
        // Again once connected: at launch Home appears before the Mac answers.
        .task(id: client.link == .local || client.link == .cloud) {
            if client.link == .local || client.link == .cloud { await loadUsage(refresh: false) }
        }
    }

    /// Home glows in the accent; the plans keep their own colours.
    private var glowColor: Color { Glass.glow }

    private func loadUsage(refresh: Bool) async {
        if case .profile(_, let profile) = await client.call(quiet: true, { .getProfile(requestID: $0, refresh: refresh) }) {
            usage = profile.usage
        }
    }

    // MARK: Pieces

    private var macMenu: some View {
        Menu {
            Section(LinkStatus.text(client)) {
                Button { nav.settings = true } label: { Label(String(localized: "Settings"), systemImage: "gearshape") }
                Button { nav.addingProject = true } label: { Label(String(localized: "Add a project…"), systemImage: "folder.badge.plus") }
            }
        } label: {
            HStack(spacing: 7) {
                Circle().fill(LinkStatus.color(client)).frame(width: 8, height: 8)
                Text(client.macName ?? String(localized: "Your Mac")).font(.system(.headline, design: .rounded, weight: .bold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
        }
        .accessibilityIdentifier("link-status")
        .accessibilityLabel(LinkStatus.text(client))
    }

    private var gauges: [PlanGauge] {
        #if DEBUG
        if let fake = ProcessInfo.processInfo.environment["XBOT_FAKE_USAGE"].flatMap(Int.init) { return PlanGauge.samples(fake) }
        #endif
        return usage.map { PlanGauge($0, name: client.agent($0.agent)?.name ?? ProviderStyle.of($0.agent).name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @ViewBuilder
    private var hero: some View {
        let gauges = gauges
        VStack(alignment: .leading, spacing: 18) {
            if gauges.isEmpty {
                ZStack {
                    ArcGauge(value: Double(today.count) / Double(max(10, today.count)))
                        .frame(width: 250, height: 250)
                    VStack(spacing: 0) {
                        Text("\(today.count)").font(.system(size: 60, weight: .heavy, design: .rounded)).monospacedDigit()
                            .foregroundStyle(LinearGradient(colors: [Glass.glow, Glass.violet], startPoint: .leading, endPoint: .trailing))
                        Text(String(localized: "chats today")).font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
            } else {
                UsageBoard(gauges: gauges) { nav.tool = .profile }
            }
            sentence(gauges.min { $0.left < $1.left })
        }
        .padding(.top, 4)
    }

    private func sentence(_ tight: PlanGauge?) -> some View {
        let dim: String = if let tight {
            String(localized: "\(tight.name) has \(Int(tight.left.rounded()))% of its \(tight.limitPhrase) left.")
        } else {
            String(localized: "\(client.chats.count) chats on \(client.macName ?? String(localized: "your Mac")).")
        }
        let bright: String = switch working.count {
        case 0: String(localized: "Everyone's free.")
        case 1: String(localized: "\(working[0].name) is working.")
        default: String(localized: "\(working.count) agents are working.")
        }
        return (Text(dim + " ").foregroundStyle(.secondary) + Text(bright).foregroundStyle(.primary))
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var workingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(String(localized: "Working now"), systemImage: "dot.radiowaves.left.and.right")
                .font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(.secondary)
            ForEach(running.prefix(4)) { chat in
                Button { nav.push(.chat(chat.id)) } label: {
                    CardRow(title: chat.title, subtitle: activity(chat), leading: AnyView(ChatMark(chat: chat))) {
                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private func activity(_ chat: RemoteChat) -> String {
        let who = chat.crewName ?? chat.agentName
        if let resident = client.world?.residents.first(where: { $0.name == chat.crewName }), let doing = resident.activity {
            return "\(who) · \(doing)"
        }
        return String(localized: "\(who) is working…")
    }

    private var recentCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(client.chats.prefix(4).enumerated()), id: \.element.id) { index, chat in
                if index > 0 { Divider().padding(.leading, 52) }
                Button { nav.push(.chat(chat.id)) } label: {
                    CardRow(title: chat.title, subtitle: chat.crewName.map { "\($0) · \(chat.agentName)" } ?? chat.agentName,
                            leading: AnyView(ChatMark(chat: chat))) {
                        Text(chat.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                            .font(.caption).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 14)
    }

    private var places: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                // Workflows only while the Mac has Jev Workflows on.
                ForEach(Tool.allCases.filter { $0 != .workflows || client.workflowsAvailable }) { tool in
                    Button { nav.tool = tool } label: {
                        VStack(spacing: 8) {
                            Image(systemName: tool.symbol)
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 66, height: 66)
                                .background(Circle().fill(LinearGradient(colors: [tool.tint, tool.tint.opacity(0.7)],
                                                                         startPoint: .top, endPoint: .bottom)))
                                .glassEffect(.regular.interactive(), in: .circle)
                                .matchedTransitionSource(id: tool, in: tools)
                            Text(tool.title).font(.system(.footnote, design: .rounded, weight: .semibold)).foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tool.title)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}
