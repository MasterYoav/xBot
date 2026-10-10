import SwiftUI
import XBotCore

struct ChatView: View {
    let workspace: Workspace
    let chat: Chat
    let composer: Namespace.ID

    private var agent: Agent? { workspace.agent(chat.agentID) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.l) {
                    if let agent, workspace.messages(in: chat.id).isEmpty, workspace.live[chat.id] == nil {
                        AgentGreeting(agent: agent)
                    }
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
                                           ? { workspace.retryLast(in: chat.id) } : nil,
                                       agent: agent, crew: workspace.agents,
                                       openAgent: { workspace.openLatestChat(with: $0) })
                        }
                    }
                    if let live = workspace.live[chat.id] {
                        AgentReply(harness: chat.harness, parts: live, isLive: true, agent: agent, crew: workspace.agents)
                    }
                }
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.xl)
                .frame(maxWidth: Metrics.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .environment(\.runInTerminal, { [workspace, id = chat.id] command in
                withAnimation(.spring(duration: 0.3, bounce: 0)) { workspace.runInTerminal(command, in: id) }
            })
            PlanStatusBar(workspace: workspace, chatID: chat.id)
            Composer(workspace: workspace, target: .chat(chat.id), namespace: composer, addProject: {})
                .frame(maxWidth: Metrics.readingWidth)
                .padding(.horizontal, Space.xl)
                .padding(.bottom, Space.l)
                .padding(.top, Space.s)
        }
    }
}

/// An empty chat with a crew member: them, standing there, ready.
private struct AgentGreeting: View {
    let agent: Agent

    var body: some View {
        VStack(spacing: Space.m) {
            ZStack(alignment: .bottom) {
                Ellipse().fill(.black.opacity(0.18)).frame(width: 70, height: 12).offset(y: 4)
                LivingAvatar(avatar: agent.avatar, pixel: 5, seed: agent.id.hashValue)
            }
            VStack(spacing: Space.xs) {
                Text(agent.name).titleText().foregroundStyle(Palette.textPrimary)
                Text(agent.role).bodyText().foregroundStyle(Palette.textSecondary)
            }
            Text(agent.isHeadMaster
                 ? String(localized: "Tell \(agent.name) what you're after. Big things get planned and shared out to the crew.")
                 : String(localized: "Tell \(agent.name) what you need."))
                .captionText().foregroundStyle(Palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xxl * 2)
    }
}
