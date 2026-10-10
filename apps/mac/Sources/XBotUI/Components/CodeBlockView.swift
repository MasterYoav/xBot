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
    /// Set in a chat: runs a command in its terminal. Nil elsewhere (Notes), so no Run button.
    @Environment(\.runInTerminal) private var runInTerminal
    @State private var ran = false

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
                if let runInTerminal, let command = RunnableCode.command(from: code, language: language) {
                    runButton(command, runInTerminal)
                }
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
            Palette.inset,
            in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
        )
        .onHover { hovering = $0 }
    }

    /// Always visible, unlike Copy: it's the thing the block is for.
    private func runButton(_ command: String, _ run: @escaping @MainActor (String) -> Void) -> some View {
        Button {
            run(command)
            ran = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                ran = false
            }
        } label: {
            Label(ran ? String(localized: "Sent to terminal") : String(localized: "Run"),
                  systemImage: ran ? "checkmark" : "play.fill")
                .captionText()
                .labelStyle(.titleAndIcon)
                .foregroundStyle(ran ? Palette.success : Palette.accent)
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xxs)
                .background(Capsule().fill(Palette.accent.opacity(ran ? 0 : 0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .motion(Motion.quick, value: ran)
        .help(String(localized: "Run in this chat's terminal"))
        .accessibilityLabel(String(localized: "Run in terminal"))
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
            .foregroundStyle(copied ? Palette.success : Palette.textSecondary)
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

extension EnvironmentValues {
    /// Runs a command in the current chat's terminal; set by the chat, nil elsewhere.
    @Entry var runInTerminal: (@MainActor (String) -> Void)? = nil
}
