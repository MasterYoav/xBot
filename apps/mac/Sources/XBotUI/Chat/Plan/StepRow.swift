import SwiftUI
import XBotCore

/// One step: its state, its time, and — open — what it did.
struct StepRow: View {
    let step: PlanStep
    let isNext: Bool
    @State private var open = false
    @State private var showTools = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                icon.frame(width: Space.l)
                title
                Spacer()
                if let start = step.startedAt {
                    Elapsed(start: start, end: step.endedAt).captionText().foregroundStyle(Palette.textTertiary)
                }
                if !step.tools.isEmpty, step.status != .running {
                    Button { open.toggle() } label: { Image(systemName: open ? "chevron.up" : "chevron.down") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            if let note = step.note, step.status == .failed {
                Text(note).captionText().foregroundStyle(Palette.stateFailed).padding(.leading, Metrics.stepIndent + Space.s)
            }
            if step.status == .stopped {
                Text(String(localized: "Stopped")).captionText().foregroundStyle(Palette.textTertiary)
                    .padding(.leading, Metrics.stepIndent + Space.s)
            }
            if step.status == .running {
                ForEach(step.tools, id: \.id) { ToolLine(tool: $0) }
                    .padding(.leading, Metrics.stepIndent + Space.s)
            } else if open {
                summary.padding(.leading, Metrics.stepIndent + Space.s)
            }
        }
        .motion(Motion.quick, value: step.status)
        .motion(Motion.quick, value: open)
    }

    @ViewBuilder private var icon: some View {
        switch step.status {
        case .pending:
            Image(systemName: isNext ? "circle" : "circle.dashed").foregroundStyle(Palette.textTertiary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.textPrimary)
        case .failed:
            Image(systemName: "xmark").foregroundStyle(Palette.stateFailed)
        case .stopped:
            Image(systemName: "stop.circle").foregroundStyle(Palette.textTertiary)
        }
    }

    @ViewBuilder private var title: some View {
        switch step.status {
        case .running:
            Text(step.active).bodyText().foregroundStyle(Palette.accent)
        case .done:
            Text(step.title).bodyText().strikethrough().foregroundStyle(Palette.textTertiary)
        case .pending:
            Text(step.title).bodyText().foregroundStyle(isNext ? Palette.textPrimary : Palette.textSecondary)
        case .failed, .stopped:
            Text(step.title).bodyText().foregroundStyle(Palette.textPrimary)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button { showTools.toggle() } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: "square.stack.3d.up").foregroundStyle(Palette.textTertiary)
                    Text(ToolLabel.summary(of: step.tools)).captionText().foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Image(systemName: showTools ? "chevron.up" : "chevron.down").foregroundStyle(Palette.textTertiary)
                }
            }
            .buttonStyle(.plain)
            if showTools {
                ForEach(step.tools, id: \.id) { ToolLine(tool: $0) }.padding(.leading, Metrics.stepIndent)
            }
        }
    }
}

/// "Reading lib/api.ts" while it runs; "Read app/search/page.tsx   64 lines  1.4s" after.
struct ToolLine: View {
    let tool: ToolPart

    var body: some View {
        let running = tool.output == nil
        HStack(spacing: Space.s) {
            if running {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: tool.isError ? "exclamationmark.circle" : ToolLabel.symbol(tool.name))
                    .foregroundStyle(tool.isError ? Palette.stateFailed : Palette.textTertiary)
            }
            Text(ToolLabel.verb(tool.name, running: running)).captionText()
                .foregroundStyle(running ? Palette.accent : Palette.textSecondary)
            Text(tool.summary).font(Typography.mono).foregroundStyle(running ? Palette.accent : Palette.textSecondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            if let size = tool.size { Text(size).captionText().foregroundStyle(Palette.textTertiary) }
            if let start = tool.startedAt {
                if let end = tool.endedAt {
                    Text(Elapsed.short(end.timeIntervalSince(start))).captionText().foregroundStyle(Palette.textTertiary)
                } else {
                    Elapsed(start: start, end: nil).captionText().foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }
}
