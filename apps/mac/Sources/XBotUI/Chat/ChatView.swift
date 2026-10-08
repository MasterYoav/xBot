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
                            UserMessage(parts: message.parts)
                        } else {
                            AgentReply(harness: chat.harness, parts: message.parts,
                                       workedFor: workspace.workedFor(message.id, in: chat.id),
                                       sentAt: message.createdAt,
                                       retry: { workspace.retryLast(in: chat.id) })
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
