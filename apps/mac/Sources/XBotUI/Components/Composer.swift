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

            HStack(alignment: .bottom, spacing: Space.s) {
                Button {
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(XBotButtonStyle())
                .accessibilityLabel(String(localized: "Attach"))

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

                Button {
                } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(XBotButtonStyle())
                .accessibilityLabel(String(localized: "Dictate"))
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
