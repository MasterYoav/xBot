import SwiftUI
import XBotRemote

/// One provider's plan on Home: how much is left in its tightest window.
struct PlanGauge: Identifiable, Equatable {
    let id: String
    let name: String
    let plan: String?
    let fiveHourLeft: Double?
    let weekLeft: Double?
    let fiveHourResets: Date?
    let weekResets: Date?

    /// 0…100: the smaller of what's left.
    var left: Double { [fiveHourLeft, weekLeft].compactMap { $0 }.min() ?? 100 }
    var tightWindow: String {
        guard let five = fiveHourLeft else { return String(localized: "week") }
        guard let week = weekLeft else { return String(localized: "5 hours") }
        return five <= week ? String(localized: "5 hours") : String(localized: "week")
    }
    var style: ProviderStyle { ProviderStyle.of(id, name: name) }
    /// "5-hour limit" / "weekly limit", for sentences.
    var limitPhrase: String {
        tightWindow == String(localized: "week") ? String(localized: "weekly limit") : String(localized: "5-hour limit")
    }

    init(_ usage: RemoteUsage, name: String) {
        id = usage.agent
        self.name = name
        plan = usage.plan
        fiveHourLeft = usage.fiveHourUsed.map { max(0, 100 - $0) }
        weekLeft = usage.weeklyUsed.map { max(0, 100 - $0) }
        fiveHourResets = usage.fiveHourResets
        weekResets = usage.weeklyResets
    }
}

/// Home's centrepiece: every connected plan at a glance, in each provider's own colours.
/// One to four plans are concentric rings; more share one arc in segments. The legend below
/// gives each plan's two windows.
struct UsageBoard: View {
    let gauges: [PlanGauge]
    let open: () -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tightest: PlanGauge? { gauges.min { $0.left < $1.left } }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                if gauges.count <= 4 {
                    RingStack(gauges: gauges, progress: shown ? 1 : 0)
                } else {
                    SegmentArc(gauges: gauges, progress: shown ? 1 : 0)
                }
                centre
            }
            .frame(width: 280, height: 268)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(gauges.map { String(localized: "\($0.name), \(Int($0.left.rounded()))% left") }.joined(separator: ". "))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("usage-board")

            legend
        }
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.spring(duration: 1.1, bounce: 0.2).delay(0.1)) { shown = true } }
        }
    }

    @ViewBuilder private var centre: some View {
        if let tight = tightest {
            VStack(spacing: 2) {
                Text("\(Int(tight.left.rounded()))%")
                    .font(.system(size: gauges.count > 2 ? 46 : 58, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tight.style.gradient)
                    .contentTransition(.numericText())
                Text(String(localized: "left on \(tight.name)"))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(tight.tightWindow.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: gauges.count > 2 ? 150 : 180)
            .offset(y: 6)
        }
    }

    private var legend: some View {
        VStack(spacing: 0) {
            ForEach(Array(gauges.enumerated()), id: \.element.id) { index, gauge in
                if index > 0 { Divider().padding(.leading, 46) }
                PlanRow(gauge: gauge, compact: gauges.count > 3)
                    .padding(.vertical, gauges.count > 3 ? 9 : 12)
            }
        }
        .card(padding: 16)
        .onTapGesture(perform: open)
    }
}

/// Concentric open rings, outermost first, each in its provider's gradient with a glowing tip.
private struct RingStack: View {
    let gauges: [PlanGauge]
    let progress: Double

    static let sweep = 0.75   // 270°, open at the bottom

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height + 30)
            let count = max(gauges.count, 1)
            let width: CGFloat = [26, 22, 18, 15][min(count, 4) - 1]
            let gap: CGFloat = 6
            ZStack {
                ForEach(Array(gauges.enumerated()), id: \.element.id) { index, gauge in
                    let inset = CGFloat(index) * (width + gap)
                    Ring(gauge: gauge, value: gauge.left / 100 * progress, width: width)
                        .frame(width: side - inset * 2, height: side - inset * 2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .offset(y: 14)
        }
    }
}

private struct Ring: View {
    let gauge: PlanGauge
    let value: Double
    let width: CGFloat

    var body: some View {
        let start = 0.25 + (1 - RingStack.sweep) / 2     // from the bottom-left
        let fill = RingStack.sweep * min(max(value, 0), 1)
        let style = gauge.style
        ZStack {
            Circle().trim(from: 0, to: RingStack.sweep)
                .stroke(style.primary.opacity(0.16), style: StrokeStyle(lineWidth: width, lineCap: .round))
            Circle().trim(from: 0, to: max(fill, 0.0001))
                .stroke(AngularGradient(colors: [style.secondary, style.primary], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(fill, 0.05))),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .shadow(color: style.primary.opacity(0.55), radius: width * 0.45)
                .opacity(fill > 0.002 ? 1 : 0)
        }
        .rotationEffect(.degrees(start * 360))
    }
}

/// Five plans and more: one arc, a segment per plan, each filled by what's left.
private struct SegmentArc: View {
    let gauges: [PlanGauge]
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height + 30)
            let sweep = 0.75
            let start = 0.25 + (1 - sweep) / 2
            let gapFraction = 0.012
            let each = (sweep - gapFraction * Double(gauges.count - 1)) / Double(max(gauges.count, 1))
            ZStack {
                ForEach(Array(gauges.enumerated()), id: \.element.id) { index, gauge in
                    let from = Double(index) * (each + gapFraction)
                    let style = gauge.style
                    Circle().trim(from: from, to: from + each)
                        .stroke(style.primary.opacity(0.16), style: StrokeStyle(lineWidth: 24, lineCap: .butt))
                    Circle().trim(from: from, to: from + each * min(gauge.left / 100, 1) * progress)
                        .stroke(LinearGradient(colors: [style.secondary, style.primary], startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 24, lineCap: .butt))
                        .shadow(color: style.primary.opacity(0.5), radius: 8)
                }
            }
            .rotationEffect(.degrees(start * 360))
            .frame(width: side - 24, height: side - 24)
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(y: 14)
        }
    }
}

