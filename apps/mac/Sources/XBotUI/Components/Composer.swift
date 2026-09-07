import SwiftUI
import XBotEngine

/// The message field.
///
/// Grows to five lines then scrolls. ⏎ sends, ⇧⏎ newlines — not configurable, because every other
/// chat app on this machine works that way and this is the one place familiarity beats preference.
public struct Composer: View {
    private let agentName: String
    private let block: ComposerBlock?
    private let onSend: (String) -> Void
    private let onBlockAction: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    public init(
        agentName: String,
        block: ComposerBlock?,
        onSend: @escaping (String) -> Void,
        onBlockAction: @escaping () -> Void = {}
    ) {
        self.agentName = agentName
        self.block = block
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
                .disabled(block != nil)
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
    }

    private func send() {
        let outgoing = text
        guard !outgoing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Cleared before the send, not after it resolves: the field must be ready for the next
        // message immediately, and the text is safe because the bubble already holds it.
        text = ""
        onSend(outgoing)
    }
}
