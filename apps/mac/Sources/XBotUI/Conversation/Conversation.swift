import SwiftUI
import XBotCore
import XBotEngine

/// The middle column: header, messages, composer.
public struct Conversation: View {
    @Environment(AppState.self) private var state

    /// Whether the user is reading rather than following the stream.
    ///
    /// Set the moment they scroll away from the bottom, and it stops the auto-pin. Yanking somebody
    /// back to the latest token mid-read is the single most-hated behaviour in a chat UI, so the
    /// pin is a default rather than a rule.
    @State private var isPinnedToBottom = true

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.separator)
            messages
            composer
        }
        .background(Palette.windowBackground)
    }

    private var header: some View {
        ZStack {
            HStack(spacing: Space.s) {
                if let agent = state.selectedAgent {
                    AgentAvatar(agent: agent, size: .small)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(agent.name).bodyEmphasis()
                        Text(agent.label)
                            .captionText()
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)

            // Floating, centred, over the content — not part of the layout.
            if let status = state.status {
                StatusPill(text: status.sentence)
            }
        }
        .motion(Motion.panel, value: state.status)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Space.m) {
                    if state.messages.isEmpty {
                        emptyState
                    }
                    ForEach(state.messages) { message in
                        MessageBubble(message: message)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(message.id)
                    }
                    // An anchor rather than scrolling to the last message: a message that is still
                    // streaming changes height on every token, and scrolling to it re-targets mid
                    // animation. A zero-height view at the end does not move.
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.l)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: state.messages.last?.text) {
                guard isPinnedToBottom else { return }
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
            .onChange(of: state.selectedAgentID) {
                isPinnedToBottom = true
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        // Never "No messages." An empty state says what to do, and it must not imply emptiness when
        // the real cause is that something is down — which is why it reads the block, not the count.
        VStack(spacing: Space.s) {
            Text(emptyTitle).sectionTitle()
            Text(emptySubtitle)
                .captionText()
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxl)
    }

    private var emptyTitle: String {
        if state.composerBlock == .engineNotRunning {
            return String(localized: "The engine isn't running")
        }
        return String(localized: "Say something to \(state.selectedAgent?.name ?? "your agent")")
    }

    private var emptySubtitle: String {
        if state.composerBlock == .engineNotRunning {
            return String(localized: "Start it to pick up where you left off.")
        }
        return String(localized: "It has a browser, files, and a shell — and only the tools you grant it.")
    }

    private var composer: some View {
        Composer(
            agentName: state.selectedAgent?.name ?? String(localized: "your agent"),
            block: state.composerBlock,
            onSend: { state.send($0) }
        )
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.m)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }

    private static let bottomAnchor = "conversation-bottom"
}
