import SwiftUI
import XBotCore

struct ChatView: View {
    let workspace: Workspace
    let chat: Chat
    let composer: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.l) {
                    ForEach(workspace.messages(in: chat.id)) { message in
                        if let plan = message.plan {
                            PlanView(workspace: workspace, chatID: chat.id, messageID: message.id, plan: plan)
                        } else if message.role == .user {
                            UserMessage(parts: message.parts, sentAt: message.createdAt,
                                        resend: workspace.isRunning(chat.id) ? nil : { text in
                                            workspace.resend(message.id, as: text, in: chat.id)
                                        })
                        } else {
                            AgentReply(harness: chat.harness, parts: message.parts,
                                       workedFor: workspace.workedFor(message.id, in: chat.id),
                                       sentAt: message.createdAt,
                                       // Only the last reply can be retried: Retry asks the last question again.
                                       retry: message.id == workspace.messages(in: chat.id).last?.id
                                           ? { workspace.retryLast(in: chat.id) } : nil)
                        }
                    }
                    if let live = workspace.live[chat.id] {
                        AgentReply(harness: chat.harness, parts: live, isLive: true)
                    }
                }
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.xl)
                .frame(maxWidth: Metrics.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            PlanStatusBar(workspace: workspace, chatID: chat.id)
            Composer(workspace: workspace, target: .chat(chat.id), namespace: composer, addProject: {})
                .frame(maxWidth: Metrics.readingWidth)
                .padding(.horizontal, Space.xl)
                .padding(.bottom, Space.l)
                .padding(.top, Space.s)
        }
    }
}
