import SwiftUI
import XBotCore

/// A reply's text: prose, headings, lists and code, at reading size.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s + Space.xxs) {
            ForEach(MessageMarkdown.blocks(of: text)) { block in
                switch block {
                case .prose(let prose):
                    Text(Self.inline(prose)).readingText().textSelection(.enabled)
                case .heading(let title, let level):
                    Text(Self.inline(title))
                        .xbotFont(level == 1 ? Typography.title : Typography.emphasis, tracking: level == 1 ? -0.2 : 0)
                        .padding(.top, Space.xs)
                case .list(let items, let ordered):
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                                Text(verbatim: ordered ? "\(index + 1)." : "•")
                                    .readingText()
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.textTertiary)
                                    .frame(minWidth: Space.l, alignment: .trailing)
                                Text(Self.inline(item)).readingText().textSelection(.enabled)
                            }
                        }
                    }
                case .code(let code, let language):
                    CodeBlockView(code: code, language: language)
                }
            }
        }
        .foregroundStyle(Palette.textPrimary)
    }

    /// Inline markdown, with code spans drawn as small inset chips.
    static func inline(_ text: String) -> AttributedString {
        var attributed = MessageMarkdown.inline(text)
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].font = Typography.mono
            attributed[run.range].backgroundColor = Palette.inset
        }
        return attributed
    }
}
