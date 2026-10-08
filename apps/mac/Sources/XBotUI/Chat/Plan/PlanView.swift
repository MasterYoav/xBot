import SwiftUI
import XBotCore

struct PlanView: View {
    let workspace: Workspace
    let chatID: UUID
    let messageID: UUID
    let plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            switch plan.status {
            case .drafting:
                PlanningCard(plan: plan)
            case .review:
                PlanReviewCard(workspace: workspace, chatID: chatID, messageID: messageID, plan: plan)
            case .stopped where plan.problem != nil && plan.steps.isEmpty:
                VStack(alignment: .leading, spacing: Space.s) {
                    Label(plan.problem ?? "", systemImage: "exclamationmark.triangle")
                        .captionText().foregroundStyle(Palette.stateFailed)
                    if !plan.reply.isEmpty {
                        Text(MessageMarkdown.inline(plan.reply)).bodyText().textSelection(.enabled)
                    }
                    Button(String(localized: "Try again")) { workspace.retryPlanning(messageID, in: chatID) }
                        .disabled(workspace.isRunning(chatID))
                }
            case .stopped where plan.isCancelled:
                Text(String(localized: "Plan cancelled.")).captionText().foregroundStyle(Palette.textTertiary)
            default:
                TasksCard(plan: plan)
                if let closing = plan.closing {
                    Text(MessageMarkdown.inline(closing)).bodyText().textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The planning turn, investigating: "Planning…" and what it is reading.
private struct PlanningCard: View {
    let plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Planning…")).bodyEmphasis()
            }
            ForEach(plan.investigation, id: \.id) { ToolLine(tool: $0) }
                .padding(.leading, Metrics.stepIndent)
        }
    }
}
