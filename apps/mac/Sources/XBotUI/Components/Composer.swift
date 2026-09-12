import SwiftUI
import XBotEngine

/// The message field.
///
/// Grows to five lines then scrolls. ⏎ sends, ⇧⏎ newlines — not configurable, because every other
/// chat app on this machine works that way and this is the one place familiarity beats preference.
public struct Composer: View {
    private let agentName: String
    private let block: ComposerBlock?
    /// Why sending has to wait, when it does. Typing never waits — see `send()`.
    private let sendBlockedReason: String?
    private let onSend: (String) -> Void
    private let onBlockAction: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    public init(
        agentName: String,
        block: ComposerBlock?,
        sendBlockedReason: String? = nil,
        onSend: @escaping (String) -> Void,
        onBlockAction: @escaping () -> Void = {}
    ) {
        self.agentName = agentName
        self.block = block
        self.sendBlockedReason = sendBlockedReason
        self.onSend = onSend
        self.onBlockAction = onBlockAction
    }

    public var body: some View {
        VStack(spacing: Space.s) {
            if let block {
                // The reason sits where the user is looking, next to the thing it disables. Not a
                // toast: a toast is gone before somebody reading the field has looked up.
                HStack(spacing: Space.s) {
                    Text(block.sentence).captionText().foregroundStyle(Palette.textSecondary)
                    if !block.actionTitle.isEmpty {
                        Button(block.actionTitle, action: onBlockAction)
                            .buttonStyle(.link)
                            .font(Typography.caption)
                    }
                    Spacer()
                }
            } else if let sendBlockedReason {
                // Same place, same rule: a field that will not send says why, beside itself.
                HStack(spacing: Space.s) {
                    Text(sendBlockedReason).captionText().foregroundStyle(Palette.textSecondary)
                    Spacer()
                }
            }

            /*
             * No attach button, and no microphone.
             *
             * Both were drawn from docs/09 and both did nothing when clicked, which is the failure
             * this product's seventh invariant is about: a control that no-ops is worse than a
             * control that is absent, because absent is honest and dead is a bug the person blames
             * themselves for.
             *
             * Attach cannot work yet. The engine has no attachment path — `agents/message-text.ts`
             * says so in as many words, "the day attachments ship" — so the button needs upstream to
             * gain a feature first, and inventing one here is the re-engineering CLAUDE.md rules out.
             *
             * The microphone needs nothing, because macOS already does it. System dictation works in
             * any standard text field, this one included, and it is the recogniser docs/09 asked for
             * reached the way the person already knows. A button of ours would be a second, worse
             * door to the same room, with a permission prompt in front of it.
             */
            HStack(alignment: .bottom, spacing: Space.s) {
                TextField(
                    String(localized: "Message \(agentName)"),
                    text: $text,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .bodyText()
                .lineLimit(1...5)
                .focused($focused)
                /*
                 * Disabled only for a block, never while a reply is running.
                 *
                 * Somebody reading a reply is usually composing the next message in their head, and
                 * a field that greys out under them for the length of an answer throws that away. So
                 * the field stays open and only the send waits, with the reason shown above it.
                 */
                .disabled(block.map { !$0.sendStartsEngine } ?? false)
                .onSubmit(send)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .background(
                Palette.elevatedSurface,
                in: RoundedRectangle(cornerRadius: Radius.xlarge, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xlarge, style: .continuous)
                    .strokeBorder(Palette.separator, lineWidth: 1)
            )
            .opacity(block == nil ? 1 : 0.6)
        }
        .motion(Motion.quick, value: block)
        .motion(Motion.quick, value: sendBlockedReason)
    }

    private func send() {
        // Returns before the field is cleared, so a send that has to wait keeps what was typed.
        guard block?.sendStartsEngine ?? true, sendBlockedReason == nil else { return }
        let outgoing = text
        guard !outgoing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Cleared before the send, not after it resolves: the field must be ready for the next
        // message immediately, and the text is safe because the bubble already holds it.
        text = ""
        onSend(outgoing)
    }
}
