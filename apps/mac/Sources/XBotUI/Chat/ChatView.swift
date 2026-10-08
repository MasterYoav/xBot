import SwiftUI
import XBotCore

struct ChatView: View {
    let workspace: Workspace
    let chat: Chat
    let composer: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.xl) {
                    ForEach(workspace.messages(in: chat.id)) { message in
                        if let plan = message.plan {
                            PlanView(workspace: workspace, chatID: chat.id, messageID: message.id, plan: plan)
                        } else {
                            MessageView(role: message.role, parts: message.parts)
                        }
                    }
                    if let live = workspace.live[chat.id] {
                        MessageView(role: .assistant, parts: live, isLive: true)
                    }
                }
                .padding(Space.xl)
                .frame(maxWidth: Metrics.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            PlanStatusBar(workspace: workspace, chatID: chat.id)
            Composer(workspace: workspace, target: .chat(chat.id), namespace: composer, addProject: {})
        }
        .navigationTitle(chat.title)
        .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        chat.projectID.flatMap { id in workspace.projects.first { $0.id == id }?.path }
            ?? String(localized: "Inbox")
    }
}
