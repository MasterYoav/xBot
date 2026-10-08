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
                Card(title: String(localized: "No plan"), meta: String(localized: "Read-only planning")) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Label(plan.problem ?? "", systemImage: "exclamationmark.triangle.fill")
                            .bodyText()
                            .foregroundStyle(Palette.failure)
                        if !plan.reply.isEmpty { MarkdownText(text: plan.reply) }
                    }
                    .padding(.horizontal, Space.s)
                    .padding(.bottom, Space.s)
                } footer: {
                    CardFooter(String(localized: "Stopped")) {
                        Button(String(localized: "Try again")) { workspace.retryPlanning(messageID, in: chatID) }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(workspace.isRunning(chatID))
                    }
                }
            case .stopped where plan.isCancelled:
                MonoLabel(String(localized: "Plan cancelled"))
            default:
                TasksCard(plan: plan)
                if let closing = plan.closing {
                    MarkdownText(text: closing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The planning turn, investigating: what it is reading, live.
private struct PlanningCard: View {
    let plan: Plan

    var body: some View {
        Card(title: String(localized: "Planning…"), meta: String(localized: "Read-only")) {
            InsetPanel {
                VStack(alignment: .leading, spacing: Space.xs) {
                    if plan.investigation.isEmpty {
                        HStack(spacing: Space.s) {
                            ProgressView().controlSize(.mini)
                            Text(String(localized: "Looking around the project")).captionText()
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    ForEach(plan.investigation, id: \.id) { ToolLine(tool: $0) }
                }
            }
            .padding(.bottom, Space.xs)
        }
    }
}
