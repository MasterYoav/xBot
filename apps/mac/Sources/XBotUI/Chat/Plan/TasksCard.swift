import SwiftUI
import XBotCore

/// "On it." The plan as it runs: progress, the latest note, and every step.
struct TasksCard: View {
    let plan: Plan
    @State private var collapsed = false
    @State private var showCompleted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(String(localized: "On it. I'll keep this list updated as I go.")).bodyText()
            VStack(alignment: .leading, spacing: Space.s) {
                header
                progress
                if !collapsed {
                    if !plan.note.isEmpty {
                        Text(plan.note).captionText().foregroundStyle(Palette.textSecondary)
                    }
                    rows
                    if plan.added > 0 {
                        Text(plan.added == 1 ? String(localized: "Plan updated · 1 added")
                                             : String(localized: "Plan updated · \(plan.added) added"))
                            .captionText()
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }
        .motion(Motion.quick, value: collapsed)
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            Text(String(localized: "Tasks")).emphasisText()
            Text(counts).captionText().foregroundStyle(Palette.textSecondary)
            Spacer()
            if let start = plan.startedAt {
                Elapsed(start: start, end: plan.status == .running ? nil : plan.endedAt)
                    .captionText()
                    .foregroundStyle(Palette.textTertiary)
            }
            Button { collapsed.toggle() } label: { Image(systemName: collapsed ? "chevron.down" : "chevron.up") }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private var counts: String {
        let done = String(localized: "\(plan.doneCount) of \(plan.steps.count) done")
        return plan.failedCount == 0 ? done : done + String(localized: " · \(plan.failedCount) failed")
    }

    private var progress: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.hairline)
                Capsule()
                    .fill(plan.failedCount > 0 ? Palette.failure : Palette.textPrimary)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: Metrics.progressHeight)
        .motion(Motion.standard, value: fraction)
    }

    private var fraction: CGFloat {
        plan.steps.isEmpty ? 0 : CGFloat(plan.doneCount + plan.failedCount) / CGFloat(plan.steps.count)
    }

    /// While running, three or more finished steps above the running one fold into one row.
    @ViewBuilder private var rows: some View {
        let running = plan.steps.firstIndex { $0.status == .running }
        let folded = running.map { plan.steps[..<$0].prefix { $0.status == .done }.count } ?? 0
        let next = plan.steps.firstIndex { $0.status == .pending }
        VStack(alignment: .leading, spacing: Space.s) {
            if plan.status == .running, folded >= 3, !showCompleted {
                Button { showCompleted = true } label: {
                    HStack(spacing: Space.s) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.textPrimary)
                        Text(String(localized: "\(folded) completed")).bodyText()
                        Image(systemName: "chevron.down").captionText().foregroundStyle(Palette.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                segments(from: folded, next: next)
            } else {
                segments(from: 0, next: next)
            }
        }
    }

    /// Steps in runs. While the plan runs, a run of steps the agent added sits on a soft panel, so
    /// the person can see what changed; once it is over they read as ordinary steps.
    private func segments(from start: Int, next: Int?) -> some View {
        let runs = Self.runs(plan.steps, from: start, highlightAdded: plan.status == .running)
        return ForEach(runs, id: \.first) { run in
            let rows = VStack(alignment: .leading, spacing: Space.s) {
                ForEach(run.indices, id: \.self) { index in
                    StepRow(step: plan.steps[index], isNext: index == next)
                }
            }
            if run.highlighted {
                rows
                    .padding(Space.s)
                    .background(Palette.raised,
                                in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                    .padding(.horizontal, -Space.s)
            } else {
                rows
            }
        }
    }

    struct Run: Equatable {
        var indices: [Int]
        var highlighted: Bool
        var first: Int { indices[0] }
    }

    /// Consecutive steps that share "added and highlighted", from `start` on.
    static func runs(_ steps: [PlanStep], from start: Int, highlightAdded: Bool) -> [Run] {
        var runs: [Run] = []
        for index in steps.indices where index >= start {
            let highlighted = highlightAdded && steps[index].added
            if let last = runs.last, last.highlighted == highlighted {
                runs[runs.count - 1].indices.append(index)
            } else {
                runs.append(Run(indices: [index], highlighted: highlighted))
            }
        }
        return runs
    }
}
