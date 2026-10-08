import SwiftUI
import XBotCore

/// "Finished · 1 failed", or "Stopped" with Resume, for the chat's latest plan.
struct PlanStatusBar: View {
    let workspace: Workspace
    let chatID: UUID

    var body: some View {
        if let found = workspace.latestPlan(in: chatID), found.plan.startedAt != nil,
           found.plan.status == .finished || found.plan.status == .stopped {
            let (messageID, plan) = found
            HStack(spacing: Space.s) {
                StatusPill(plan.status == .finished ? (plan.failedCount == 0 ? .success : .warning) : .failure,
                           label(plan))
                if plan.status == .stopped {
                    Button(String(localized: "Resume")) { workspace.resumePlan(messageID, in: chatID) }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(workspace.isRunning(chatID))
                }
            }
            .padding(.horizontal, Space.xl)
            .frame(maxWidth: Metrics.readingWidth, alignment: .leading)
            .padding(.horizontal, Space.l)
        }
    }

    private func label(_ plan: Plan) -> String {
        let state = plan.status == .finished ? String(localized: "Finished") : String(localized: "Stopped")
        return plan.failedCount == 0 ? state : state + String(localized: " · \(plan.failedCount) failed")
    }
}