/// A plan in the legend: who, what's left, and both windows.
private struct PlanRow: View {
    let gauge: PlanGauge
    let compact: Bool

    var body: some View {
        let style = gauge.style
        VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            HStack(spacing: 10) {
                Text(String(gauge.name.prefix(1)))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(style.gradient))
                    .shadow(color: style.primary.opacity(0.35), radius: 6, y: 2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(gauge.name).font(.system(.headline, design: .rounded, weight: .bold)).lineLimit(1)
                    if let plan = gauge.plan {
                        Text(plan.capitalized).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text("\(Int(gauge.left.rounded()))%")
                    .font(.system(size: compact ? 20 : 24, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(style.primary)
            }
            HStack(spacing: 12) {
                if let five = gauge.fiveHourLeft { Meter(title: String(localized: "5 hours"), left: five, resets: gauge.fiveHourResets, style: style) }
                if let week = gauge.weekLeft { Meter(title: String(localized: "Week"), left: week, resets: gauge.weekResets, style: style) }
            }
            .padding(.leading, 42)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Meter: View {
    let title: String
    let left: Double
    let resets: Date?
    let style: ProviderStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text("\(Int(left.rounded()))%").font(.caption2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(left < 15 ? .red : .primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(style.primary.opacity(0.15))
                    Capsule().fill(LinearGradient(colors: [style.secondary, style.primary], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(5, geo.size.width * min(left, 100) / 100))
                }
            }
            .frame(height: 5)
            Text(resetText).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var resetText: String {
        guard let resets else { return " " }
        return resets > .now ? String(localized: "resets \(resets.formatted(.relative(presentation: .named)))") : String(localized: "reset")
    }
}

#if DEBUG
extension PlanGauge {
    /// Made-up plans, for checking the board with any number of providers (`XBOT_FAKE_USAGE=N`).
    static func samples(_ count: Int) -> [PlanGauge] {
        let ids = ["claude", "codex", "antigravity", "copilot", "cursor", "grok", "mistral", "opencode"]
        let names = ["Claude Code", "Codex", "Antigravity", "Copilot", "Cursor", "Grok", "Mistral", "OpenCode"]
        return (0..<min(count, ids.count)).map { i in
            PlanGauge(RemoteUsage(agent: ids[i], plan: ["max", "plus", "pro", "business", "pro", "premium", "pro", "free"][i],
                                  fiveHourUsed: Double([18, 31, 64, 8, 45, 72, 22, 90][i]), fiveHourResets: .now.addingTimeInterval(Double(i + 1) * 2400),
                                  weeklyUsed: Double([12, 5, 40, 20, 33, 61, 9, 50][i]), weeklyResets: .now.addingTimeInterval(Double(i + 2) * 86400),
                                  updatedAt: .now), name: names[i])
        }
    }
}
#endif
