import SwiftUI
import XBotEngine

/// One message. Incoming light and left; outgoing near-black and right; both capped so a bubble
/// never spans the conversation.
public struct MessageBubble: View {
    private let message: Message
    private let onRetry: () -> Void

    public init(message: Message, onRetry: @escaping () -> Void = {}) {
        self.message = message
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: Space.xs) {
            ForEach(message.toolCalls) { call in
                HStack(spacing: Space.s) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 11, weight: .medium))
                    Text(call.name).captionText()
                    if !call.target.isEmpty {
                        Text(call.target)
                            .captionText()
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.xs)
                .background(
                    Palette.elevatedSurface,
                    in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                )
            }

            if !message.text.isEmpty {
                Text(message.text)
                    .bodyText()
                    .textSelection(.enabled)
                    .foregroundStyle(
                        message.isFromUser ? Palette.bubbleOutgoingText : Palette.bubbleIncomingText
                    )
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .background(
                        message.isFromUser ? Palette.bubbleOutgoing : Palette.bubbleIncoming,
                        in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    )
                    .opacity(isSending ? 0.55 : 1)
            }

            if case .failed(let reason) = message.state {
                // Inline, with the reason and an action. Never a modal, and never a bare
                // "something went wrong" — the text the user typed is still in the bubble above.
                HStack(spacing: Space.s) {
                    Text(reason).captionText().foregroundStyle(Palette.stateFailed)
                    Button(String(localized: "Retry"), action: onRetry)
                        .buttonStyle(.link)
                        .font(Typography.caption)
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: message.isFromUser ? .trailing : .leading
        )
        .motion(Motion.quick, value: message.state)
    }

    private var isSending: Bool {
        if case .sending = message.state { return true }
        return false
    }
}
