import AppKit
import SwiftUI
import XBotCore

/// A fenced code block from a reply: monospaced, coloured, and copyable.
///
/// docs/09-ui-spec.md: "Code blocks with syntax highlighting and a copy button". The copy button is
/// the load-bearing half — a snippet a person cannot take out of the window is a snippet they
/// retype, and the one rule this product does not break is that nobody has to.
struct CodeBlockView: View {
    let code: String
    let language: String?

    @State private var copied = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                if let language {
                    Text(language)
                        .captionText()
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 0)
                copyButton
                    // Always present for VoiceOver and for a pointer that has not arrived yet;
                    // faded rather than absent so the block does not resize when hovered.
                    .opacity(hovering || copied || reduceMotion ? 1 : 0)
                    .motion(Motion.quick, value: hovering)
                    .motion(Motion.quick, value: copied)
            }
            .padding(.horizontal, Space.s)
            .padding(.top, Space.xs)

            // Horizontal scrolling rather than wrapping: a wrapped line of code reads as two
            // statements, and indentation is how a person finds their place in a snippet.
            ScrollView(.horizontal, showsIndicators: false) {
                highlighted
                    .font(Typography.mono)
                    .textSelection(.enabled)
                    .padding(.horizontal, Space.s)
                    .padding(.bottom, Space.s)
                    .padding(.top, Space.xs)
            }
        }
        .background(
            Palette.codeBackground,
            in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .strokeBorder(Palette.separator, lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            Label(
                copied
                    ? String(localized: "Copied") : String(localized: "Copy"),
                systemImage: copied ? "checkmark" : "doc.on.doc"
            )
            .captionText()
            .labelStyle(.titleAndIcon)
            .foregroundStyle(copied ? Palette.stateRunning : Palette.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Copy code"))
    }

    /// One `Text`, concatenated, so the whole snippet stays a single selectable run.
    private var highlighted: Text {
        CodeHighlight.tokens(code, language: language)
            .reduce(Text(verbatim: "")) { result, token in
                result + Text(verbatim: token.0).foregroundColor(colour(token.1))
            }
    }

    private func colour(_ token: CodeHighlight.Token) -> Color {
        switch token {
        case .plain: Palette.textPrimary
        case .keyword: Palette.codeKeyword
        case .string: Palette.codeString
        case .comment: Palette.codeComment
        case .number: Palette.codeNumber
        }
    }
}
